import azure.functions as func
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, List
import pyodbc
import os
import uuid
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions  # added imports
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest
from openai import AzureOpenAI 


gpt5_endpoint = os.getenv("GPT5_ENDPOINT", "").strip()
gpt5_model_name = os.getenv("GPT5_MODEL", "").strip()
gpt5_deployment = os.getenv("GPT5_DEPLOYMENT", "").strip()
gpt5_token_provider = get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default")
gpt5_api_version = "2024-12-01-preview"



# Initialize the Function App with proper configuration
app = func.FunctionApp()
# Use managed identity credentials
credential = DefaultAzureCredential()


# Optional: log once whether storage account name env is present (non-fatal)
STORAGE_ACCOUNT_NAME = os.getenv("STORAGE_ACCOUNT_NAME")
if STORAGE_ACCOUNT_NAME:
    logging.info(f'STORAGE_ACCOUNT_NAME detected: {STORAGE_ACCOUNT_NAME}')

# Helper: build blob service client (connection string preferred, else MSI)
def _get_blob_service_client() -> BlobServiceClient:
    conn = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
    acct = os.getenv("STORAGE_ACCOUNT_NAME")
    if conn:
        logging.info("Using AZURE_STORAGE_CONNECTION_STRING for BlobServiceClient")
        return BlobServiceClient.from_connection_string(conn)
    if acct:
        logging.info("Using managed identity for BlobServiceClient (no connection string)")
        return BlobServiceClient(account_url=f"https://{acct}.blob.core.windows.net", credential=credential)
    raise RuntimeError("Storage not configured: set AZURE_STORAGE_CONNECTION_STRING or STORAGE_ACCOUNT_NAME")

# Document Intelligence configuration (fixed wrong env var name)
DOC_INTEL_ENDPOINT = os.getenv("DOCUMENT_INTELLIGENCE_ENDPOINT", "").strip()
DOC_INTEL_KEY = os.getenv("DOCUMENT_INTELLIGENCE_KEY", "").strip()
DOC_INTEL_REGION = os.getenv("DOCUMENT_INTELLIGENCE_REGION", "").strip()

# --- Added SAS generation helper ---
def generate_blob_sas_url(blob_service_client: BlobServiceClient, container: str, blob_name: str, hours: int = 1):
    """
    Generate a read-only user delegation SAS URL for a blob using ONLY managed identity (AAD).
    Ignores any shared key / connection string on the passed client to avoid AuthenticationFailed
    ('Only authentication scheme Bearer is supported') when requesting user delegation key.
    """
    # account_name may be None depending on how the client was constructed; provide a safe fallback
    account_name = getattr(blob_service_client, "account_name", None)
    if not account_name:
        account_name = os.getenv("STORAGE_ACCOUNT_NAME")
    if not account_name:
        logging.error("Storage account name not found for SAS generation; set STORAGE_ACCOUNT_NAME or use a BlobServiceClient with account_name.")
        return ''

    expiry = datetime.utcnow() + timedelta(hours=hours)
    try:
        # Always build an AAD-authenticated client (even if original was from connection string)
        if os.getenv("AZURE_STORAGE_CONNECTION_STRING"):
            logging.debug("SAS: Re-initializing BlobServiceClient with managed identity for user delegation key.")
        aad_client = BlobServiceClient(
            account_url=f"https://{account_name}.blob.core.windows.net",
            credential=credential
        )

        delegation_key = aad_client.get_user_delegation_key(
            key_start_time=datetime.utcnow() - timedelta(minutes=5),
            key_expiry_time=expiry
        )

        sas_token = generate_blob_sas(
            account_name=account_name,
            container_name=container,
            blob_name=blob_name,
            user_delegation_key=delegation_key,
            permission=BlobSasPermissions(read=True),
            expiry=expiry
        )
        return f"https://{account_name}.blob.core.windows.net/{container}/{blob_name}?{sas_token}"
    except Exception as ex:
        msg = str(ex)
        if "AuthorizationPermissionMismatch" in msg or "UserDelegation" in msg:
            logging.error(
                "User delegation SAS failed for %s/%s (likely missing 'Storage Blob Delegator' role). Details: %s",
                container, blob_name, ex
            )
        elif "AuthenticationFailed" in msg:
            logging.error(
                "Authentication failed obtaining user delegation key for %s/%s. Ensure the managed identity is used "
                "and has proper role assignments. Details: %s", container, blob_name, ex
            )
        else:
            logging.warning("Failed to generate user delegation SAS for %s/%s: %s", container, blob_name, ex)
        return ''

@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint to verify function app is working"""
    logging.info('Health check endpoint called')
    
    response_data = {
        "status": "healthy",
        "message": "AI Claims Automation Function App is running",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "1.0.0"
    }
    
    return func.HttpResponse(
        json.dumps(response_data, indent=2),
        status_code=200,
        mimetype="application/json"
    )

@app.route(route="process_email", methods=["POST"])
def process_email(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('process_email invoked')
    try:
        attachments_container = os.getenv("EMAIL_ATTACHMENTS_CONTAINER", "emailattachments")
        # Build client (fallback logic)
        try:
            blob_service_client = _get_blob_service_client()
        except Exception as cfg_err:
            logging.error(f'Blob client init failed: {cfg_err}', exc_info=True)
            return func.HttpResponse(
                json.dumps({"error": "Storage configuration error", "details": str(cfg_err)}),
                status_code=500,
                mimetype="application/json"
            )

        data = req.get_json()
        sender = (data.get('sender') or '').strip()
        subject = (data.get('subject') or '').strip()
        body_text = (data.get('bodyText') or '').strip()
        text = "Subject: " + subject + "\n\n" + body_text
        email_blob_uri = data.get('emailBlobUri')
        attachment_uris: List[str] = data.get('attachmentUris', [])
        event_ts = data.get('timestamp') or datetime.now(timezone.utc).isoformat()

        if not sender or not email_blob_uri:
            return func.HttpResponse(
                json.dumps({"error": "Required fields: sender, subject, emailBlobUri"}),
                status_code=400,
                mimetype="application/json"
            )

        processed = []
        for att in attachment_uris:
            blob_name = att.lstrip('/')  # normalize if path starts with /
            filetype = blob_name.rsplit('.', 1)[-1].lower()
            logging.info(f'Processing attachment {blob_name}: {filetype}')
            blob_client = blob_service_client.get_blob_client(container=attachments_container, blob=blob_name)

            extracted_text = ""
            # if filetype in ['tiff', 'tif', 'png', 'jpg', 'jpeg', 'pdf', 'doc', 'docx']:
            #     extracted_text = analyze_with_document_intelligence(blob_client)
            #     if extracted_text:
            #         logging.info(f'Extracted text length (Document Intelligence): {len(extracted_text)}')
            #     else:
            #         logging.info('No text extracted (empty or feature not configured)')

            sas_url = generate_blob_sas_url(blob_service_client, attachments_container, blob_name)

            processed.append({
                "name": blob_name,
                "type": filetype,
                "sasUrl": sas_url,
                "extractedTextPreview": extracted_text[:200] if extracted_text else ""
            })

        resp = {
            "status": "success",
            "data": {
                "sender": sender,
                "Summary": analyze_email_text(text),
            }
        }
        return func.HttpResponse(json.dumps(resp, indent=2), status_code=200, mimetype="application/json")
    except ValueError as ve:
        return func.HttpResponse(json.dumps({"error": "Invalid JSON", "details": str(ve)}),
                                 status_code=400, mimetype="application/json")
    except Exception as ex:
        logging.error(f'Unhandled error: {ex}', exc_info=True)
        return func.HttpResponse(json.dumps({"error": "Internal server error", "details": str(ex)}),
                                 status_code=500, mimetype="application/json")
    

    # --- Added: safe stubs / env checks ---
def call_vision_ocr(blob_uri: str) -> str:
    """
    Placeholder OCR extraction.
    Replace with actual Vision / Document Intelligence call.
    """
    logging.info(f'OCR stub invoked for {blob_uri}')
    return f'EXTRACTED_TEXT_FROM::{blob_uri}'

def analyze_email_text(text: str) -> str:

    gpt5_client = AzureOpenAI(
        api_version=gpt5_api_version,
        azure_endpoint=gpt5_endpoint,
        azure_ad_token_provider=gpt5_token_provider,
    )

    with open(f'./ai/gpt5_prompt.txt', 'r') as f:
        prompt = f.read()
        response = gpt5_client.chat.completions.create(
    messages=[
        {
            "role": "system",
            "content": prompt,
        },
        {
            "role": "user",
            "content": text,
        }
    ],
    max_tokens=30000,
    temperature=1.0,
    top_p=1.0,
    model=gpt5_deployment
)
    logging.info(f'Customer wants {response.choices[0].message.content}')
    return str(response.choices[0].message.content)




# def analyze_with_document_intelligence(blob_client) -> str:

#     document_intelligence_client = DocumentIntelligenceClient(endpoint=DOC_INTEL_ENDPOINT, credential=AzureKeyCredential(DOC_INTEL_KEY))
#     if not DOC_INTEL_ENDPOINT or not DOC_INTEL_KEY:
#         logging.warning('Document Intelligence not configured (missing endpoint/key); skipping analysis.')
#         return ''

#     poller = document_intelligence_client.begin_analyze_document("prebuilt-invoice", AnalyzeDocumentRequest(url_source=blob_client.url))
#     logging.info(f'Document Intelligence invoked for {blob_client.url}')
#     return f'EXTRACTED_TEXT_FROM::{blob_client.url}'

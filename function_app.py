import azure.functions as func
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, List
import pyodbc
import os
import uuid
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient  # generate_blob_sas, BlobSasPermissions removed
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
from azure.ai.documentintelligence.models import AnalyzeDocumentRequest



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

# Document Intelligence configuration (do NOT log key)
DOC_INTEL_ENDPOINT = os.getenv("DOCUMENT_INTELLIGENCE_ENDPOINTAI_DOC_INTEL_ENDPOINT", "").strip()
DOC_INTEL_KEY = os.getenv("DOCUMENT_INTELLIGENCE_KEY", "").strip()
DOC_INTEL_REGION = os.getenv("DOCUMENT_INTELLIGENCE_REGION", "").strip()

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
            if filetype in ['tiff', 'tif', 'png', 'jpg', 'jpeg', 'pdf', 'doc', 'docx']:
                extracted_text = analyze_with_document_intelligence(blob_client)
                if extracted_text:
                    logging.info(f'Extracted text length (Document Intelligence): {len(extracted_text)}')
                else:
                    logging.info('No text extracted (empty or feature not configured)')

            processed.append({
                "name": blob_name,
                "type": filetype
            })

        resp = {
            "status": "success",
            "data": {
                "sender": sender,
                "subject": subject,
                "bodyText": body_text,
                "emailBlobUri": email_blob_uri,
                "attachmentUris": attachment_uris,
                "processedAttachments": processed,
                "attachmentCount": len(attachment_uris),
                "eventTimestamp": event_ts
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

def analyze_with_document_intelligence(blob_client) -> str:
    """
    Placeholder for analyzing document using Azure Document Intelligence.
    """
    logging.info(f'Document Intelligence stub invoked for {blob_client}')
    return f'EXTRACTED_TEXT_FROM::{blob_client}'

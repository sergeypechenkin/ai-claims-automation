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


# Initialize the Function App with proper configuration
app = func.FunctionApp()
# Use managed identity credentials
credential = DefaultAzureCredential()

# --- Added: safe stubs / env checks ---
def call_vision_ocr(blob_uri: str) -> str:
    """
    Placeholder OCR extraction.
    Replace with actual Vision / Document Intelligence call.
    """
    logging.info(f'OCR stub invoked for {blob_uri}')
    return f'EXTRACTED_TEXT_FROM::{blob_uri}'

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
            logging.info(f'Processing attachment {blob_name} ({filetype})')
            # Existence check (best-effort)
            try:
                blob_client = blob_service_client.get_blob_client(container=attachments_container, blob=blob_name)
                # Optionally: blob_client.get_blob_properties()
            except Exception as bex:
                logging.warning(f'Blob client create failed for {blob_name}: {bex}')
                continue

            if filetype in ['tiff', 'tif', 'png', 'jpg', 'jpeg']:
                extracted_text = call_vision_ocr(blob_name)
                logging.debug(f'OCR extracted length={len(extracted_text)}')
            elif filetype in ['pdf', 'doc', 'docx', 'xlx', 'xlsx', 'ppt', 'pptx']:
                pass  # placeholder for future doc processing
            else:
                logging.debug(f'No special handler for type {filetype}')

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

def process_email_metadata(sender: str, subject: str, email_blob_uri: str, attachment_uris: List[str], event_timestamp: str) -> Dict[str, Any]:
    """
        processed_timestamp = datetime.now(datetime.timezone.utc).isoformat()

    Args:
        sender (str): The email sender's address.
        subject (str): The subject of the email.
        email_blob_uri (str): URI to the email blob.
        attachment_uris (List[str]): List of URIs for attachments.
        event_timestamp (str): Timestamp of the event.

    Returns:
        return {"timestamp": processed_timestamp, "analysis": analysis, "details": details}
    """
    try:
        ts = datetime.now(timezone.utc).isoformat()
        analysis = f"Email from {sender} '{subject}' stored. {len(attachment_uris)} attachment blobs."
        details = {
            "sender_domain": sender.split('@')[-1] if '@' in sender else "unknown",
            "email_blob_uri": email_blob_uri,
            "attachment_uri_count": len(attachment_uris),
            "has_attachments": len(attachment_uris) > 0,
            "event_timestamp": event_timestamp,
            "processed_by": "ai-claims-automation"
        }
        return {"timestamp": ts, "analysis": analysis, "details": details}
    except Exception as e:
        logging.error(f'processing failure: {e}', exc_info=True)
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "analysis": f"failure: {str(e)}",
            "details": {}
        }
        

def process_email_data(sender: str, subject: str, body_text: str, attachment_uris: List[str], event_timestamp: str) -> Dict[str, Any]:
    """
    Process the email data and return analysis results
    """
    try:
        ts = datetime.utcnow().isoformat()
        analysis_result = {
            "sender_domain": sender.split('@')[-1] if '@' in sender else "unknown",
            "subject_length": len(subject),
            "body_length": len(body_text),
            "attachment_uri_count": len(attachment_uris),
            "has_attachments": len(attachment_uris) > 0,
            "event_timestamp": event_timestamp,
            "processed_by": "ai-claims-automation"
        }
        analysis = f"Email from {sender} with subject '{subject}' and {len(attachment_uris)} attachment URIs processed."
        return {"timestamp": ts, "analysis": analysis, "details": analysis_result}
    except Exception as ex:
        logging.error(f'Analysis failure: {ex}', exc_info=True)
        return {"timestamp": datetime.utcnow().isoformat(), "analysis": "Analysis error", "details": {}}
        attachment_names = [att.get('name', '') for att in attachments if isinstance(att, dict)]
        total_attachment_size = sum(att.get('size', 0) for att in attachments if isinstance(att, dict))
        
        analysis_result = {
            "sender_domain": sender.split('@')[-1] if '@' in sender else "unknown",
            "body_text": body_text,
            "attachment_count": len(attachments),
            "attachment_names": attachment_names,
            "total_attachment_size": total_attachment_size,
            "processed_by": "ai-claims-automation"
        }
        
        analysis = f"Email from {sender} with subject '{subject}', {len(body_text)} characters body text, and {len(attachments)} attachments analyzed."
        
        logging.info(f'Enhanced email analysis completed: {analysis_result}')
        
        return {
            "timestamp": timestamp,
            "analysis": analysis,
            "details": analysis_result
        }

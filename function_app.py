import azure.functions as func
import json
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List

# Initialize the Function App with proper configuration
app = func.FunctionApp()

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
        data = req.get_json()
        sender = (data.get('sender') or '').strip()
        subject = (data.get('subject') or '').strip()
        email_blob_uri = data.get('emailBlobUri')
        attachment_uris: List[str] = data.get('attachmentUris', [])
        event_ts = data.get('timestamp') or datetime.now(timezone.utc).isoformat()

        if not sender or not subject or not email_blob_uri:
            return func.HttpResponse(
                json.dumps({"error": "Required fields: sender, subject, emailBlobUri"}),
                status_code=400,
                mimetype="application/json"
            )

        result = process_email_metadata(sender, subject, email_blob_uri, attachment_uris, event_ts)

        resp = {
            "status": "success",
            "message": "Email metadata processed",
            "data": {
                "sender": sender,
                "subject": subject,
                "emailBlobUri": email_blob_uri,
                "attachmentUris": attachment_uris,
                "attachmentCount": len(attachment_uris),
                "eventTimestamp": event_ts,
                "processed_at": result.get("timestamp"),
                "analysis": result.get("analysis")
            }
        }
        return func.HttpResponse(json.dumps(resp, indent=2), status_code=200, mimetype="application/json")
    except ValueError:
        return func.HttpResponse(json.dumps({"error": "Invalid JSON"}), status_code=400, mimetype="application/json")
    except Exception as ex:
        logging.error(f'Unhandled error: {ex}', exc_info=True)
        return func.HttpResponse(json.dumps({"error": "Internal server error"}), status_code=500, mimetype="application/json")

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
        
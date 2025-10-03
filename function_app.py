import azure.functions as func
import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, List
# import pyodbc
# import os
# import uuid
# from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions  # added imports
from extract_text import extract_file_info, analyze_text


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
        body_text = (data.get('bodyText') or '').strip()
        text = "Subject: " + subject + "\n\n" + "Text: " + body_text
        email_blob_uri = data.get('emailBlobUri')
        attachment_uris: List[str] = data.get('attachmentUris', [])

        if not sender or not email_blob_uri:
            return func.HttpResponse(
                json.dumps({"error": "Required fields: sender, subject, emailBlobUri"}),
                status_code=400,
                mimetype="application/json"
            )

        processed = []
        processed.append(("Email:", text))
        for att in attachment_uris:
            logging.info(f'Function cycle Processing attachment: {att}')
            blob_name = att.lstrip('/')  # normalize if path starts with /
            image_processing_result = extract_file_info(att)
            logging.info(f'Function cycle extracted result for attachment {att}: {image_processing_result}')
            processed.append((blob_name, image_processing_result))


        # Convert processed list to a single string for analysis

        processed_text = '\n\n'.join(str(item) for item in processed)
        logging.info(f'Function  Processed all attachments, text for analysis: {processed_text[:500]}...')  # Log first 500 chars
        resp = analyze_text(processed_text)
        print("-----Message Analysis Result -----","/n", resp)
        logging.info(f'Function Analysis result: {resp}')

        resp = {
            "status": "success",
            "data": {
                "sender": sender,
                "Summary": resp
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
    









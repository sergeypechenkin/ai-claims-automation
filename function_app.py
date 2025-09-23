import azure.functions as func
import json
import logging
from datetime import datetime
from typing import Dict, Any

# Initialize the Function App with proper configuration
app = func.FunctionApp()

@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint to verify function app is working"""
    logging.info('Health check endpoint called')
    
    response_data = {
        "status": "healthy",
        "message": "AI Claims Automation Function App is running",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0"
    }
    
    return func.HttpResponse(
        json.dumps(response_data, indent=2),
        status_code=200,
        mimetype="application/json"
    )

@app.route(route="process_email", methods=["POST"])
def process_email(req: func.HttpRequest) -> func.HttpResponse:
    """
    Process email information sent from Logic Apps
    Expected JSON format: {
        "sender": "email@domain.com", 
        "subject": "Email Subject",
        "bodyText": "Clean email body text without HTML formatting",
        "attachments": [{"name": "file.pdf", "size": 1024}]
    }
    """
    logging.info('Email processing function triggered')
    
    try:
        # Parse the JSON request body
        req_body = req.get_json()
        
        if not req_body:
            logging.warning('Empty or invalid JSON request body')
            return func.HttpResponse(
                json.dumps({"error": "Invalid JSON in request body"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Extract essential email data from the request
        sender = req_body.get('sender', '').strip()
        subject = req_body.get('subject', '').strip()
        body_text = req_body.get('bodyText', '').strip()
        attachments = req_body.get('attachments', [])
        
        if not sender or not subject:
            logging.warning(f'Missing required fields - sender: {bool(sender)}, subject: {bool(subject)}')
            return func.HttpResponse(
                json.dumps({"error": "Missing required fields: sender and/or subject"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Log the email information
        logging.info(f'Processing email - Sender: {sender}, Subject: {subject}, Body length: {len(body_text)}, Attachments: {len(attachments)}')
        
        # Process the email data
        result = process_email_data(sender, subject, body_text, attachments)
        
        # Return success response
        response_data = {
            "status": "success",
            "message": "Email processed successfully",
            "data": {
                "sender": sender,
                "subject": subject,
                "bodyLength": len(body_text),
                "attachmentCount": len(attachments),
                "processed_at": result.get("timestamp"),
                "result": result.get("analysis", "Email analyzed successfully"),
                "claims_related": result.get("details", {}).get("contains_keywords", False)
            }
        }
        
        logging.info(f'Email processed successfully for sender: {sender}')
        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except ValueError as e:
        logging.error(f'JSON parsing error: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": "Invalid JSON format"}),
            status_code=400,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f'Error processing email: {str(e)}', exc_info=True)
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json"
        )

def process_email_data(sender: str, subject: str, body_text: str = '', attachments: list = []) -> Dict[str, Any]:
    """
    Process the email data and return analysis results
    """
    try:
        timestamp = datetime.utcnow().isoformat()
        
        if attachments is None:
            attachments = []
        

        
        # Analyze attachments
        attachment_names = [att.get('name', '') for att in attachments if isinstance(att, dict)]
        total_attachment_size = sum(att.get('size', 0) for att in attachments if isinstance(att, dict))
        
        analysis_result = {
            "sender_domain": sender.split('@')[-1] if '@' in sender else "unknown",
            "subject_length": len(subject),
            "body_length": len(body_text),
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
        
    except Exception as e:
        logging.error(f'Error in process_email_data: {str(e)}', exc_info=True)
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "analysis": f"Error processing email: {str(e)}",
            "details": {}
        }

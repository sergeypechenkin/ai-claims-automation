import azure.functions as func
import json
import logging

app = func.FunctionApp()

@app.route(route="process_email", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def process_email(req: func.HttpRequest) -> func.HttpResponse:
    """
    Process email information sent from Logic Apps
    Expected JSON format: {"sender": "email@domain.com", "subject": "Email Subject"}
    """
    logging.info('Email processing function triggered')
    
    try:
        # Parse the JSON request body
        req_body = req.get_json()
        
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Invalid JSON in request body"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Extract sender and subject from the request
        sender = req_body.get('sender', '')
        subject = req_body.get('subject', '')
        
        if not sender or not subject:
            return func.HttpResponse(
                json.dumps({"error": "Missing required fields: sender and/or subject"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Log the email information
        logging.info(f'Processing email - Sender: {sender}, Subject: {subject}')
        
        # TODO: Add your email processing logic here
        # For example:
        # - Save to database
        # - Analyze content
        # - Trigger other processes
        
        # Process the email data
        result = process_email_data(sender, subject)
        
        # Return success response
        response_data = {
            "status": "success",
            "message": "Email processed successfully",
            "data": {
                "sender": sender,
                "subject": subject,
                "processed_at": result.get("timestamp"),
                "result": result.get("analysis", "Email logged successfully")
            }
        }
        
        return func.HttpResponse(
            json.dumps(response_data),
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
        logging.error(f'Error processing email: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json"
        )

def process_email_data(sender: str, subject: str) -> dict:
    """
    Process the email data and return analysis results
    """
    from datetime import datetime
    
    # Basic email processing logic
    timestamp = datetime.utcnow().isoformat()
    
    # TODO: Implement your specific email processing logic here
    # Examples:
    # - Extract key information from subject
    # - Categorize emails
    # - Validate sender domain
    # - Store in database
    
    analysis = f"Email from {sender} with subject '{subject}' processed"
    
    return {
        "timestamp": timestamp,
        "analysis": analysis
    }

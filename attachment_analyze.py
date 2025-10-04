#extract_text.py v2
#import base64
import logging
import os
#import re
import shutil
#from xmlrpc import client
from docx import Document
import docx2txt
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image
from io import BytesIO
import contextlib
import tempfile
from urllib.parse import urlparse
import requests
import zipfile
from azure.ai.vision.imageanalysis import ImageAnalysisClient
#from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.core.credentials import AzureKeyCredential
#from azure.core.exceptions import HttpResponseError
from azure.identity import DefaultAzureCredential
import json
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
#from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
#from azure.ai.documentintelligence.models import AnalyzeDocumentRequest
from openai import AzureOpenAI 
from datetime import datetime, timedelta
from azure.storage.blob import (BlobServiceClient, generate_blob_sas, BlobSasPermissions)
import time
import uuid

def get_gpt5_client():
    gpt5_endpoint = os.getenv("GPT5_ENDPOINT", "").strip()
    gpt5_deployment = os.getenv("GPT5_DEPLOYMENT", "").strip()
    gpt5_model_name = os.getenv("GPT5_MODEL", "").strip()
    gpt5_key = os.getenv("GPT5_KEY", "").strip()
    gpt5_api_version = "2024-12-01-preview"

    if not gpt5_endpoint:
        try:
            with open("local.settings.json", "r") as fh:
                settings = json.load(fh)["Values"]
            gpt5_endpoint = gpt5_endpoint or settings.get("GPT5_ENDPOINT", "")
            gpt5_deployment = gpt5_deployment or settings.get("GPT5_DEPLOYMENT", "")
            gpt5_model_name = gpt5_model_name or settings.get("GPT5_MODEL", "")
            gpt5_key = gpt5_key or settings.get("GPT5_KEY", "")
        except FileNotFoundError:
            pass

    if not gpt5_endpoint:
        raise RuntimeError("GPT5_ENDPOINT is missing")

    if gpt5_key:  
        # 🔑 Locally via API Key
        client = AzureOpenAI(
            api_key=gpt5_key,
            api_version=gpt5_api_version,
            azure_endpoint=gpt5_endpoint
        )
    else:  
        # 🔐 In the cloud via Managed Identity
        credential = DefaultAzureCredential()
        token_provider = get_bearer_token_provider(
            credential, "https://cognitiveservices.azure.com/.default"
        )
        client = AzureOpenAI(
            api_version=gpt5_api_version,
            azure_endpoint=gpt5_endpoint,
            azure_ad_token_provider=token_provider
        )

    return {
        "client": client,
        "deployment": gpt5_deployment,
        "model_name": gpt5_model_name
    }
def get_ai_services_client():
    endpoint = os.getenv("AI_SERVICES_ENDPOINT", "").strip()
    key = os.getenv("AI_SERVICES_KEY", "").strip()

    if not endpoint:
        try:
            with open("local.settings.json", "r") as fh:
                settings = json.load(fh)["Values"]
            endpoint = endpoint or settings.get("AI_SERVICES_ENDPOINT", "")
            key = key or settings.get("AI_SERVICES_KEY", "")
        except FileNotFoundError:
            pass

    if not endpoint:
        raise RuntimeError("AI_SERVICES_ENDPOINT is missing")

    if key:  
        credential = AzureKeyCredential(key)
    else:  
        credential = DefaultAzureCredential()

    client = ImageAnalysisClient(endpoint=endpoint, credential=credential)
    return client
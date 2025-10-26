"""
Configuration Module

Contains all application configuration constants and settings.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Cache Configuration
CACHE_DIR = Path(".cache/screenshots")
CACHE_TTL_SECONDS = 3600  # 1 hour

# Steel.dev Retry Configuration
STEEL_MAX_RETRIES = 3
STEEL_RETRY_DELAYS = [1, 2, 4]  # seconds (exponential backoff)

# API Keys and External Services
STEEL_API_KEY = os.environ.get("STEEL_API_KEY")
SERPAPI_KEY = os.environ.get("SERPAPI_KEY")
LLAMA_API_KEY = os.environ.get("LLAMA_API_KEY")

# Clerk Authentication
CLERK_SECRET_KEY = os.environ.get("CLERK_SECRET_KEY")
CLERK_PUBLISHABLE_KEY = os.environ.get("CLERK_PUBLISHABLE_KEY")

# Supabase Database
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

# AWS S3 Storage
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-2")
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME")

# LLM Configuration
LLAMA_MODEL = "Llama-4-Maverick-17B-128E-Instruct-FP8"
LLAMA_BASE_URL = "https://api.llama.com/compat/v1/"

# Server Configuration
DEFAULT_PORT = 8010

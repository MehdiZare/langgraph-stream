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

# LLM Configuration
LLAMA_MODEL = "Llama-4-Maverick-17B-128E-Instruct-FP8"
LLAMA_BASE_URL = "https://api.llama.com/compat/v1/"

# Server Configuration
DEFAULT_PORT = 8010

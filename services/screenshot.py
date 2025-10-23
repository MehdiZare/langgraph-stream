"""
Screenshot Service

Handles screenshot capture using Steel.dev API with retry logic and caching.
"""

import base64
import asyncio
from fastapi import WebSocket
from steel import Steel
import httpx

from config import STEEL_API_KEY, STEEL_MAX_RETRIES, STEEL_RETRY_DELAYS
from utils import normalize_url
from services.cache import get_cached_screenshot, save_screenshot_to_cache


def get_steel_client():
    """
    Initialize Steel client with API key.

    Returns:
        Steel client instance

    Raises:
        ValueError: If STEEL_API_KEY is not set
    """
    if not STEEL_API_KEY:
        raise ValueError("STEEL_API_KEY environment variable is not set")
    return Steel(steel_api_key=STEEL_API_KEY)


async def fetch_screenshot_with_retry(steel_client, url: str, websocket: WebSocket = None) -> tuple[str | None, bytes | None]:
    """
    Fetch screenshot with retry logic and progress updates.

    Args:
        steel_client: Steel API client instance
        url: URL to capture screenshot of
        websocket: Optional WebSocket for progress updates

    Returns:
        Tuple of (screenshot_url, screenshot_bytes) - one will be None

    Raises:
        Exception: After all retries are exhausted
    """
    last_error = None

    for attempt in range(STEEL_MAX_RETRIES):
        try:
            if attempt > 0:
                # Send retry update to user
                if websocket:
                    await websocket.send_json({
                        "type": "status",
                        "content": f"Retrying screenshot capture (attempt {attempt + 1}/{STEEL_MAX_RETRIES})..."
                    })
                # Wait with exponential backoff
                await asyncio.sleep(STEEL_RETRY_DELAYS[attempt - 1])

            # Send progress update
            if websocket:
                await websocket.send_json({
                    "type": "status",
                    "content": "Contacting Steel.dev browser..."
                })

            response = steel_client.screenshot(url=url)

            # Extract URL or bytes from response
            if hasattr(response, 'url'):
                return (response.url, None)
            elif isinstance(response, dict) and 'url' in response:
                return (response['url'], None)
            elif isinstance(response, str) and response.startswith('http'):
                return (response, None)
            elif isinstance(response, bytes):
                return (None, response)
            else:
                raise Exception("Unknown response format from Steel.dev")

        except Exception as e:
            last_error = e
            error_msg = str(e)

            # Check if it's a retryable error (5xx server errors)
            is_retryable = '500' in error_msg or '502' in error_msg or '503' in error_msg or '504' in error_msg

            if not is_retryable or attempt == STEEL_MAX_RETRIES - 1:
                # Don't retry for non-5xx errors or on last attempt
                break

    # All retries failed
    raise Exception(f"Failed to capture screenshot after {STEEL_MAX_RETRIES} attempts: {str(last_error)}")


async def capture_screenshot(url: str, websocket: WebSocket = None) -> str:
    """
    Capture a screenshot of the given URL using Steel.dev.
    Uses 1-hour file-based cache to reduce API calls.

    Args:
        url: URL to capture screenshot of
        websocket: Optional WebSocket for progress updates

    Returns:
        Base64 encoded screenshot string

    Raises:
        Exception: If screenshot capture fails
    """
    # Normalize URL for consistent caching
    normalized_url = normalize_url(url)

    # Check cache first
    cached_screenshot = get_cached_screenshot(normalized_url)
    if cached_screenshot:
        print(f"Cache hit for {normalized_url}")
        if websocket:
            await websocket.send_json({
                "type": "status",
                "content": "Using cached screenshot..."
            })
        return cached_screenshot

    print(f"Cache miss for {normalized_url}, fetching from Steel.dev")

    try:
        steel_client = get_steel_client()

        # Fetch screenshot with retry logic
        screenshot_url, screenshot_bytes = await fetch_screenshot_with_retry(
            steel_client,
            normalized_url,
            websocket
        )

        if screenshot_url:
            # Send progress update
            if websocket:
                await websocket.send_json({
                    "type": "status",
                    "content": "Downloading screenshot image..."
                })

            # Fetch the screenshot from the URL
            async with httpx.AsyncClient() as client:
                img_response = await client.get(screenshot_url)
                img_response.raise_for_status()
                screenshot_bytes = img_response.content

        # Encode to base64
        screenshot_base64 = base64.b64encode(screenshot_bytes).decode('utf-8')

        # Save to cache before returning
        save_screenshot_to_cache(normalized_url, screenshot_base64)

        return screenshot_base64

    except Exception as e:
        # Provide helpful error message
        error_detail = str(e)
        if '500' in error_detail or 'Internal Server Error' in error_detail:
            raise Exception("Steel.dev service is temporarily unavailable. Please try again in a moment.")
        elif '401' in error_detail or '403' in error_detail:
            raise Exception("Steel.dev API authentication failed. Please check your API key.")
        elif '429' in error_detail:
            raise Exception("Steel.dev rate limit exceeded. Please wait a moment before trying again.")
        else:
            raise Exception(f"Failed to capture screenshot: {error_detail}")

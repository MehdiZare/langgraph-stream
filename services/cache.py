"""
Cache Service

Manages file-based caching for screenshots to reduce API calls.
"""

import json
import time
import hashlib
from pathlib import Path
from config import CACHE_DIR, CACHE_TTL_SECONDS


def get_cache_path(url: str) -> Path:
    """
    Generate cache file path from URL using SHA-256 hash.

    Args:
        url: URL to generate cache path for

    Returns:
        Path object for cache file
    """
    url_hash = hashlib.sha256(url.encode()).hexdigest()
    return CACHE_DIR / f"{url_hash}.json"


def get_cached_screenshot(url: str) -> str | None:
    """
    Retrieve screenshot from cache if valid and not expired.

    Args:
        url: URL of the cached screenshot

    Returns:
        Base64 encoded screenshot string or None if not found/expired
    """
    cache_file = get_cache_path(url)

    if not cache_file.exists():
        return None

    try:
        with open(cache_file, 'r') as f:
            cache_data = json.load(f)

        # Check if cache is expired
        age = time.time() - cache_data['timestamp']
        if age > CACHE_TTL_SECONDS:
            # Cache expired, delete file
            cache_file.unlink()
            return None

        return cache_data['base64']
    except Exception as e:
        print(f"Cache read error: {e}")
        return None


def save_screenshot_to_cache(url: str, base64_data: str):
    """
    Save screenshot to cache.

    Args:
        url: URL of the screenshot
        base64_data: Base64 encoded screenshot data
    """
    try:
        # Ensure cache directory exists
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

        cache_data = {
            "url": url,
            "timestamp": time.time(),
            "base64": base64_data
        }

        cache_file = get_cache_path(url)
        with open(cache_file, 'w') as f:
            json.dump(cache_data, f)
    except Exception as e:
        print(f"Cache write error: {e}")


def cleanup_expired_cache():
    """
    Remove expired cache files from cache directory.

    Returns:
        Number of files cleaned up
    """
    if not CACHE_DIR.exists():
        return 0

    cleaned_count = 0
    for cache_file in CACHE_DIR.glob("*.json"):
        try:
            with open(cache_file, 'r') as f:
                cache_data = json.load(f)

            age = time.time() - cache_data['timestamp']
            if age > CACHE_TTL_SECONDS:
                cache_file.unlink()
                cleaned_count += 1
        except Exception:
            pass

    if cleaned_count > 0:
        print(f"Cleaned up {cleaned_count} expired cache file(s)")

    return cleaned_count

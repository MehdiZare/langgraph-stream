"""
Utility Functions

Contains helper functions for URL validation and normalization.
"""

from urllib.parse import urlparse


def normalize_url(url: str) -> str:
    """
    Normalize URL to lowercase for consistent caching.

    Args:
        url: URL to normalize

    Returns:
        Normalized URL in lowercase
    """
    return url.lower().strip()


def validate_url(url: str) -> bool:
    """
    Validate if the given string is a valid URL.

    Args:
        url: String to validate

    Returns:
        True if valid URL with http/https scheme, False otherwise
    """
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc]) and result.scheme in ['http', 'https']
    except Exception:
        return False

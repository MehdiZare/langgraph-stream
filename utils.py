"""
Utility Functions

Contains helper functions for URL validation and normalization.
"""

from urllib.parse import urlparse


def normalize_url(url: str) -> str:
    """
    Normalize URL for consistent caching.
    Only lowercases the protocol and domain to preserve case-sensitive paths.

    Args:
        url: URL to normalize

    Returns:
        Normalized URL with lowercase protocol and domain
    """
    url = url.strip()
    parsed = urlparse(url)

    # Lowercase only the scheme and netloc (domain)
    # Keep path, params, query, and fragment as-is (they can be case-sensitive)
    normalized = parsed._replace(
        scheme=parsed.scheme.lower(),
        netloc=parsed.netloc.lower()
    )

    return normalized.geturl()


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

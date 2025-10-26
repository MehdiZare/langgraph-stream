"""
Search Service

Handles search engine queries using SerpAPI for Google and Bing.
"""

from typing import List
from urllib.parse import urlparse
from serpapi import GoogleSearch

from config import SERPAPI_KEY
from utils import normalize_url


def search_google(keywords: List[str]) -> List[dict]:
    """
    Search Google using SerpAPI with the given keywords.

    Args:
        keywords: List of search keywords

    Returns:
        List of top 10 organic search results

    Raises:
        ValueError: If SERPAPI_KEY is not set
    """
    if not SERPAPI_KEY:
        raise ValueError("SERPAPI_KEY environment variable is not set")

    # Use the first keyword or join them for better search
    search_query = keywords[0] if keywords else ""

    params = {
        "engine": "google_light",
        "q": search_query,
        "api_key": SERPAPI_KEY,
        "num": 10  # Get top 10 results
    }

    try:
        search = GoogleSearch(params)
        results = search.get_dict()
        organic_results = results.get("organic_results", [])

        # Return only the top 10 results with relevant fields
        return organic_results[:10]
    except Exception as e:
        print(f"SerpAPI error: {e}")
        # Return empty list on error to not break the flow
        return []


def search_bing(keywords: List[str]) -> List[dict]:
    """
    Search Bing using SerpAPI with the given keywords.

    Args:
        keywords: List of search keywords

    Returns:
        List of top 10 organic search results

    Raises:
        ValueError: If SERPAPI_KEY is not set
    """
    if not SERPAPI_KEY:
        raise ValueError("SERPAPI_KEY environment variable is not set")

    # Use the first keyword or join them for better search
    search_query = keywords[0] if keywords else ""

    params = {
        "engine": "bing",
        "q": search_query,
        "cc": "US",
        "api_key": SERPAPI_KEY,
        "count": 10  # Get top 10 results
    }

    try:
        search = GoogleSearch(params)
        results = search.get_dict()
        organic_results = results.get("organic_results", [])

        # Return only the top 10 results with relevant fields
        return organic_results[:10]
    except Exception as e:
        print(f"SerpAPI Bing error: {e}")
        # Return empty list on error to not break the flow
        return []


def find_url_ranking(url: str, organic_results: List[dict]) -> int | None:
    """
    Find the position of the given URL in the organic search results.

    Args:
        url: URL to search for
        organic_results: List of organic search results

    Returns:
        Position (1-based) or None if not found in top results
    """
    # Parse the target URL and extract normalized domain
    try:
        parsed_target = urlparse(normalize_url(url))
        target_netloc = parsed_target.netloc.lower()
        # Strip "www." prefix for comparison
        if target_netloc.startswith("www."):
            target_netloc = target_netloc[4:]
    except (ValueError, AttributeError):
        return None

    for idx, result in enumerate(organic_results, start=1):
        result_url = result.get("link", "")
        if not result_url:
            continue

        try:
            # Parse result URL and extract normalized domain
            parsed_result = urlparse(normalize_url(result_url))
            result_netloc = parsed_result.netloc.lower()
            # Strip "www." prefix for comparison
            if result_netloc.startswith("www."):
                result_netloc = result_netloc[4:]

            # Match if domains are identical
            if target_netloc == result_netloc:
                return idx
        except (ValueError, AttributeError):
            continue

    return None

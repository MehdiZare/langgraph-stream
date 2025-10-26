"""
LLM Service

Handles LLM model initialization and configuration for different use cases.
"""

from langchain_openai import ChatOpenAI

from config import LLAMA_API_KEY, LLAMA_MODEL, LLAMA_BASE_URL
from models import WebsiteAnalysis, SEORecommendation


def get_llama_model():
    """
    Get Llama model configured for streaming chat.

    Returns:
        ChatOpenAI instance configured for streaming

    Raises:
        ValueError: If LLAMA_API_KEY is not set
    """
    if not LLAMA_API_KEY:
        raise ValueError("LLAMA_API_KEY environment variable is not set")

    return ChatOpenAI(
        model=LLAMA_MODEL,
        api_key=LLAMA_API_KEY,
        base_url=LLAMA_BASE_URL,
        streaming=True,
    )


def get_llama_model_structured():
    """
    Get Llama model configured for structured WebsiteAnalysis output.

    Returns:
        ChatOpenAI instance with structured output for WebsiteAnalysis

    Raises:
        ValueError: If LLAMA_API_KEY is not set
    """
    if not LLAMA_API_KEY:
        raise ValueError("LLAMA_API_KEY environment variable is not set")

    model = ChatOpenAI(
        model=LLAMA_MODEL,
        api_key=LLAMA_API_KEY,
        base_url=LLAMA_BASE_URL,
        streaming=False,  # Structured output doesn't stream
    )

    # Use LangChain's with_structured_output for Pydantic model
    return model.with_structured_output(WebsiteAnalysis)


def get_llama_model_seo():
    """
    Get Llama model configured for SEO recommendation structured output.

    Returns:
        ChatOpenAI instance with structured output for SEORecommendation

    Raises:
        ValueError: If LLAMA_API_KEY is not set
    """
    if not LLAMA_API_KEY:
        raise ValueError("LLAMA_API_KEY environment variable is not set")

    model = ChatOpenAI(
        model=LLAMA_MODEL,
        api_key=LLAMA_API_KEY,
        base_url=LLAMA_BASE_URL,
        streaming=False,  # Structured output doesn't stream
    )

    # Use LangChain's with_structured_output for Pydantic model
    return model.with_structured_output(SEORecommendation)

"""
SEO Analyzer Node

Performs SEO analysis and generates recommendations.
"""

import asyncio
from typing import List
from langchain_core.messages import HumanMessage

from models import WebsiteAnalysis, SEORecommendation
from services.llm import get_llama_model_seo
from workflow.prompts.seo import build_seo_analysis_prompt


async def analyze_seo_node(
    url: str,
    website_analysis: WebsiteAnalysis,
    google_results: List[dict],
    bing_results: List[dict],
    google_ranking: int | None,
    bing_ranking: int | None
) -> SEORecommendation:
    """
    Node for SEO analysis and recommendations from both Google and Bing.

    Args:
        url: URL of the website being analyzed
        website_analysis: WebsiteAnalysis object with website details
        google_results: Google search results
        bing_results: Bing search results
        google_ranking: Position in Google results (or None)
        bing_ranking: Position in Bing results (or None)

    Returns:
        SEORecommendation Pydantic model with structured recommendations
    """
    seo_model = get_llama_model_seo()

    # Build the SEO analysis prompt
    prompt = build_seo_analysis_prompt(
        url=url,
        website_analysis=website_analysis,
        google_results=google_results,
        bing_results=bing_results,
        google_ranking=google_ranking,
        bing_ranking=bing_ranking
    )

    # Create message
    message = HumanMessage(content=prompt)

    # Invoke the model
    seo_recommendation = await asyncio.to_thread(seo_model.invoke, [message])

    return seo_recommendation

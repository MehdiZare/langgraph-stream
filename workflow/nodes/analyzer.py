"""
Website Analyzer Node

Performs structured analysis of website screenshots.
"""

import asyncio
from langchain_core.messages import HumanMessage

from models import WebsiteAnalysis
from services.llm import get_llama_model_structured
from workflow.prompts.analysis import build_website_analysis_prompt


async def analyze_website_node(url: str, screenshot_base64: str) -> WebsiteAnalysis:
    """
    Node for structured website analysis.

    Args:
        url: URL of the website being analyzed
        screenshot_base64: Base64 encoded screenshot

    Returns:
        WebsiteAnalysis Pydantic model with structured analysis
    """
    structured_model = get_llama_model_structured()

    # Build the prompt
    prompt_text = build_website_analysis_prompt(url)

    # Create the vision message
    message = HumanMessage(
        content=[
            {
                "type": "text",
                "text": prompt_text
            },
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:image/png;base64,{screenshot_base64}"
                }
            }
        ]
    )

    # Invoke the structured model (returns WebsiteAnalysis object)
    analysis_result = await asyncio.to_thread(structured_model.invoke, [message])

    return analysis_result

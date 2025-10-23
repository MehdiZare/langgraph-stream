"""
Prompts Module

Contains prompt templates for different analysis types.
"""

from workflow.prompts.analysis import (
    build_website_analysis_prompt,
    build_streaming_description_prompt
)
from workflow.prompts.seo import build_seo_analysis_prompt

__all__ = [
    "build_website_analysis_prompt",
    "build_streaming_description_prompt",
    "build_seo_analysis_prompt",
]

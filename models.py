"""
Pydantic Models

Defines data models for structured output from LLM analysis.
"""

from typing import List, Literal
from pydantic import BaseModel, Field


class WebsiteAnalysis(BaseModel):
    """Structured analysis of a website screenshot"""

    website_type: Literal[
        "E-commerce",
        "SaaS/Software",
        "Blog/Content",
        "Portfolio",
        "Corporate/Business",
        "Landing Page",
        "News/Media",
        "Social Platform",
        "Educational",
        "Government",
        "Other"
    ] = Field(description="Primary category/type of the website")

    primary_goal: Literal[
        "Product Sales",
        "Lead Generation",
        "Information/Education",
        "Brand Awareness",
        "User Engagement",
        "Content Distribution",
        "Service Delivery",
        "Community Building",
        "Other"
    ] = Field(description="Main business objective of the website")

    description: str = Field(
        description="Brief 2-3 sentence description of the website, its purpose, and visual design"
    )

    key_features: List[str] = Field(
        description="List of 3-5 notable features, UI elements, or characteristics observed",
        min_length=3,
        max_length=5
    )

    keywords: List[str] = Field(
        description="Top 5 SEO keywords that best represent the page content and business focus",
        min_length=5,
        max_length=5
    )


class SEORecommendation(BaseModel):
    """SEO analysis and recommendations based on competitive landscape"""

    findings: str = Field(
        description="Markdown-formatted findings about the website's SEO performance and competitive position. Write in a positive, constructive tone."
    )

    recommendations: str = Field(
        description="Markdown-formatted actionable recommendations to improve SEO and competitiveness. Write in a positive, encouraging tone."
    )

    require_attention: str = Field(
        description="Markdown-formatted items that require immediate attention or quick wins. Write in a positive, motivating tone."
    )

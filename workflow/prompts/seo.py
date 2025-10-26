"""
SEO Analysis Prompts

Prompt templates for SEO analysis and recommendations.
"""

from typing import List
from models import WebsiteAnalysis


def build_seo_analysis_prompt(
    url: str,
    website_analysis: WebsiteAnalysis,
    google_results: List[dict],
    bing_results: List[dict],
    google_ranking: int | None,
    bing_ranking: int | None
) -> str:
    """
    Build comprehensive SEO analysis prompt with competitor data.

    Args:
        url: URL of the website being analyzed
        website_analysis: WebsiteAnalysis object with website details
        google_results: Google search results
        bing_results: Bing search results
        google_ranking: Position in Google results (or None)
        bing_ranking: Position in Bing results (or None)

    Returns:
        Formatted prompt string with all SEO analysis context
    """
    # Build Google competitor information
    google_competitors = ""
    for idx, result in enumerate(google_results[:5], start=1):
        title = result.get("title", "N/A")
        link = result.get("link", "N/A")
        snippet = result.get("snippet", "N/A")
        google_competitors += f"\n{idx}. **{title}**\n   URL: {link}\n   Snippet: {snippet}\n"

    # Build Bing competitor information
    bing_competitors = ""
    for idx, result in enumerate(bing_results[:5], start=1):
        title = result.get("title", "N/A")
        link = result.get("link", "N/A")
        snippet = result.get("snippet", "N/A")
        bing_competitors += f"\n{idx}. **{title}**\n   URL: {link}\n   Snippet: {snippet}\n"

    # Build ranking message for both engines
    google_rank_msg = f"Google: Ranked at position #{google_ranking}" if google_ranking else "Google: Not in top 10"
    bing_rank_msg = f"Bing: Ranked at position #{bing_ranking}" if bing_ranking else "Bing: Not in top 10"
    ranking_msg = f"{google_rank_msg}\n{bing_rank_msg}"

    # Construct the full prompt
    prompt = f"""You are an SEO expert analyzing a website's competitive position across multiple search engines.

**Website Being Analyzed:** {url}

**Website Analysis:**
- Type: {website_analysis.website_type}
- Primary Goal: {website_analysis.primary_goal}
- Description: {website_analysis.description}
- Key Features: {', '.join(website_analysis.key_features)}
- Target Keywords: {', '.join(website_analysis.keywords)}

**Current Search Rankings:**
{ranking_msg}

**Top Google Competitors (search for "{website_analysis.keywords[0]}"):**
{google_competitors}

**Top Bing Competitors (search for "{website_analysis.keywords[0]}"):**
{bing_competitors}

Please provide a comprehensive SEO analysis with:
1. **Findings**: Key observations about the website's current SEO position across Google and Bing, competitive landscape differences between engines, and opportunities
2. **Recommendations**: Specific, actionable steps to improve SEO performance on both search engines and overall competitiveness
3. **Require Attention**: High-priority items or quick wins that should be addressed immediately

IMPORTANT:
- Write everything in a positive, encouraging, and constructive tone
- Focus on opportunities and growth potential rather than shortcomings
- Highlight any interesting differences between Google and Bing results
- Use markdown formatting for better readability (bullet points, bold text, headings, etc.)
"""

    return prompt

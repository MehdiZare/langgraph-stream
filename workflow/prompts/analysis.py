"""
Analysis Prompts

Prompt templates for website analysis.
"""


def build_website_analysis_prompt(url: str) -> str:
    """
    Build prompt for structured website screenshot analysis.

    Args:
        url: URL of the website being analyzed

    Returns:
        Formatted prompt string
    """
    return (
        f"Analyze this website screenshot from {url}. "
        "Identify the website type, primary business goal, provide a description, "
        "list key features, and determine the top 5 SEO keywords that best represent this page."
    )


def build_streaming_description_prompt(url: str) -> str:
    """
    Build prompt for streaming description mode.

    Args:
        url: URL of the website being analyzed

    Returns:
        Formatted prompt string
    """
    return (
        f"Please describe this website screenshot from {url}. "
        "Provide details about the layout, design, key elements, "
        "and what the website appears to be about."
    )

"""
WebSocket Route

Handles WebSocket connections for real-time website analysis.
"""

import json
import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from utils import validate_url
from services.screenshot import capture_screenshot
from services.search import search_google, search_bing, find_url_ranking
from workflow import create_agent, analyze_website_node, analyze_seo_node
from workflow.prompts.analysis import build_streaming_description_prompt

router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for streaming website analysis.

    Handles two modes:
    1. Structured mode: Provides structured WebsiteAnalysis and SEO recommendations
    2. Streaming mode: Streams conversational description of the website

    Args:
        websocket: WebSocket connection
    """
    await websocket.accept()
    print("WebSocket connection established")

    try:
        # Create the agent for streaming mode
        agent = create_agent()

        while True:
            # Receive URL from client
            data = await websocket.receive_text()
            print(f"Received data: {data}")

            # Parse the incoming data
            try:
                message_data = json.loads(data)
                url = message_data.get("url", "")
                mode = message_data.get("mode", "structured")  # Default to structured
            except json.JSONDecodeError:
                # If it's not JSON, treat it as plain text URL
                url = data.strip()
                mode = "structured"

            if not url:
                await websocket.send_json({
                    "type": "error",
                    "content": "Empty URL received"
                })
                continue

            # Validate URL
            if not validate_url(url):
                await websocket.send_json({
                    "type": "error",
                    "content": "Invalid URL format. Please enter a valid URL starting with http:// or https://"
                })
                continue

            # Send status update: Capturing screenshot
            await websocket.send_json({
                "type": "status",
                "content": f"Capturing screenshot of {url}..."
            })

            # Capture screenshot
            try:
                screenshot_base64 = await capture_screenshot(url, websocket)
                print(f"Screenshot captured successfully for {url}")

                # Send screenshot to frontend
                await websocket.send_json({
                    "type": "screenshot",
                    "content": screenshot_base64
                })
            except Exception as e:
                print(f"Error capturing screenshot: {e}")
                await websocket.send_json({
                    "type": "error",
                    "content": str(e)
                })
                continue

            # Send status update: Analyzing
            await websocket.send_json({
                "type": "start",
                "content": "Analyzing website..."
            })

            # Choose analysis mode
            try:
                if mode == "structured":
                    # Use structured output (no streaming, no LangGraph wrapper)
                    analysis_result = await analyze_website_node(url, screenshot_base64)

                    # Send structured result
                    await websocket.send_json({
                        "type": "structured",
                        "analysis": {
                            "website_type": analysis_result.website_type,
                            "primary_goal": analysis_result.primary_goal,
                            "description": analysis_result.description,
                            "key_features": analysis_result.key_features,
                            "keywords": analysis_result.keywords
                        }
                    })

                    # Send status update: Searching competitors
                    await websocket.send_json({
                        "type": "status",
                        "content": "Searching Google and Bing for competitors..."
                    })

                    # Search both Google and Bing in parallel
                    google_results, bing_results = await asyncio.gather(
                        asyncio.to_thread(search_google, analysis_result.keywords),
                        asyncio.to_thread(search_bing, analysis_result.keywords)
                    )

                    # Find URL ranking in both engines
                    google_ranking = find_url_ranking(url, google_results)
                    bing_ranking = find_url_ranking(url, bing_results)

                    # Send status update: Analyzing SEO
                    await websocket.send_json({
                        "type": "status",
                        "content": "Analyzing SEO and generating recommendations..."
                    })

                    # Run SEO analysis with both engines' data
                    seo_result = await analyze_seo_node(
                        url=url,
                        website_analysis=analysis_result,
                        google_results=google_results,
                        bing_results=bing_results,
                        google_ranking=google_ranking,
                        bing_ranking=bing_ranking
                    )

                    # Send SEO recommendations
                    await websocket.send_json({
                        "type": "seo_recommendation",
                        "seo": {
                            "findings": seo_result.findings,
                            "recommendations": seo_result.recommendations,
                            "require_attention": seo_result.require_attention,
                            "google_ranking": google_ranking,
                            "bing_ranking": bing_ranking
                        }
                    })

                    # Send completion
                    await websocket.send_json({
                        "type": "end",
                        "content": "Analysis complete"
                    })

                else:
                    # Use original streaming mode
                    prompt_text = build_streaming_description_prompt(url)

                    input_data = {
                        "messages": [
                            {
                                "role": "user",
                                "content": [
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
                            }
                        ]
                    }

                    # Stream the response
                    full_response = ""
                    async for event in agent.astream_events(input_data, version="v2"):
                        kind = event["event"]

                        # Handle different event types
                        if kind == "on_chat_model_stream":
                            content = event["data"]["chunk"].content
                            if content:
                                full_response += content
                                # Send token to client
                                await websocket.send_json({
                                    "type": "token",
                                    "content": content
                                })

                    # Send completion signal
                    await websocket.send_json({
                        "type": "end",
                        "content": "Stream complete",
                        "full_response": full_response
                    })

            except Exception as e:
                print(f"Error during agent execution: {e}")
                await websocket.send_json({
                    "type": "error",
                    "content": f"Error analyzing screenshot: {str(e)}"
                })

    except WebSocketDisconnect:
        print("WebSocket connection closed")
    except Exception as e:
        print(f"Unexpected error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "content": f"Server error: {str(e)}"
            })
        except:
            pass

"""
WebSocket Route

Handles WebSocket connections for real-time website analysis.
"""

import json
import asyncio
import uuid
from typing import Optional
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from urllib.parse import urlparse

from utils import validate_url
from services.screenshot import capture_screenshot
from services.search import search_google, search_bing, find_url_ranking
from workflow import create_agent, analyze_website_node, analyze_seo_node
from workflow.prompts.analysis import build_streaming_description_prompt
from db import (
    verify_clerk_token,
    get_supabase_client,
    create_or_get_website,
    create_scan,
    update_scan_status,
    claim_user_scans,
    upload_to_s3,
    S3_BUCKET_NAME
)

router = APIRouter()


class WebSocketSession:
    """Manages WebSocket session state including authentication."""

    def __init__(self):
        self.authenticated: bool = False
        self.user_id: Optional[str] = None
        self.session_id: Optional[str] = None
        self.current_scan_id: Optional[str] = None

    def set_authenticated(self, user_id: str, session_id: str):
        """Set session as authenticated."""
        self.authenticated = True
        self.user_id = user_id
        self.session_id = session_id

    def set_anonymous(self, session_id: str):
        """Set session as anonymous."""
        self.authenticated = False
        self.user_id = None
        self.session_id = session_id


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for streaming website analysis.

    Two-phase flow:
    1. Authentication phase: First message must be auth message
    2. Analysis phase: Subsequent messages contain URL analysis requests

    Modes:
    - Structured mode: Provides structured WebsiteAnalysis and SEO recommendations
    - Streaming mode: Streams conversational description of the website

    Args:
        websocket: WebSocket connection
    """
    await websocket.accept()
    print("WebSocket connection established")

    # Initialize session state
    session = WebSocketSession()
    supabase = get_supabase_client(use_service_role=True)

    try:
        # Create the agent for streaming mode
        agent = create_agent()

        # PHASE 1: AUTHENTICATION
        # First message must be authentication
        auth_data = await websocket.receive_text()
        print(f"Received auth data: {auth_data}")

        try:
            auth_message = json.loads(auth_data)
            if auth_message.get("type") != "auth":
                await websocket.send_json({
                    "type": "error",
                    "content": "First message must be authentication message with type='auth'"
                })
                await websocket.close()
                return

            token = auth_message.get("token")
            provided_session_id = auth_message.get("session_id")
            claimed_scans = 0

            if token:
                # Verify Clerk token
                user_id = verify_clerk_token(token)
                if user_id:
                    # Generate or use provided session_id
                    session_id = provided_session_id or str(uuid.uuid4())
                    session.set_authenticated(user_id, session_id)

                    # If user was previously anonymous, claim their scans
                    if provided_session_id:
                        claimed_scans = await claim_user_scans(supabase, provided_session_id, user_id)
                        print(f"Claimed {claimed_scans} scans for user {user_id}")

                    await websocket.send_json({
                        "type": "auth_response",
                        "authenticated": True,
                        "user_id": user_id,
                        "session_id": session_id,
                        "claimed_scans": claimed_scans
                    })
                else:
                    # Invalid token
                    await websocket.send_json({
                        "type": "auth_response",
                        "authenticated": False,
                        "error": "Invalid authentication token"
                    })
                    await websocket.close()
                    return
            else:
                # Anonymous user
                session_id = provided_session_id or str(uuid.uuid4())
                session.set_anonymous(session_id)

                await websocket.send_json({
                    "type": "auth_response",
                    "authenticated": False,
                    "session_id": session_id
                })

        except json.JSONDecodeError:
            await websocket.send_json({
                "type": "error",
                "content": "Invalid JSON in authentication message"
            })
            await websocket.close()
            return

        print(f"Session authenticated: {session.authenticated}, user_id: {session.user_id}, session_id: {session.session_id}")

        # PHASE 2: ANALYSIS
        while True:
            # Receive analysis request from client
            data = await websocket.receive_text()
            print(f"Received data: {data}")

            # Parse the incoming data
            try:
                message_data = json.loads(data)

                # Expect analyze message type
                if message_data.get("type") != "analyze":
                    await websocket.send_json({
                        "type": "error",
                        "content": "Expected message type 'analyze'"
                    })
                    continue

                url = message_data.get("url", "")
                mode = message_data.get("mode", "structured")  # Default to structured
            except json.JSONDecodeError:
                await websocket.send_json({
                    "type": "error",
                    "content": "Invalid JSON format"
                })
                continue

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

            # DATABASE: Create website and scan records
            start_time = asyncio.get_event_loop().time()
            try:
                # Extract domain from URL
                parsed_url = urlparse(url)
                domain = parsed_url.netloc

                # Create or get website record
                website = await create_or_get_website(supabase, url, domain)
                print(f"Website record: {website['id']}")

                # Create scan record
                scan = await create_scan(
                    supabase,
                    website_id=website['id'],
                    user_id=session.user_id,
                    session_id=session.session_id
                )
                session.current_scan_id = scan['id']
                print(f"Created scan: {scan['id']}")

                # Update scan status to processing
                await update_scan_status(supabase, scan['id'], 'processing')

            except Exception as e:
                print(f"Error creating database records: {e}")
                await websocket.send_json({
                    "type": "error",
                    "content": f"Database error: {str(e)}"
                })
                continue

            # Send status update: Capturing screenshot
            await websocket.send_json({
                "type": "status",
                "content": f"Capturing screenshot of {url}..."
            })

            # Capture screenshot
            screenshot_base64 = None
            try:
                screenshot_base64 = await capture_screenshot(url, websocket)
                print(f"Screenshot captured successfully for {url}")

                # Send screenshot to frontend immediately
                await websocket.send_json({
                    "type": "screenshot",
                    "content": screenshot_base64
                })

                # Upload screenshot to S3 (async, don't block on failure)
                try:
                    import base64
                    import tempfile
                    import os

                    # Decode base64 to bytes
                    screenshot_bytes = base64.b64decode(screenshot_base64)

                    # Write to temporary file
                    with tempfile.NamedTemporaryFile(delete=False, suffix='.png') as tmp_file:
                        tmp_file.write(screenshot_bytes)
                        tmp_path = tmp_file.name

                    # Upload to S3
                    s3_uploaded = upload_to_s3(tmp_path, session.current_scan_id, 'screenshot.png')

                    # Clean up temp file
                    os.unlink(tmp_path)

                    if s3_uploaded:
                        print(f"Screenshot uploaded to S3 for scan {session.current_scan_id}")
                    else:
                        print(f"Failed to upload screenshot to S3 for scan {session.current_scan_id}")

                except Exception as s3_error:
                    # Don't fail the whole analysis if S3 upload fails
                    print(f"S3 upload error (non-fatal): {s3_error}")

            except Exception as e:
                print(f"Error capturing screenshot: {e}")

                # Update scan status to failed
                await update_scan_status(
                    supabase,
                    session.current_scan_id,
                    'failed',
                    error_message=f"Screenshot capture failed: {str(e)}"
                )

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

                    # DATABASE: Save scan results
                    end_time = asyncio.get_event_loop().time()
                    processing_time_ms = int((end_time - start_time) * 1000)

                    scan_data = {
                        "analysis": {
                            "website_type": analysis_result.website_type,
                            "primary_goal": analysis_result.primary_goal,
                            "description": analysis_result.description,
                            "key_features": analysis_result.key_features,
                            "keywords": analysis_result.keywords
                        },
                        "seo": {
                            "findings": seo_result.findings,
                            "recommendations": seo_result.recommendations,
                            "require_attention": seo_result.require_attention,
                            "google_ranking": google_ranking,
                            "bing_ranking": bing_ranking
                        },
                        "s3_files": {
                            "screenshot": f"scans/{session.current_scan_id}/screenshot.png"
                        } if S3_BUCKET_NAME else None
                    }

                    await update_scan_status(
                        supabase,
                        session.current_scan_id,
                        'completed',
                        scan_data=scan_data,
                        processing_time_ms=processing_time_ms
                    )

                    # Send completion
                    await websocket.send_json({
                        "type": "end",
                        "content": "Analysis complete",
                        "scan_id": session.current_scan_id
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

                    # DATABASE: Save streaming results
                    end_time = asyncio.get_event_loop().time()
                    processing_time_ms = int((end_time - start_time) * 1000)

                    scan_data = {
                        "mode": "streaming",
                        "description": full_response,
                        "s3_files": {
                            "screenshot": f"scans/{session.current_scan_id}/screenshot.png"
                        } if S3_BUCKET_NAME else None
                    }

                    await update_scan_status(
                        supabase,
                        session.current_scan_id,
                        'completed',
                        scan_data=scan_data,
                        processing_time_ms=processing_time_ms
                    )

                    # Send completion signal
                    await websocket.send_json({
                        "type": "end",
                        "content": "Stream complete",
                        "full_response": full_response,
                        "scan_id": session.current_scan_id
                    })

            except Exception as e:
                print(f"Error during agent execution: {e}")

                # DATABASE: Update scan status to failed
                if session.current_scan_id:
                    try:
                        await update_scan_status(
                            supabase,
                            session.current_scan_id,
                            'failed',
                            error_message=f"Analysis failed: {str(e)}"
                        )
                    except Exception as db_error:
                        print(f"Error updating scan status: {db_error}")

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

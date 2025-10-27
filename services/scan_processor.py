"""
Scan Processor Service

Background service for processing website scans with real-time progress updates.
Extracts screenshot, analyzes content, and performs SEO analysis.
"""

import asyncio
import base64
import io
import logging
import tempfile
import os
import uuid
from typing import Optional
from urllib.parse import urlparse
from PIL import Image

from utils import validate_url
from services.screenshot import capture_screenshot
from services.search import search_google, search_bing, find_url_ranking
from workflow import create_agent, analyze_website_node, analyze_seo_node
from workflow.prompts.analysis import build_streaming_description_prompt
from db import (
    get_supabase_client,
    create_or_get_website,
    create_scan,
    update_scan_status,
    upload_to_s3,
    S3_BUCKET_NAME
)

# Set up logger
logger = logging.getLogger(__name__)


class ScanProcessor:
    """
    Processes website scans with real-time updates via Socket.io.
    """

    def __init__(self, sio=None):
        """
        Initialize scan processor.

        Args:
            sio: Socket.io server instance for emitting events (optional)
        """
        self.sio = sio
        self.supabase = get_supabase_client(use_service_role=True)

    async def emit_progress(self, scan_id: str, percent: int, message: str):
        """
        Emit progress update to all clients in scan room.

        Args:
            scan_id: UUID of the scan
            percent: Progress percentage (0-100)
            message: Progress message
        """
        if self.sio:
            await self.sio.emit('scan:progress', {
                'scan_id': scan_id,
                'percent': percent,
                'message': message
            }, room=f'scan_{scan_id}')

    async def emit_completed(self, scan_id: str, results: dict):
        """
        Emit completion event to all clients in scan room.

        Args:
            scan_id: UUID of the scan
            results: Scan results data
        """
        if self.sio:
            await self.sio.emit('scan:completed', {
                'scan_id': scan_id,
                'results': results
            }, room=f'scan_{scan_id}')

    async def emit_failed(self, scan_id: str, error: str):
        """
        Emit failure event to all clients in scan room.

        Args:
            scan_id: UUID of the scan
            error: Error message
        """
        if self.sio:
            await self.sio.emit('scan:failed', {
                'scan_id': scan_id,
                'error': error
            }, room=f'scan_{scan_id}')

    async def emit_issue(self, scan_id: str, issue: dict):
        """
        Emit individual issue as it's discovered (optional).

        Args:
            scan_id: UUID of the scan
            issue: Issue data
        """
        if self.sio:
            await self.sio.emit('scan:issue', {
                'scan_id': scan_id,
                'issue': issue
            }, room=f'scan_{scan_id}')

    async def emit_screenshot_loading(self, scan_id: str):
        """
        Emit screenshot loading event to notify clients that screenshot capture has started.

        Args:
            scan_id: UUID of the scan
        """
        if self.sio:
            await self.sio.emit('scan:screenshot_loading', {
                'scan_id': scan_id
            }, room=f'scan_{scan_id}')

    async def emit_screenshot(self, scan_id: str, screenshot_base64: str):
        """
        Emit compressed screenshot to all clients in scan room for progressive loading.

        Args:
            scan_id: UUID of the scan
            screenshot_base64: Base64-encoded screenshot (will be compressed)
        """
        if self.sio:
            # Compress screenshot for WebSocket transmission
            try:
                # Decode base64 to bytes
                screenshot_bytes = base64.b64decode(screenshot_base64)

                # Open image with PIL
                img = Image.open(io.BytesIO(screenshot_bytes))

                # Resize to max 800px width while maintaining aspect ratio
                max_width = 800
                if img.width > max_width:
                    ratio = max_width / img.width
                    new_height = int(img.height * ratio)
                    img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)

                # Convert to JPEG with reduced quality for smaller size
                output = io.BytesIO()
                img.convert('RGB').save(output, format='JPEG', quality=65, optimize=True)
                compressed_bytes = output.getvalue()

                # Encode back to base64
                compressed_base64 = base64.b64encode(compressed_bytes).decode('utf-8')

                # Emit compressed screenshot
                await self.sio.emit('scan:screenshot', {
                    'scan_id': scan_id,
                    'screenshot': f'data:image/jpeg;base64,{compressed_base64}'
                }, room=f'scan_{scan_id}')

                logger.info(f"Emitted compressed screenshot for scan {scan_id} (original: {len(screenshot_bytes)} bytes, compressed: {len(compressed_bytes)} bytes)")

            except Exception as e:
                logger.warning(f"Error compressing screenshot for scan {scan_id}: {e}")
                # Fall back to sending original if compression fails
                # Note: fallback uses JPEG MIME since compression target was JPEG
                await self.sio.emit('scan:screenshot', {
                    'scan_id': scan_id,
                    'screenshot': f'data:image/jpeg;base64,{screenshot_base64}'
                }, room=f'scan_{scan_id}')

    async def _capture_and_emit_screenshot(
        self,
        scan_id: str,
        url: str
    ) -> Optional[str]:
        """
        Helper method to capture screenshot and emit events.

        Args:
            scan_id: UUID of the scan
            url: URL to capture

        Returns:
            Base64-encoded screenshot string, or None on failure
        """
        try:
            # Emit loading state
            await self.emit_screenshot_loading(scan_id)
            await self.emit_progress(scan_id, 15, f"Capturing screenshot of {url}...")

            # Capture screenshot
            screenshot_base64 = await capture_screenshot(url)

            if not screenshot_base64:
                raise Exception("Failed to capture screenshot")

            await self.emit_progress(scan_id, 30, "Screenshot captured successfully")

            # Small delay to ensure client has joined the scan room
            # (Prevents race condition when using REST API + Socket.io pattern)
            await asyncio.sleep(0.5)

            # Emit compressed screenshot for progressive display
            await self.emit_screenshot(scan_id, screenshot_base64)

            # Upload screenshot to S3 (non-blocking)
            # Normalize to PNG format before upload to ensure consistent format
            try:
                screenshot_bytes = base64.b64decode(screenshot_base64)

                # Open with Pillow and normalize to PNG
                img = Image.open(io.BytesIO(screenshot_bytes))

                # Convert to appropriate mode for PNG
                # Preserve alpha channel if present, otherwise convert to RGB
                if img.mode in ('LA', 'P', 'RGBA'):
                    img = img.convert('RGBA')
                else:
                    img = img.convert('RGB')

                # Save as PNG to temp file
                with tempfile.NamedTemporaryFile(delete=False, suffix='.png', mode='wb') as tmp_file:
                    img.save(tmp_file, format='PNG')
                    tmp_path = tmp_file.name

                s3_uploaded = upload_to_s3(tmp_path, scan_id, 'screenshot.png')
                os.unlink(tmp_path)

                if s3_uploaded:
                    logger.info(f"Screenshot uploaded to S3 for scan {scan_id}")
            except Exception as s3_error:
                logger.warning(f"S3 upload error (non-fatal) for scan {scan_id}: {s3_error}")

            return screenshot_base64

        except Exception as e:
            print(f"Error capturing screenshot: {e}")
            return None

    async def _run_structured_workflow(
        self,
        scan_id: str,
        url: str,
        screenshot_base64: str
    ) -> dict:
        """
        Helper method to run structured analysis workflow.

        Args:
            scan_id: UUID of the scan
            url: URL being analyzed
            screenshot_base64: Base64-encoded screenshot

        Returns:
            Dictionary containing analysis and SEO results
        """
        # Step 1: Analyze website (30% -> 60%)
        await self.emit_progress(scan_id, 35, "Analyzing website content...")

        analysis_result = await analyze_website_node(url, screenshot_base64)

        await self.emit_progress(scan_id, 60, "Website analysis complete")

        # Step 2: Search competitors (60% -> 75%)
        await self.emit_progress(scan_id, 65, "Searching Google and Bing for competitors...")

        google_results, bing_results = await asyncio.gather(
            asyncio.to_thread(search_google, analysis_result.keywords),
            asyncio.to_thread(search_bing, analysis_result.keywords)
        )

        google_ranking = find_url_ranking(url, google_results)
        bing_ranking = find_url_ranking(url, bing_results)

        await self.emit_progress(scan_id, 75, "Competitor search complete")

        # Step 3: SEO analysis (75% -> 95%)
        await self.emit_progress(scan_id, 80, "Analyzing SEO and generating recommendations...")

        seo_result = await analyze_seo_node(
            url=url,
            website_analysis=analysis_result,
            google_results=google_results,
            bing_results=bing_results,
            google_ranking=google_ranking,
            bing_ranking=bing_ranking
        )

        await self.emit_progress(scan_id, 95, "SEO analysis complete")

        return {
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
            }
        }

    async def process_scan(
        self,
        url: str,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        mode: str = "structured",
        scan_id: Optional[str] = None
    ) -> Optional[str]:
        """
        Main scan processing orchestrator.

        Args:
            url: URL to scan
            user_id: User ID (authenticated users)
            session_id: Session ID (anonymous users)
            mode: Analysis mode ('structured' or 'streaming')
            scan_id: Existing scan ID (if already created)

        Returns:
            Scan ID if successful, None otherwise
        """
        start_time = asyncio.get_event_loop().time()

        try:
            # Validate URL
            if not validate_url(url):
                raise ValueError("Invalid URL format")

            # Parse URL
            parsed_url = urlparse(url)
            domain = parsed_url.netloc

            # Create website and scan records if not provided
            if not scan_id:
                await self.emit_progress(None, 0, "Creating scan record...")

                website = await create_or_get_website(self.supabase, url, domain)
                scan = await create_scan(
                    self.supabase,
                    website_id=website['id'],
                    user_id=user_id,
                    session_id=session_id
                )
                scan_id = scan['id']

            # Update status to processing
            await update_scan_status(self.supabase, scan_id, 'processing')
            await self.emit_progress(scan_id, 10, f"Starting scan for {url}...")

            if mode == "structured":
                # Run screenshot capture and workflow analysis in parallel
                screenshot_task = self._capture_and_emit_screenshot(scan_id, url)

                # Wait for screenshot to complete first, then start workflow
                # This ensures the workflow has the screenshot available
                screenshot_base64 = await screenshot_task

                if not screenshot_base64:
                    raise Exception("Failed to capture screenshot")

                # Now run the structured workflow
                workflow_results = await self._run_structured_workflow(
                    scan_id, url, screenshot_base64
                )

                # Prepare scan data
                end_time = asyncio.get_event_loop().time()
                processing_time_ms = int((end_time - start_time) * 1000)

                scan_data = {
                    "mode": "structured",
                    "screenshot_url": f"scans/{scan_id}/screenshot.png" if S3_BUCKET_NAME else None,
                    "analysis": workflow_results["analysis"],
                    "seo": workflow_results["seo"],
                    "s3_files": {
                        "screenshot": f"scans/{scan_id}/screenshot.png"
                    } if S3_BUCKET_NAME else None
                }

                # Update database
                await update_scan_status(
                    self.supabase,
                    scan_id,
                    'completed',
                    scan_data=scan_data,
                    processing_time_ms=processing_time_ms
                )

                await self.emit_progress(scan_id, 100, "Scan complete!")
                await self.emit_completed(scan_id, scan_data)

            else:
                # Streaming mode - capture screenshot first, then stream
                screenshot_base64 = await self._capture_and_emit_screenshot(scan_id, url)

                if not screenshot_base64:
                    raise Exception("Failed to capture screenshot")

                # Stream the analysis
                agent = create_agent()
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

                    if kind == "on_chat_model_stream":
                        content = event["data"]["chunk"].content
                        if content:
                            full_response += content
                            # Could emit tokens here if needed

                # Prepare scan data
                end_time = asyncio.get_event_loop().time()
                processing_time_ms = int((end_time - start_time) * 1000)

                scan_data = {
                    "mode": "streaming",
                    "screenshot_url": f"scans/{scan_id}/screenshot.png" if S3_BUCKET_NAME else None,
                    "description": full_response,
                    "s3_files": {
                        "screenshot": f"scans/{scan_id}/screenshot.png"
                    } if S3_BUCKET_NAME else None
                }

                # Update database
                await update_scan_status(
                    self.supabase,
                    scan_id,
                    'completed',
                    scan_data=scan_data,
                    processing_time_ms=processing_time_ms
                )

                await self.emit_progress(scan_id, 100, "Scan complete!")
                await self.emit_completed(scan_id, scan_data)

            return scan_id

        except Exception as e:
            error_message = str(e)
            print(f"Error during scan processing: {error_message}")

            if scan_id:
                await update_scan_status(
                    self.supabase,
                    scan_id,
                    'failed',
                    error_message=error_message
                )
                await self.emit_failed(scan_id, error_message)

            return None


# Global processor instance (will be initialized with sio in socketio_handler.py)
_processor_instance = None


def get_scan_processor(sio=None) -> ScanProcessor:
    """
    Get or create the global scan processor instance.

    Args:
        sio: Socket.io server instance (optional, only needed on first call)

    Returns:
        ScanProcessor instance
    """
    global _processor_instance

    if _processor_instance is None:
        _processor_instance = ScanProcessor(sio)
    elif sio is not None and _processor_instance.sio is None:
        _processor_instance.sio = sio

    return _processor_instance

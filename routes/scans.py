"""
Scans REST API Routes

Provides HTTP endpoints for scan CRUD operations.
"""

import uuid
import asyncio
import logging
from typing import Optional
from urllib.parse import urlparse
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field

from utils import validate_url
from db import (
    get_supabase_client,
    get_user_id_from_auth_header,
    create_or_get_website,
    create_scan,
    get_scan_by_id,
    list_user_scans,
    claim_user_scans,
    get_s3_presigned_url,
    can_access_scan
)
from services.scan_processor import get_scan_processor


# Set up logger
logger = logging.getLogger(__name__)

router = APIRouter(tags=["scans"])


# Request/Response Models

class CreateScanRequest(BaseModel):
    """Request model for creating a scan."""
    url: str = Field(..., description="URL to scan")


class CreateScanResponse(BaseModel):
    """Response model for creating a scan."""
    scan_id: str
    website_id: str
    url: str
    domain: str
    status: str
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    created_at: str


class GetScanResponse(BaseModel):
    """Response model for getting scan details."""
    scan_id: str
    website_id: str
    url: str
    domain: str
    status: str
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    scan_data: Optional[dict] = None
    error_message: Optional[str] = None
    processing_time_ms: Optional[int] = None
    created_at: str
    completed_at: Optional[str] = None


class ListScansResponse(BaseModel):
    """Response model for listing scans."""
    scans: list[dict]
    total: int
    limit: int
    offset: int


class ClaimScansRequest(BaseModel):
    """Request model for claiming anonymous scans."""
    session_id: str = Field(..., description="Session ID to claim scans from")


class ClaimScansResponse(BaseModel):
    """Response model for claiming scans."""
    claimed_count: int
    message: str


class AssetInfo(BaseModel):
    """Asset information model."""
    url: str
    filename: str
    expires_at: str


class GetAssetsResponse(BaseModel):
    """Response model for getting scan assets."""
    scan_id: str
    assets: dict[str, AssetInfo]


# Helper Functions

def generate_session_id() -> str:
    """Generate a new session ID for anonymous users."""
    return str(uuid.uuid4())


def format_scan_response(scan: dict, website: Optional[dict] = None) -> dict:
    """
    Format scan data for API response.

    Args:
        scan: Scan record from database
        website: Website record from database (optional, may be nested in scan)

    Returns:
        Formatted scan dict
    """
    # Extract website data if nested
    if not website and 'websites' in scan:
        website = scan['websites']

    return {
        'scan_id': scan['id'],
        'website_id': scan['website_id'],
        'url': website['url'] if website else None,
        'domain': website['domain'] if website else None,
        'status': scan['status'],
        'user_id': scan.get('user_id'),
        'session_id': scan.get('session_id'),
        'scan_data': scan.get('scan_data'),
        'error_message': scan.get('error_message'),
        'processing_time_ms': scan.get('processing_time_ms'),
        'created_at': scan['created_at'],
        'completed_at': scan.get('completed_at')
    }


# API Endpoints

@router.post("/scans", response_model=CreateScanResponse)
async def create_scan_endpoint(
    request: CreateScanRequest,
    authorization: Optional[str] = Header(None),
    x_session_id: Optional[str] = Header(None, alias="X-Session-ID")
):
    """
    Create a new scan.

    - **Authenticated users**: Provide Authorization header with Clerk JWT token
    - **Anonymous users**: Provide X-Session-ID header with session_id from Socket.io auth

    After creation, scan processing starts in the background.
    Connect to WebSocket and join the scan room to receive real-time updates.
    """
    supabase = get_supabase_client(use_service_role=True)

    # Validate URL
    if not validate_url(request.url):
        raise HTTPException(
            status_code=400,
            detail="Invalid URL format. Please enter a valid URL starting with http:// or https://"
        )

    # Extract user_id from auth header
    user_id = get_user_id_from_auth_header(authorization)

    # Use client-provided session_id or generate new one for anonymous users
    session_id = None if user_id else (x_session_id or generate_session_id())

    try:
        # Parse URL
        parsed_url = urlparse(request.url)
        domain = parsed_url.netloc

        # Debug logging for scan creation
        logger.info(f"POST /scans - Creating scan for URL: {request.url}")
        logger.info(f"POST /scans - user_id: {user_id}, session_id: {session_id}")
        logger.info(f"POST /scans - x_session_id header: {x_session_id}")

        # Create website and scan records
        website = await create_or_get_website(supabase, request.url, domain)
        scan = await create_scan(
            supabase,
            website_id=website['id'],
            user_id=user_id,
            session_id=session_id
        )

        logger.info(f"POST /scans - Scan created successfully: {scan['id']}")
        logger.info(f"POST /scans - Scan record: user_id={scan.get('user_id')}, session_id={scan.get('session_id')}")

        # Start background processing
        processor = get_scan_processor()
        asyncio.create_task(
            processor.process_scan(
                url=request.url,
                user_id=user_id,
                session_id=session_id,
                mode="structured",
                scan_id=scan['id']
            )
        )

        # Return scan details
        return CreateScanResponse(
            scan_id=scan['id'],
            website_id=website['id'],
            url=website['url'],
            domain=website['domain'],
            status=scan['status'],
            user_id=user_id,
            session_id=session_id,
            created_at=scan['created_at']
        )

    except ValueError as e:
        # URL parsing or validation errors
        logger.exception("Invalid data when creating scan")
        raise HTTPException(
            status_code=400,
            detail="Invalid data provided for scan creation"
        ) from e
    except HTTPException:
        # Re-raise HTTP exceptions (like 400 from validation)
        raise
    except Exception as e:
        # Catch-all for unexpected errors (database, network, etc.)
        logger.exception("Unexpected error creating scan")
        raise HTTPException(
            status_code=500,
            detail="Error creating scan"
        ) from e


@router.get("/scans/{scan_id}", response_model=GetScanResponse)
async def get_scan_endpoint(
    scan_id: str,
    authorization: Optional[str] = Header(None),
    session_id: Optional[str] = Header(None, alias="X-Session-ID")
):
    """
    Get scan details by ID.

    Access is granted if:
    - User owns the scan (authenticated)
    - Session ID matches (anonymous)
    """
    supabase = get_supabase_client(use_service_role=True)

    # Extract user_id from auth header
    user_id = get_user_id_from_auth_header(authorization)

    # Debug logging
    logger.info(f"GET /scans/{scan_id} - user_id: {user_id}, session_id: {session_id}")
    logger.info(f"GET /scans/{scan_id} - auth header present: {authorization is not None}")

    # Check if scan exists first (without access control)
    check_response = supabase.table('scans').select('id, user_id, session_id').eq('id', scan_id).execute()
    scan_exists = check_response.data and len(check_response.data) > 0

    if not scan_exists:
        logger.warning(f"GET /scans/{scan_id} - Scan does not exist in database")
        raise HTTPException(
            status_code=404,
            detail="Scan not found"
        )

    # Get scan with access verification
    scan = await get_scan_by_id(supabase, scan_id, user_id, session_id)

    if not scan:
        # Scan exists but access is denied
        logger.warning(f"GET /scans/{scan_id} - Access denied for user_id: {user_id}, session_id: {session_id}")

        # Check if user needs to authenticate or provide session_id
        if not user_id and not session_id:
            raise HTTPException(
                status_code=401,
                detail="Authentication required. Please provide either Authorization header or X-Session-ID header."
            )
        else:
            raise HTTPException(
                status_code=403,
                detail="Access denied to this scan"
            )

    # Format response
    formatted = format_scan_response(scan)

    return GetScanResponse(**formatted)


@router.get("/scans", response_model=ListScansResponse)
async def list_scans_endpoint(
    limit: int = 20,
    offset: int = 0,
    status: Optional[str] = None,
    authorization: Optional[str] = Header(None)
):
    """
    List scans for authenticated user with pagination.

    **Requires authentication** - must provide Authorization header.

    Query parameters:
    - **limit**: Number of scans to return (default: 20, max: 100)
    - **offset**: Number of scans to skip (default: 0)
    - **status**: Filter by status (optional): pending, processing, completed, failed
    """
    supabase = get_supabase_client(use_service_role=True)

    # Extract user_id from auth header
    user_id = get_user_id_from_auth_header(authorization)

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="Authentication required. Please provide Authorization header."
        )

    # Validate limit
    if limit > 100:
        limit = 100

    # Get user scans
    scans, total = await list_user_scans(supabase, user_id, limit, offset, status)

    # Format scans
    formatted_scans = [format_scan_response(scan) for scan in scans]

    return ListScansResponse(
        scans=formatted_scans,
        total=total,
        limit=limit,
        offset=offset
    )


@router.post("/scans/claim", response_model=ClaimScansResponse)
async def claim_scans_endpoint(
    request: ClaimScansRequest,
    authorization: Optional[str] = Header(None)
):
    """
    Claim anonymous scans when user logs in.

    **Requires authentication** - must provide Authorization header.

    Transfers ownership of all scans associated with the provided session_id
    to the authenticated user.
    """
    supabase = get_supabase_client(use_service_role=True)

    # Extract user_id from auth header
    user_id = get_user_id_from_auth_header(authorization)

    if not user_id:
        raise HTTPException(
            status_code=401,
            detail="Authentication required. Please provide Authorization header."
        )

    try:
        # Claim scans
        claimed_count = await claim_user_scans(supabase, request.session_id, user_id)

        return ClaimScansResponse(
            claimed_count=claimed_count,
            message=f"Successfully claimed {claimed_count} scan(s)"
        )

    except ValueError as e:
        # Invalid session_id or user_id
        logger.exception("Invalid data when claiming scans")
        raise HTTPException(
            status_code=400,
            detail="Invalid session or user data"
        ) from e
    except Exception as e:
        # Database errors or other unexpected issues
        logger.exception("Unexpected error claiming scans")
        raise HTTPException(
            status_code=500,
            detail="Error claiming scans"
        ) from e


@router.get("/scans/{scan_id}/assets", response_model=GetAssetsResponse)
async def get_scan_assets_endpoint(
    scan_id: str,
    authorization: Optional[str] = Header(None),
    session_id: Optional[str] = Header(None, alias="X-Session-ID"),
    expiration: int = 3600
):
    """
    Get presigned URLs for scan assets (screenshot, html, raw_data).

    Access is granted if:
    - User owns the scan (authenticated)
    - Session ID matches (anonymous)

    Query parameters:
    - **expiration**: URL expiration time in seconds (default: 3600 = 1 hour)
    """
    supabase = get_supabase_client(use_service_role=True)

    # Extract user_id from auth header
    user_id = get_user_id_from_auth_header(authorization)

    # Verify access
    has_access = await can_access_scan(supabase, scan_id, user_id, session_id)

    if not has_access:
        raise HTTPException(
            status_code=404,
            detail="Scan not found or access denied"
        )

    # Generate presigned URLs for common assets
    assets = {}

    # Screenshot
    screenshot_url = get_s3_presigned_url(scan_id, 'screenshot.png', expiration)
    if screenshot_url:
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=expiration)
        assets['screenshot'] = AssetInfo(
            url=screenshot_url,
            filename='screenshot.png',
            expires_at=expires_at.isoformat() + 'Z'
        )

    # HTML (optional)
    html_url = get_s3_presigned_url(scan_id, 'page.html', expiration)
    if html_url:
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=expiration)
        assets['html'] = AssetInfo(
            url=html_url,
            filename='page.html',
            expires_at=expires_at.isoformat() + 'Z'
        )

    # Raw data (optional)
    raw_data_url = get_s3_presigned_url(scan_id, 'raw_data.json', expiration)
    if raw_data_url:
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=expiration)
        assets['raw_data'] = AssetInfo(
            url=raw_data_url,
            filename='raw_data.json',
            expires_at=expires_at.isoformat() + 'Z'
        )

    return GetAssetsResponse(
        scan_id=scan_id,
        assets=assets
    )

"""
Database and Storage Configuration

This module provides Supabase client and S3 client initialization
along with helper functions for database operations and S3 file management.
"""

import logging
from typing import Optional
from supabase import create_client, Client
import boto3
from botocore.exceptions import ClientError
from clerk_backend_api import Clerk

# Import configuration from centralized config module
from config import (
    CLERK_SECRET_KEY,
    CLERK_PUBLISHABLE_KEY,
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
    AWS_ACCESS_KEY_ID,
    AWS_SECRET_ACCESS_KEY,
    AWS_REGION,
    S3_BUCKET_NAME
)

# Set up logger
logger = logging.getLogger(__name__)


def get_supabase_client(use_service_role: bool = False) -> Client:
    """
    Get Supabase client instance.

    Args:
        use_service_role: If True, use service role key (bypasses RLS).
                         If False, use anon key (respects RLS).

    Returns:
        Supabase client instance
    """
    if not SUPABASE_URL:
        raise ValueError("SUPABASE_URL environment variable is not set")

    key = SUPABASE_SERVICE_ROLE_KEY if use_service_role else SUPABASE_ANON_KEY
    if not key:
        raise ValueError(
            f"{'SUPABASE_SERVICE_ROLE_KEY' if use_service_role else 'SUPABASE_ANON_KEY'} "
            "environment variable is not set"
        )

    return create_client(SUPABASE_URL, key)


def get_s3_client():
    """
    Get boto3 S3 client instance.

    In ECS/production, credentials are automatically provided via the task IAM role.
    For local development, credentials are resolved via boto3's default credential chain:
    - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    - AWS credentials file (~/.aws/credentials)
    - IAM instance profile (if running on EC2)

    Returns:
        boto3 S3 client
    """
    if not S3_BUCKET_NAME:
        raise ValueError(
            "S3_BUCKET_NAME environment variable must be set"
        )

    # Use boto3's default credential chain (includes ECS task role)
    return boto3.client('s3', region_name=AWS_REGION)


def get_scan_s3_path(scan_id: str, filename: str) -> str:
    """
    Construct S3 key path for a scan file.

    S3 folder structure: scans/{scan_id}/{filename}

    Args:
        scan_id: UUID of the scan
        filename: Name of the file (e.g., 'screenshot.png', 'page.html')

    Returns:
        S3 key path
    """
    return f"scans/{scan_id}/{filename}"


def upload_to_s3(local_file_path: str, scan_id: str, filename: str) -> bool:
    """
    Upload a file to S3 for a specific scan.

    Args:
        local_file_path: Path to the local file to upload
        scan_id: UUID of the scan
        filename: Name to give the file in S3

    Returns:
        True if upload successful, False otherwise
    """
    try:
        s3_client = get_s3_client()
        s3_key = get_scan_s3_path(scan_id, filename)

        s3_client.upload_file(
            local_file_path,
            S3_BUCKET_NAME,
            s3_key
        )
        return True
    except ClientError as e:
        logger.error(f"Error uploading to S3: {e}")
        return False


def download_from_s3(scan_id: str, filename: str, local_destination: str) -> bool:
    """
    Download a file from S3 for a specific scan.

    Args:
        scan_id: UUID of the scan
        filename: Name of the file in S3
        local_destination: Local path to save the file

    Returns:
        True if download successful, False otherwise
    """
    try:
        s3_client = get_s3_client()
        s3_key = get_scan_s3_path(scan_id, filename)

        s3_client.download_file(
            S3_BUCKET_NAME,
            s3_key,
            local_destination
        )
        return True
    except ClientError as e:
        logger.error(f"Error downloading from S3: {e}")
        return False


def get_s3_presigned_url(scan_id: str, filename: str, expiration: int = 3600) -> Optional[str]:
    """
    Generate a presigned URL for accessing a scan file in S3.

    Args:
        scan_id: UUID of the scan
        filename: Name of the file in S3
        expiration: URL expiration time in seconds (default: 1 hour)

    Returns:
        Presigned URL string or None if error
    """
    try:
        s3_client = get_s3_client()
        s3_key = get_scan_s3_path(scan_id, filename)

        url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': S3_BUCKET_NAME,
                'Key': s3_key
            },
            ExpiresIn=expiration
        )
        return url
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        return None


# Clerk Authentication Functions

def get_clerk_client() -> Clerk:
    """
    Get Clerk client instance.

    Returns:
        Clerk client instance
    """
    if not CLERK_SECRET_KEY:
        raise ValueError("CLERK_SECRET_KEY environment variable is not set")

    return Clerk(bearer_auth=CLERK_SECRET_KEY)


def verify_clerk_token(token: str) -> Optional[str]:
    """
    Verify Clerk JWT token and extract user_id.

    Args:
        token: Clerk JWT token from Authorization header

    Returns:
        User ID if token is valid, None otherwise
    """
    try:
        clerk = get_clerk_client()

        # Verify the session token
        session = clerk.sessions.verify_token(token)

        if session and hasattr(session, 'user_id'):
            return session.user_id

        return None
    except Exception as e:
        print(f"Error verifying Clerk token: {e}")
        return None


def get_user_id_from_auth_header(auth_header: Optional[str]) -> Optional[str]:
    """
    Extract and verify user_id from Authorization header.

    Args:
        auth_header: Authorization header value (e.g., "Bearer <token>")

    Returns:
        User ID if authenticated, None otherwise
    """
    if not auth_header:
        return None

    if not auth_header.startswith('Bearer '):
        return None

    token = auth_header.replace('Bearer ', '', 1)
    return verify_clerk_token(token)


# Example usage and database helper functions

async def create_or_get_website(supabase: Client, url: str, domain: str) -> dict:
    """
    Create a website record or get existing one.

    Args:
        supabase: Supabase client instance
        url: Full URL of the website
        domain: Domain extracted from URL

    Returns:
        Website record as dict
    """
    # Try to get existing website
    response = supabase.table('websites').select('*').eq('url', url).execute()

    if response.data and len(response.data) > 0:
        return response.data[0]

    # Create new website
    response = supabase.table('websites').insert({
        'url': url,
        'domain': domain
    }).execute()

    return response.data[0]


async def create_scan(
    supabase: Client,
    website_id: str,
    user_id: Optional[str] = None,
    session_id: Optional[str] = None
) -> dict:
    """
    Create a new scan record.

    Args:
        supabase: Supabase client instance
        website_id: UUID of the website being scanned
        user_id: UUID of the user (optional for anonymous scans)
        session_id: Session ID for anonymous scans

    Returns:
        Scan record as dict
    """
    scan_data = {
        'website_id': website_id,
        'status': 'pending'
    }

    if user_id:
        scan_data['user_id'] = user_id

    if session_id:
        scan_data['session_id'] = session_id

    response = supabase.table('scans').insert(scan_data).execute()
    return response.data[0]


async def update_scan_status(
    supabase: Client,
    scan_id: str,
    status: str,
    scan_data: Optional[dict] = None,
    error_message: Optional[str] = None,
    processing_time_ms: Optional[int] = None
) -> dict:
    """
    Update scan status and data.

    Args:
        supabase: Supabase client instance
        scan_id: UUID of the scan
        status: New status ('processing', 'completed', 'failed')
        scan_data: JSONB data to store with the scan
        error_message: Error message if scan failed
        processing_time_ms: Processing time in milliseconds

    Returns:
        Updated scan record as dict
    """
    update_data = {'status': status}

    if scan_data is not None:
        update_data['scan_data'] = scan_data

    if error_message is not None:
        update_data['error_message'] = error_message

    if processing_time_ms is not None:
        update_data['processing_time_ms'] = processing_time_ms

    if status == 'completed':
        from datetime import datetime
        update_data['completed_at'] = datetime.utcnow().isoformat()

    response = supabase.table('scans').update(update_data).eq('id', scan_id).execute()
    return response.data[0]


async def claim_user_scans(supabase: Client, session_id: str, user_id: str) -> int:
    """
    Claim anonymous scans when user logs in.

    Args:
        supabase: Supabase client instance
        session_id: Session ID used for anonymous scans
        user_id: UUID of the authenticated user

    Returns:
        Number of scans claimed
    """
    response = supabase.rpc('claim_anonymous_scans', {
        'p_session_id': session_id,
        'p_user_id': user_id
    }).execute()

    return response.data


async def can_access_scan(
    supabase: Client,
    scan_id: str,
    user_id: Optional[str] = None,
    session_id: Optional[str] = None
) -> bool:
    """
    Check if a user/session has access to a scan.

    A user has access if:
    - They own the scan (user_id matches)
    - The scan is anonymous and session_id matches

    Args:
        supabase: Supabase client instance
        scan_id: UUID of the scan
        user_id: UUID of the authenticated user (optional)
        session_id: Session ID for anonymous users (optional)

    Returns:
        True if user has access, False otherwise
    """
    try:
        response = supabase.table('scans').select('*').eq('id', scan_id).execute()

        if not response.data or len(response.data) == 0:
            logger.info(f"can_access_scan({scan_id}) - Scan not found in database")
            return False

        scan = response.data[0]

        # Debug logging with detailed comparison
        logger.info(f"can_access_scan({scan_id}) - Checking access:")
        logger.info(f"  - Scan user_id: {scan.get('user_id')} (type: {type(scan.get('user_id')).__name__})")
        logger.info(f"  - Scan session_id: {scan.get('session_id')} (type: {type(scan.get('session_id')).__name__})")
        logger.info(f"  - Request user_id: {user_id} (type: {type(user_id).__name__})")
        logger.info(f"  - Request session_id: {session_id} (type: {type(session_id).__name__})")

        # Check if user owns the scan
        if user_id and scan.get('user_id') == user_id:
            logger.info(f"can_access_scan({scan_id}) - Access granted: user_id match")
            return True

        # Check if session matches for anonymous scan
        scan_session_id = scan.get('session_id')
        if session_id and scan_session_id:
            # Log detailed comparison for debugging
            match = scan_session_id == session_id
            logger.info(f"can_access_scan({scan_id}) - Session ID comparison:")
            logger.info(f"  - Scan session_id:    '{scan_session_id}' (len: {len(scan_session_id) if scan_session_id else 0})")
            logger.info(f"  - Request session_id: '{session_id}' (len: {len(session_id) if session_id else 0})")
            logger.info(f"  - Match result: {match}")

            if match:
                logger.info(f"can_access_scan({scan_id}) - Access granted: session_id match")
                return True

        logger.warning(f"can_access_scan({scan_id}) - Access denied: no match")
        logger.warning(f"  - user_id check: provided={user_id}, scan_user_id={scan.get('user_id')}, match={user_id == scan.get('user_id') if user_id else 'N/A'}")
        logger.warning(f"  - session_id check: provided={session_id}, scan_session_id={scan.get('session_id')}, match={session_id == scan.get('session_id') if session_id else 'N/A'}")
        return False
    except Exception as e:
        logger.error(f"Error checking scan access: {e}")
        return False


async def get_scan_by_id(
    supabase: Client,
    scan_id: str,
    user_id: Optional[str] = None,
    session_id: Optional[str] = None
) -> Optional[dict]:
    """
    Get a scan by ID with access verification.

    Args:
        supabase: Supabase client instance
        scan_id: UUID of the scan
        user_id: UUID of the authenticated user (optional)
        session_id: Session ID for anonymous users (optional)

    Returns:
        Scan record as dict if user has access, None otherwise
    """
    # Check access first
    has_access = await can_access_scan(supabase, scan_id, user_id, session_id)
    if not has_access:
        logger.info(f"get_scan_by_id({scan_id}) - Access denied, returning None")
        return None

    try:
        # Get scan with website data
        response = supabase.table('scans').select(
            '*, websites(*)'
        ).eq('id', scan_id).execute()

        if response.data and len(response.data) > 0:
            logger.info(f"get_scan_by_id({scan_id}) - Scan found and returned")
            return response.data[0]

        logger.warning(f"get_scan_by_id({scan_id}) - Scan not found after access check passed")
        return None
    except Exception as e:
        logger.error(f"Error getting scan: {e}")
        return None


async def list_user_scans(
    supabase: Client,
    user_id: str,
    limit: int = 20,
    offset: int = 0,
    status: Optional[str] = None
) -> tuple[list[dict], int]:
    """
    List scans for a user with pagination.

    Args:
        supabase: Supabase client instance
        user_id: UUID of the authenticated user
        limit: Number of scans to return
        offset: Number of scans to skip
        status: Filter by status (optional)

    Returns:
        Tuple of (scans list, total count)
    """
    try:
        # Build query
        query = supabase.table('scans').select(
            '*, websites(*)',
            count='exact'
        ).eq('user_id', user_id)

        # Apply status filter if provided
        if status:
            query = query.eq('status', status)

        # Apply pagination and ordering
        query = query.order('created_at', desc=True).range(offset, offset + limit - 1)

        response = query.execute()

        scans = response.data if response.data else []
        total = response.count if hasattr(response, 'count') else len(scans)

        return scans, total
    except Exception as e:
        print(f"Error listing user scans: {e}")
        return [], 0
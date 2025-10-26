"""
Socket.io Handler

Handles real-time WebSocket connections for scan progress updates.
Provides room-based broadcasting for multiple clients to watch the same scan.
"""

import os
import uuid
import socketio
from typing import Optional
from urllib.parse import urlparse

from db import (
    get_supabase_client,
    verify_clerk_token,
    claim_user_scans,
    can_access_scan,
    create_or_get_website,
    create_scan
)
from utils import validate_url
from services.scan_processor import get_scan_processor


# Get Redis URL from environment (for Docker Compose)
REDIS_URL = os.getenv('REDIS_URL')

# Create Socket.io server with optional Redis support
if REDIS_URL:
    print(f"Initializing Socket.io with Redis: {REDIS_URL}")
    # Use Redis for multi-instance support (production/Docker)
    mgr = socketio.AsyncRedisManager(REDIS_URL)
    sio = socketio.AsyncServer(
        async_mode='asgi',
        client_manager=mgr,
        cors_allowed_origins=[],  # Let FastAPI's CORSMiddleware handle CORS
        logger=True,
        engineio_logger=True
    )
else:
    print("Initializing Socket.io with in-memory manager (single instance only)")
    # Use in-memory manager for development (single instance only)
    sio = socketio.AsyncServer(
        async_mode='asgi',
        cors_allowed_origins=[],  # Let FastAPI's CORSMiddleware handle CORS
        logger=True,
        engineio_logger=True
    )


# Helper Functions

def generate_session_id() -> str:
    """Generate a new session ID for anonymous users."""
    return str(uuid.uuid4())


# Event Handlers

@sio.event
async def connect(sid, environ):
    """
    Handle client connection.

    Clients must send 'auth' event as first message after connection.
    """
    print(f'Client connected: {sid}')


@sio.event
async def disconnect(sid):
    """Handle client disconnection."""
    print(f'Client disconnected: {sid}')


@sio.on('auth')
async def handle_auth(sid, data):
    """
    Handle authentication as first message after connection.

    This event MUST be the first message sent after connection.

    Args:
        sid: Socket.io session ID
        data: {
            'token': str | None,      # Clerk JWT token (null for anonymous)
            'session_id': str | None  # Session ID for anonymous users
        }

    Emits:
        auth_response: {
            'authenticated': bool,
            'user_id': str | None,
            'session_id': str | None,
            'claimed_scans': list[str]  # List of scan IDs claimed
        }
    """
    try:
        token = data.get('token')
        provided_session_id = data.get('session_id')
        supabase = get_supabase_client(use_service_role=True)

        if token:
            # Authenticated user flow
            try:
                # Verify Clerk JWT token
                user_id = verify_clerk_token(token)

                if user_id:
                    # Store user info in socket session
                    async with sio.session(sid) as session:
                        session['authenticated'] = True
                        session['user_id'] = user_id
                        session['session_id'] = provided_session_id

                    # Check for scans to claim (anonymous scans by this user)
                    claimed_scans = []
                    if provided_session_id:
                        claimed_count = await claim_user_scans(supabase, provided_session_id, user_id)
                        print(f"Claimed {claimed_count} scans for user {user_id}")
                        # Note: claimed_scans should be a list of scan IDs, but the DB function returns count
                        # For now, we'll return the count in the response

                    # Send auth response
                    await sio.emit('auth_response', {
                        'authenticated': True,
                        'user_id': user_id,
                        'claimed_scans': []  # TODO: Return actual scan IDs from claim function
                    }, room=sid)

                    print(f"User {user_id} authenticated via Socket.io")
                else:
                    # Invalid token - treat as anonymous
                    session_id = provided_session_id or generate_session_id()

                    async with sio.session(sid) as session:
                        session['authenticated'] = False
                        session['session_id'] = session_id

                    await sio.emit('auth_response', {
                        'authenticated': False,
                        'session_id': session_id
                    }, room=sid)

                    print(f"Invalid token, created anonymous session: {session_id}")

            except Exception as e:
                # Error verifying token - treat as anonymous
                print(f"Error verifying token: {e}")
                session_id = provided_session_id or generate_session_id()

                async with sio.session(sid) as session:
                    session['authenticated'] = False
                    session['session_id'] = session_id

                await sio.emit('auth_response', {
                    'authenticated': False,
                    'session_id': session_id
                }, room=sid)
        else:
            # Anonymous user flow
            session_id = provided_session_id or generate_session_id()

            async with sio.session(sid) as session:
                session['authenticated'] = False
                session['session_id'] = session_id

            await sio.emit('auth_response', {
                'authenticated': False,
                'session_id': session_id
            }, room=sid)

            print(f"Anonymous user connected with session: {session_id}")

    except Exception as e:
        print(f"Error in auth handler: {e}")
        await sio.emit('error', {
            'message': f"Authentication error: {str(e)}"
        }, room=sid)


@sio.on('join')
async def handle_join(sid, data):
    """
    Join a scan room to receive real-time updates.

    Args:
        sid: Socket.io session ID
        data: {'scan_id': str}

    The client will receive all events emitted to the scan room:
    - scan:progress
    - scan:completed
    - scan:failed
    - scan:issue (optional)
    """
    try:
        scan_id = data.get('scan_id')

        if not scan_id:
            await sio.emit('error', {
                'message': 'scan_id is required'
            }, room=sid)
            return

        # Get user/session info from socket session
        async with sio.session(sid) as session:
            user_id = session.get('user_id')
            session_id = session.get('session_id')

        # Verify user has access to this scan
        supabase = get_supabase_client(use_service_role=True)
        has_access = await can_access_scan(supabase, scan_id, user_id, session_id)

        if has_access:
            # Join the room
            await sio.enter_room(sid, f'scan_{scan_id}')
            print(f'Client {sid} joined scan room: scan_{scan_id}')

            # Optionally send confirmation
            await sio.emit('joined', {
                'scan_id': scan_id,
                'room': f'scan_{scan_id}'
            }, room=sid)
        else:
            await sio.emit('error', {
                'message': 'Access denied to this scan'
            }, room=sid)

    except Exception as e:
        print(f"Error in join handler: {e}")
        await sio.emit('error', {
            'message': f"Error joining room: {str(e)}"
        }, room=sid)


@sio.on('leave')
async def handle_leave(sid, data):
    """
    Leave a scan room.

    Args:
        sid: Socket.io session ID
        data: {'scan_id': str}
    """
    try:
        scan_id = data.get('scan_id')

        if not scan_id:
            await sio.emit('error', {
                'message': 'scan_id is required'
            }, room=sid)
            return

        # Leave the room
        await sio.leave_room(sid, f'scan_{scan_id}')
        print(f'Client {sid} left scan room: scan_{scan_id}')

        # Optionally send confirmation
        await sio.emit('left', {
            'scan_id': scan_id,
            'room': f'scan_{scan_id}'
        }, room=sid)

    except Exception as e:
        print(f"Error in leave handler: {e}")
        await sio.emit('error', {
            'message': f"Error leaving room: {str(e)}"
        }, room=sid)


@sio.on('analyze')
async def handle_analyze(sid, data):
    """
    Start analyzing a URL via WebSocket (OPTIONAL).

    Most clients should create scans via POST /api/scans instead.
    This event is provided for clients that want to create scans directly via WebSocket.

    Args:
        sid: Socket.io session ID
        data: {
            'url': str,
            'mode': 'structured' | 'streaming'  (default: 'structured')
        }

    Emits:
        analyze_response: {
            'scan_id': str,
            'url': str,
            'status': str,
            'user_id': str | None,
            'session_id': str | None,
            'created_at': str
        }

    After analyze_response, the client will receive progress updates in the scan room.
    """
    try:
        url = data.get('url')
        mode = data.get('mode', 'structured')

        if not url:
            await sio.emit('error', {
                'message': 'url is required'
            }, room=sid)
            return

        # Validate URL
        if not validate_url(url):
            await sio.emit('error', {
                'message': 'Invalid URL format. Please enter a valid URL starting with http:// or https://'
            }, room=sid)
            return

        # Get user/session info from socket session
        async with sio.session(sid) as session:
            user_id = session.get('user_id')
            session_id = session.get('session_id')

        # Parse URL
        parsed_url = urlparse(url)
        domain = parsed_url.netloc

        # Create website and scan records
        supabase = get_supabase_client(use_service_role=True)
        website = await create_or_get_website(supabase, url, domain)
        scan = await create_scan(
            supabase,
            website_id=website['id'],
            user_id=user_id,
            session_id=session_id
        )

        scan_id = scan['id']

        # Auto-join client to scan room for updates
        await sio.enter_room(sid, f'scan_{scan_id}')
        print(f'Client {sid} auto-joined scan room: scan_{scan_id}')

        # Return scan info to client
        await sio.emit('analyze_response', {
            'scan_id': scan_id,
            'url': url,
            'status': scan['status'],
            'user_id': user_id,
            'session_id': session_id,
            'created_at': scan['created_at']
        }, room=sid)

        # Start background task to process scan
        processor = get_scan_processor(sio)

        # Use sio.start_background_task for async tasks
        sio.start_background_task(
            processor.process_scan,
            url=url,
            user_id=user_id,
            session_id=session_id,
            mode=mode,
            scan_id=scan_id
        )

        print(f"Started scan processing for {url} (scan_id: {scan_id})")

    except Exception as e:
        print(f"Error in analyze handler: {e}")
        await sio.emit('error', {
            'message': f"Error starting analysis: {str(e)}"
        }, room=sid)


# Initialize scan processor with sio
# This must be done after sio is created
def initialize_processor():
    """Initialize the scan processor with Socket.io server."""
    processor = get_scan_processor(sio)
    print("Scan processor initialized with Socket.io server")


# Call initialization
initialize_processor()

"""
FastAPI Application

Main application initialization and route registration.
Integrates Socket.io for real-time WebSocket communication.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import socketio

from routes.health import router as health_router
from routes.static import router as static_router
from routes.websocket import router as websocket_router
from routes.scans import router as scans_router
from routes.socketio_handler import sio
from services.cache import cleanup_expired_cache

# Initialize FastAPI app
app = FastAPI(
    title="Website Scanner API",
    description="AI-powered website screenshot analyzer with real-time scan updates",
    version="0.2.0"
)

# Configure CORS to allow frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",          # Local development
        "https://*.vercel.app",           # All Vercel preview deployments
        "https://roboad.ai",              # Production domain
        "https://*.roboad.ai",            # Any roboad.ai subdomains
    ],
    allow_credentials=True,
    allow_methods=["*"],  # Allow all HTTP methods (GET, POST, OPTIONS, etc.)
    allow_headers=["*"],  # Allow all headers
)

# Register REST API routers
app.include_router(health_router)
app.include_router(static_router)
app.include_router(websocket_router)  # Legacy WebSocket (can be removed later)
app.include_router(scans_router, prefix="/api")  # New REST API endpoints


@app.on_event("startup")
async def startup_event():
    """
    Application startup event handler.
    Cleans up expired cache files on startup.
    """
    cleanup_expired_cache()
    print("Application started successfully")
    print("Socket.io server initialized")
    print("REST API available at /api/scans")
    print("Socket.io available at /socket.io/")


# Wrap FastAPI app with Socket.io ASGI
socket_app = socketio.ASGIApp(
    socketio_server=sio,
    other_asgi_app=app,
    socketio_path='socket.io'
)

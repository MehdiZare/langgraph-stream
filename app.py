"""
FastAPI Application

Main application initialization and route registration.
"""

from fastapi import FastAPI

from routes.health import router as health_router
from routes.static import router as static_router
from routes.websocket import router as websocket_router
from services.cache import cleanup_expired_cache

# Initialize FastAPI app
app = FastAPI()

# Register routers
app.include_router(health_router)
app.include_router(static_router)
app.include_router(websocket_router)


@app.on_event("startup")
async def startup_event():
    """
    Application startup event handler.
    Cleans up expired cache files on startup.
    """
    cleanup_expired_cache()
    print("Application started successfully")

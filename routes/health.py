"""
Health Check Route

Provides health check endpoint for load balancers and monitoring.
"""

from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health_check():
    """
    Health check endpoint for AWS ALB/ECS and other load balancers.

    Returns:
        Dict with status and service name
    """
    return {"status": "healthy", "service": "langgraph-websocket"}

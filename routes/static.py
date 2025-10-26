"""
Static File Route

Serves the HTML client for the application.
"""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter()


@router.get("/")
async def get_client():
    """
    Serve the HTML client interface.

    Returns:
        HTMLResponse with client.html content
    """
    with open("client.html", "r") as f:
        return HTMLResponse(content=f.read())

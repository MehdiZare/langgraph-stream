"""
Server Entry Point

Minimal entry point that imports the FastAPI app and runs uvicorn.

Note: This file has been refactored. The original code has been split into:
- config.py: Configuration constants
- models.py: Pydantic models
- utils.py: Utility functions
- services/: Service layer (cache, screenshot, search, llm)
- workflow/: LangGraph workflow (prompts, nodes, graph)
- routes/: API routes (health, static, websocket)
- app.py: FastAPI application initialization
"""

import os
from app import app

if __name__ == "__main__":
    import uvicorn
    from config import DEFAULT_PORT

    # Get port from environment variable or default to 8010
    port = int(os.environ.get("PORT", DEFAULT_PORT))
    uvicorn.run(app, host="0.0.0.0", port=port)

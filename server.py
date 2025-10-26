"""
Server Entry Point

Minimal entry point that imports the Socket.io wrapped FastAPI app and runs uvicorn.

Note: This file has been refactored. The original code has been split into:
- config.py: Configuration constants
- models.py: Pydantic models
- utils.py: Utility functions
- services/: Service layer (cache, screenshot, search, llm, scan_processor)
- workflow/: LangGraph workflow (prompts, nodes, graph)
- routes/: API routes (health, static, websocket, scans, socketio_handler)
- app.py: FastAPI application initialization with Socket.io integration
"""

import os
from app import socket_app

if __name__ == "__main__":
    import uvicorn
    from config import DEFAULT_PORT

    # Get port from environment variable or default to 8010
    port = int(os.environ.get("PORT", DEFAULT_PORT))

    print(f"Starting server on port {port}")
    print("REST API endpoints:")
    print(f"  - POST   http://localhost:{port}/api/scans")
    print(f"  - GET    http://localhost:{port}/api/scans/{{scan_id}}")
    print(f"  - GET    http://localhost:{port}/api/scans")
    print(f"  - POST   http://localhost:{port}/api/scans/claim")
    print(f"  - GET    http://localhost:{port}/api/scans/{{scan_id}}/assets")
    print(f"Socket.io endpoint:")
    print(f"  - WS     http://localhost:{port}/socket.io/")
    print()

    uvicorn.run(socket_app, host="0.0.0.0", port=port)

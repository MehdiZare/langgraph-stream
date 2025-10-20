# LangGraph WebSocket Streaming Test

A simple project to test real-time streaming between a frontend and a LangGraph agent using WebSockets, powered by Meta Llama.

## Features

- Real-time WebSocket communication
- LangGraph agent with Meta Llama (Llama-3.3-8B-Instruct)
- Streaming AI responses token-by-token
- Simple, clean HTML/CSS/JS frontend
- Python backend with FastAPI
- Dependency management with `uv`

## Project Structure

```
.
├── server.py          # FastAPI server with WebSocket and LangGraph agent
├── client.html        # HTML test client
├── pyproject.toml     # Project dependencies (managed by uv)
├── .env.example       # Environment variable template
└── README.md          # This file
```

## Prerequisites

- Python 3.10 or higher
- [uv](https://github.com/astral-sh/uv) - Fast Python package installer
- Meta Llama API key (from [llama.com](https://www.llama.com/))

## Setup

### 1. Install `uv` (if not already installed)

```bash
# On macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# On Windows
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

### 2. Clone and navigate to the project

```bash
cd langgraph-stream
```

### 3. Install dependencies with uv

```bash
uv sync
```

This will create a virtual environment and install all dependencies from `pyproject.toml`.

### 4. Set up environment variables

Create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` and add your Meta Llama API key:

```
LLAMA_API_KEY=your_actual_api_key_here
```

You can get your API key from [llama.com](https://www.llama.com/).

## Running the Application

### Start the server

```bash
# Using uv to run with the virtual environment
uv run python server.py
```

Or activate the virtual environment first:

```bash
# Activate the virtual environment
source .venv/bin/activate  # On macOS/Linux
# or
.venv\Scripts\activate     # On Windows

# Then run the server
python server.py
```

The server will start on `http://localhost:8000`

### Access the test client

Open your browser and navigate to:

```
http://localhost:8000
```

You should see the LangGraph WebSocket Test interface.

## Usage

1. The client automatically connects to the WebSocket server
2. Type a message in the input field or use the quick action buttons
3. Click "Send" or press Enter
4. Watch the AI response stream in real-time!

### Quick Test Messages

- "Hello!" - Simple greeting
- "Tell me a short joke" - Get a joke from the AI
- "What is the capital of France?" - Trivia question

## How It Works

### Backend (server.py)

1. **FastAPI Server**: Handles HTTP and WebSocket connections
2. **LangGraph Agent**: Creates a simple conversational agent using:
   - `ChatOpenAI` with custom base URL for Meta Llama API
   - `StateGraph` for managing conversation state
   - Streaming enabled for real-time responses
3. **WebSocket Handler**:
   - Receives messages from the frontend
   - Triggers the LangGraph agent
   - Streams responses back token-by-token

### Frontend (client.html)

1. **WebSocket Client**: Connects to the server
2. **Message Display**: Shows user and AI messages
3. **Streaming UI**: Displays tokens as they arrive
4. **Auto-reconnect**: Automatically reconnects if connection drops

## API Details

### WebSocket Endpoint

**URL**: `ws://localhost:8000/ws`

**Message Format (Client → Server)**:
```json
{
  "message": "Your message here"
}
```

**Message Format (Server → Client)**:

Start of stream:
```json
{
  "type": "start",
  "content": "Processing your message..."
}
```

Token stream:
```json
{
  "type": "token",
  "content": "single token or word"
}
```

End of stream:
```json
{
  "type": "end",
  "content": "Stream complete",
  "full_response": "The complete response"
}
```

Error:
```json
{
  "type": "error",
  "content": "Error message"
}
```

## Customization

### Change the AI Model

Edit `server.py` and modify the model name in `get_llama_model()`:

```python
return ChatOpenAI(
    model="Llama-3.3-8B-Instruct",  # Change this
    api_key=api_key,
    base_url="https://api.llama.com/compat/v1/",
    streaming=True,
)
```

### Modify the Agent Behavior

Edit the `create_agent()` function in `server.py` to add system prompts, tools, or more complex graph structures.

### Customize the Frontend

Edit `client.html` to change styling, add features, or modify the UI.

## Troubleshooting

### "LLAMA_API_KEY environment variable is not set"

Make sure you have:
1. Created a `.env` file
2. Added your API key to it
3. The `.env` file is in the same directory as `server.py`

### WebSocket connection fails

- Ensure the server is running on port 8000
- Check if another application is using port 8000
- Try accessing `http://localhost:8000` directly to verify the server is running

### Dependencies installation issues

Try:
```bash
uv sync --reinstall
```

## Dependencies

- **langgraph**: Graph-based agent framework
- **langchain**: LLM framework
- **langchain-openai**: OpenAI integration for LangChain
- **fastapi**: Modern web framework
- **uvicorn**: ASGI server
- **python-dotenv**: Environment variable management
- **openai**: OpenAI Python client

## License

MIT

# Website Screenshot Analyzer

An AI-powered website screenshot analyzer using LangGraph, Meta Llama Vision, and Steel.dev browser automation. Enter a URL, get an AI-generated description of the website with real-time streaming.

## 🚀 Quick Deploy to AWS

**Want to deploy this to production?** We've got you covered with complete CI/CD infrastructure!

**Start here**: **[GETTING_STARTED.md](GETTING_STARTED.md)** - Choose your deployment path

### Deployment Options:
- **[QUICKSTART.md](QUICKSTART.md)** - Deploy in 30 minutes ⚡
- **[SETUP.md](SETUP.md)** - Detailed setup guide 📚
- **[MIGRATION.md](MIGRATION.md)** - Migrate existing infrastructure 🔄

### What You Get:
- ✅ Production AWS ECS Fargate deployment
- ✅ Auto-deploy on merge to main
- ✅ Ephemeral PR environments (auto-created/destroyed)
- ✅ Complete CI/CD with GitHub Actions
- ✅ Infrastructure as Code with Terraform
- ✅ ~$80/month base cost

---

## Features

- Real-time WebSocket communication
- Automated screenshot capture with Steel.dev browser API
- Vision-enabled AI analysis with Meta Llama (Llama-4-Maverick-17B-128E-Instruct-FP8)
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
- Steel.dev API key (from [steel.dev](https://steel.dev/))

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

Edit `.env` and add your API keys:

```
LLAMA_API_KEY=your_actual_llama_api_key_here
STEEL_API_KEY=your_actual_steel_api_key_here
```

Get your API keys:
- Meta Llama API key from [llama.com](https://www.llama.com/)
- Steel.dev API key from [steel.dev](https://steel.dev/)

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

### Access the analyzer

Open your browser and navigate to:

```
http://localhost:8000
```

You should see the Website Screenshot Analyzer interface.

## Usage

1. The client automatically connects to the WebSocket server
2. Enter a website URL in the input field or use the quick action buttons
3. Click "Analyze" or press Enter
4. Watch as the system:
   - Captures a screenshot of the website
   - Analyzes it with AI vision
   - Streams the description in real-time!

### Quick Test URLs

- `https://github.com` - GitHub homepage
- `https://news.ycombinator.com` - Hacker News
- `https://www.anthropic.com` - Anthropic's website

## How It Works

### Backend (server.py)

1. **FastAPI Server**: Handles HTTP and WebSocket connections
2. **Steel.dev Integration**: Browser automation for screenshot capture
   - Creates browser sessions
   - Captures high-quality screenshots of websites
   - Returns base64-encoded images
3. **LangGraph Agent**: Vision-enabled AI agent using:
   - `ChatOpenAI` with Meta Llama Vision model
   - `StateGraph` for managing analysis workflow
   - Streaming enabled for real-time responses
4. **WebSocket Handler**:
   - Receives URL from the frontend
   - Validates URL format
   - Captures screenshot via Steel.dev
   - Sends screenshot + prompt to Llama Vision
   - Streams AI analysis back token-by-token

### Frontend (client.html)

1. **WebSocket Client**: Connects to the server
2. **URL Input**: Accepts website URLs
3. **Status Display**: Shows progress (capturing, analyzing)
4. **Streaming UI**: Displays AI description as it's generated
5. **Auto-reconnect**: Automatically reconnects if connection drops

## API Details

### WebSocket Endpoint

**URL**: `ws://localhost:8000/ws`

**Message Format (Client → Server)**:
```json
{
  "url": "https://example.com"
}
```

**Message Format (Server → Client)**:

Status update (capturing screenshot):
```json
{
  "type": "status",
  "content": "Capturing screenshot of https://example.com..."
}
```

Start of analysis:
```json
{
  "type": "start",
  "content": "Analyzing website..."
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
  "content": "Analysis complete",
  "full_response": "The complete description"
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
    model="Llama-4-Maverick-17B-128E-Instruct-FP8",  # Change to another vision model
    api_key=api_key,
    base_url="https://api.llama.com/compat/v1/",
    streaming=True,
)
```

### Customize the Analysis Prompt

Edit the prompt in the WebSocket handler (server.py, line ~182):

```python
"text": f"Please describe this website screenshot from {url}. Provide details about the layout, design, key elements, and what the website appears to be about."
```

Change this to customize what the AI looks for in screenshots.

### Modify Screenshot Settings

Edit the `capture_screenshot()` function to customize Steel.dev screenshot options (full page, viewport size, etc.).

### Customize the Frontend

Edit `client.html` to change styling, add features, or display the screenshot image alongside the analysis.

## Troubleshooting

### "LLAMA_API_KEY environment variable is not set" or "STEEL_API_KEY environment variable is not set"

Make sure you have:
1. Created a `.env` file
2. Added both API keys to it
3. The `.env` file is in the same directory as `server.py`

### "Failed to capture screenshot"

- Verify your Steel.dev API key is correct
- Check if you have credits/quota remaining in your Steel.dev account
- Ensure the URL is accessible and properly formatted (must start with `http://` or `https://`)

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
- **langchain-openai**: OpenAI integration for LangChain (supports vision models)
- **steel-sdk**: Steel.dev browser automation SDK
- **fastapi**: Modern web framework
- **uvicorn**: ASGI server
- **python-dotenv**: Environment variable management
- **openai**: OpenAI Python client

## License

MIT

import os
import json
import base64
import hashlib
import time
import asyncio
from typing import Annotated, List, Literal
from pathlib import Path
from urllib.parse import urlparse
from pydantic import BaseModel, Field
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from dotenv import load_dotenv
from steel import Steel
import httpx

# Load environment variables
load_dotenv()

# Pydantic model for structured output
class WebsiteAnalysis(BaseModel):
    """Structured analysis of a website screenshot"""

    website_type: Literal[
        "E-commerce",
        "SaaS/Software",
        "Blog/Content",
        "Portfolio",
        "Corporate/Business",
        "Landing Page",
        "News/Media",
        "Social Platform",
        "Educational",
        "Government",
        "Other"
    ] = Field(description="Primary category/type of the website")

    primary_goal: Literal[
        "Product Sales",
        "Lead Generation",
        "Information/Education",
        "Brand Awareness",
        "User Engagement",
        "Content Distribution",
        "Service Delivery",
        "Community Building",
        "Other"
    ] = Field(description="Main business objective of the website")

    description: str = Field(
        description="Brief 2-3 sentence description of the website, its purpose, and visual design"
    )

    key_features: List[str] = Field(
        description="List of 3-5 notable features, UI elements, or characteristics observed",
        min_length=3,
        max_length=5
    )

# Cache configuration
CACHE_DIR = Path(".cache/screenshots")
CACHE_TTL_SECONDS = 3600  # 1 hour

# Steel.dev retry configuration
STEEL_MAX_RETRIES = 3
STEEL_RETRY_DELAYS = [1, 2, 4]  # seconds (exponential backoff)

# Initialize FastAPI app
app = FastAPI()

# Initialize Steel client
def get_steel_client():
    """Initialize Steel client with API key"""
    api_key = os.environ.get("STEEL_API_KEY")
    if not api_key:
        raise ValueError("STEEL_API_KEY environment variable is not set")
    return Steel(steel_api_key=api_key)

# Cache helper functions
def get_cache_path(url: str) -> Path:
    """Generate cache file path from URL"""
    url_hash = hashlib.sha256(url.encode()).hexdigest()
    return CACHE_DIR / f"{url_hash}.json"

def get_cached_screenshot(url: str) -> str | None:
    """Retrieve screenshot from cache if valid"""
    cache_file = get_cache_path(url)

    if not cache_file.exists():
        return None

    try:
        with open(cache_file, 'r') as f:
            cache_data = json.load(f)

        # Check if cache is expired
        age = time.time() - cache_data['timestamp']
        if age > CACHE_TTL_SECONDS:
            # Cache expired, delete file
            cache_file.unlink()
            return None

        return cache_data['base64']
    except Exception as e:
        print(f"Cache read error: {e}")
        return None

def save_screenshot_to_cache(url: str, base64_data: str):
    """Save screenshot to cache"""
    try:
        # Ensure cache directory exists
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

        cache_data = {
            "url": url,
            "timestamp": time.time(),
            "base64": base64_data
        }

        cache_file = get_cache_path(url)
        with open(cache_file, 'w') as f:
            json.dump(cache_data, f)
    except Exception as e:
        print(f"Cache write error: {e}")

def cleanup_expired_cache():
    """Remove expired cache files"""
    if not CACHE_DIR.exists():
        return

    cleaned_count = 0
    for cache_file in CACHE_DIR.glob("*.json"):
        try:
            with open(cache_file, 'r') as f:
                cache_data = json.load(f)

            age = time.time() - cache_data['timestamp']
            if age > CACHE_TTL_SECONDS:
                cache_file.unlink()
                cleaned_count += 1
        except Exception:
            pass

    if cleaned_count > 0:
        print(f"Cleaned up {cleaned_count} expired cache file(s)")

# Capture screenshot from URL
def normalize_url(url: str) -> str:
    """Normalize URL to lowercase for consistent caching"""
    return url.lower().strip()

def validate_url(url: str) -> bool:
    """Validate if the given string is a valid URL"""
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc]) and result.scheme in ['http', 'https']
    except Exception:
        return False

async def fetch_screenshot_with_retry(steel_client, url: str, websocket: WebSocket = None) -> tuple[str | None, bytes | None]:
    """
    Fetch screenshot with retry logic and progress updates
    Returns: (screenshot_url, screenshot_bytes) - one will be None
    """
    last_error = None

    for attempt in range(STEEL_MAX_RETRIES):
        try:
            if attempt > 0:
                # Send retry update to user
                if websocket:
                    await websocket.send_json({
                        "type": "status",
                        "content": f"Retrying screenshot capture (attempt {attempt + 1}/{STEEL_MAX_RETRIES})..."
                    })
                # Wait with exponential backoff
                await asyncio.sleep(STEEL_RETRY_DELAYS[attempt - 1])

            # Send progress update
            if websocket:
                await websocket.send_json({
                    "type": "status",
                    "content": "Contacting Steel.dev browser..."
                })

            response = steel_client.screenshot(url=url)

            # Extract URL or bytes from response
            if hasattr(response, 'url'):
                return (response.url, None)
            elif isinstance(response, dict) and 'url' in response:
                return (response['url'], None)
            elif isinstance(response, str) and response.startswith('http'):
                return (response, None)
            elif isinstance(response, bytes):
                return (None, response)
            else:
                raise Exception("Unknown response format from Steel.dev")

        except Exception as e:
            last_error = e
            error_msg = str(e)

            # Check if it's a retryable error (5xx server errors)
            is_retryable = '500' in error_msg or '502' in error_msg or '503' in error_msg or '504' in error_msg

            if not is_retryable or attempt == STEEL_MAX_RETRIES - 1:
                # Don't retry for non-5xx errors or on last attempt
                break

    # All retries failed
    raise Exception(f"Failed to capture screenshot after {STEEL_MAX_RETRIES} attempts: {str(last_error)}")

async def capture_screenshot(url: str, websocket: WebSocket = None) -> str:
    """
    Capture a screenshot of the given URL using Steel.dev
    Uses 1-hour file-based cache to reduce API calls
    Returns base64 encoded screenshot
    """
    # Normalize URL for consistent caching
    normalized_url = normalize_url(url)

    # Check cache first
    cached_screenshot = get_cached_screenshot(normalized_url)
    if cached_screenshot:
        print(f"Cache hit for {normalized_url}")
        if websocket:
            await websocket.send_json({
                "type": "status",
                "content": "Using cached screenshot..."
            })
        return cached_screenshot

    print(f"Cache miss for {normalized_url}, fetching from Steel.dev")

    try:
        steel_client = get_steel_client()

        # Fetch screenshot with retry logic
        screenshot_url, screenshot_bytes = await fetch_screenshot_with_retry(
            steel_client,
            normalized_url,
            websocket
        )

        if screenshot_url:
            # Send progress update
            if websocket:
                await websocket.send_json({
                    "type": "status",
                    "content": "Downloading screenshot image..."
                })

            # Fetch the screenshot from the URL
            async with httpx.AsyncClient() as client:
                img_response = await client.get(screenshot_url)
                img_response.raise_for_status()
                screenshot_bytes = img_response.content

        # Encode to base64
        screenshot_base64 = base64.b64encode(screenshot_bytes).decode('utf-8')

        # Save to cache before returning
        save_screenshot_to_cache(normalized_url, screenshot_base64)

        return screenshot_base64

    except Exception as e:
        # Provide helpful error message
        error_detail = str(e)
        if '500' in error_detail or 'Internal Server Error' in error_detail:
            raise Exception("Steel.dev service is temporarily unavailable. Please try again in a moment.")
        elif '401' in error_detail or '403' in error_detail:
            raise Exception("Steel.dev API authentication failed. Please check your API key.")
        elif '429' in error_detail:
            raise Exception("Steel.dev rate limit exceeded. Please wait a moment before trying again.")
        else:
            raise Exception(f"Failed to capture screenshot: {error_detail}")

# Serve static files (for the HTML client)
@app.get("/")
async def get_client():
    with open("client.html", "r") as f:
        return HTMLResponse(content=f.read())

# Initialize Meta Llama via OpenAI-compatible API
def get_llama_model():
    api_key = os.environ.get("LLAMA_API_KEY")
    if not api_key:
        raise ValueError("LLAMA_API_KEY environment variable is not set")

    return ChatOpenAI(
        model="Llama-4-Maverick-17B-128E-Instruct-FP8",
        api_key=api_key,
        base_url="https://api.llama.com/compat/v1/",
        streaming=True,
    )

def get_llama_model_structured():
    """Get Llama model configured for structured output"""
    api_key = os.environ.get("LLAMA_API_KEY")
    if not api_key:
        raise ValueError("LLAMA_API_KEY environment variable is not set")

    model = ChatOpenAI(
        model="Llama-4-Maverick-17B-128E-Instruct-FP8",
        api_key=api_key,
        base_url="https://api.llama.com/compat/v1/",
        streaming=False,  # Structured output doesn't stream
    )

    # Use LangChain's with_structured_output for Pydantic model
    return model.with_structured_output(WebsiteAnalysis)

# Define the LangGraph agent
def create_agent():
    """Create a simple conversational agent using LangGraph"""

    # Initialize the model
    model = get_llama_model()

    # Define the chatbot node
    def chatbot(state: MessagesState):
        return {"messages": [model.invoke(state["messages"])]}

    # Build the graph
    graph_builder = StateGraph(MessagesState)
    graph_builder.add_node("chatbot", chatbot)
    graph_builder.add_edge(START, "chatbot")
    graph_builder.add_edge("chatbot", END)

    return graph_builder.compile()

# WebSocket endpoint for streaming
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("WebSocket connection established")

    try:
        # Create the agent
        agent = create_agent()

        while True:
            # Receive URL from client
            data = await websocket.receive_text()
            print(f"Received data: {data}")

            # Parse the incoming data
            try:
                message_data = json.loads(data)
                url = message_data.get("url", "")
                mode = message_data.get("mode", "structured")  # Default to structured
            except json.JSONDecodeError:
                # If it's not JSON, treat it as plain text URL
                url = data.strip()
                mode = "structured"

            if not url:
                await websocket.send_json({
                    "type": "error",
                    "content": "Empty URL received"
                })
                continue

            # Validate URL
            if not validate_url(url):
                await websocket.send_json({
                    "type": "error",
                    "content": "Invalid URL format. Please enter a valid URL starting with http:// or https://"
                })
                continue

            # Send status update: Capturing screenshot
            await websocket.send_json({
                "type": "status",
                "content": f"Capturing screenshot of {url}..."
            })

            # Capture screenshot
            try:
                screenshot_base64 = await capture_screenshot(url, websocket)
                print(f"Screenshot captured successfully for {url}")
            except Exception as e:
                print(f"Error capturing screenshot: {e}")
                await websocket.send_json({
                    "type": "error",
                    "content": str(e)
                })
                continue

            # Send status update: Analyzing
            await websocket.send_json({
                "type": "start",
                "content": "Analyzing website..."
            })

            # Choose analysis mode
            try:
                if mode == "structured":
                    # Use structured output (no streaming, no LangGraph wrapper)
                    structured_model = get_llama_model_structured()

                    # Create the vision message directly
                    message = HumanMessage(
                        content=[
                            {
                                "type": "text",
                                "text": f"Analyze this website screenshot from {url}. Identify the website type, primary business goal, provide a description, and list key features."
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/png;base64,{screenshot_base64}"
                                }
                            }
                        ]
                    )

                    # Invoke the structured model directly (returns WebsiteAnalysis object)
                    analysis_result = await asyncio.to_thread(structured_model.invoke, [message])

                    # analysis_result is already a WebsiteAnalysis Pydantic model
                    # Send structured result
                    await websocket.send_json({
                        "type": "structured",
                        "analysis": {
                            "website_type": analysis_result.website_type,
                            "primary_goal": analysis_result.primary_goal,
                            "description": analysis_result.description,
                            "key_features": analysis_result.key_features
                        }
                    })

                    # Send completion
                    await websocket.send_json({
                        "type": "end",
                        "content": "Analysis complete"
                    })

                else:
                    # Use original streaming mode
                    input_data = {
                        "messages": [
                            {
                                "role": "user",
                                "content": [
                                    {
                                        "type": "text",
                                        "text": f"Please describe this website screenshot from {url}. Provide details about the layout, design, key elements, and what the website appears to be about."
                                    },
                                    {
                                        "type": "image_url",
                                        "image_url": {
                                            "url": f"data:image/png;base64,{screenshot_base64}"
                                        }
                                    }
                                ]
                            }
                        ]
                    }

                    # Stream the response
                    full_response = ""
                    async for event in agent.astream_events(input_data, version="v2"):
                        kind = event["event"]

                        # Handle different event types
                        if kind == "on_chat_model_stream":
                            content = event["data"]["chunk"].content
                            if content:
                                full_response += content
                                # Send token to client
                                await websocket.send_json({
                                    "type": "token",
                                    "content": content
                                })

                    # Send completion signal
                    await websocket.send_json({
                        "type": "end",
                        "content": "Stream complete",
                        "full_response": full_response
                    })

            except Exception as e:
                print(f"Error during agent execution: {e}")
                await websocket.send_json({
                    "type": "error",
                    "content": f"Error analyzing screenshot: {str(e)}"
                })

    except WebSocketDisconnect:
        print("WebSocket connection closed")
    except Exception as e:
        print(f"Unexpected error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "content": f"Server error: {str(e)}"
            })
        except:
            pass

if __name__ == "__main__":
    import uvicorn
    # Clean up expired cache files on startup
    cleanup_expired_cache()
    uvicorn.run(app, host="0.0.0.0", port=8010)

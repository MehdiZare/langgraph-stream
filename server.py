import os
import json
from typing import Annotated
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, MessagesState, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize FastAPI app
app = FastAPI()

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
        model="Llama-3.3-8B-Instruct",
        api_key=api_key,
        base_url="https://api.llama.com/compat/v1/",
        streaming=True,
    )

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
            # Receive message from client
            data = await websocket.receive_text()
            print(f"Received message: {data}")

            # Parse the incoming message
            try:
                message_data = json.loads(data)
                user_message = message_data.get("message", "")
            except json.JSONDecodeError:
                # If it's not JSON, treat it as plain text
                user_message = data

            if not user_message:
                await websocket.send_json({
                    "type": "error",
                    "content": "Empty message received"
                })
                continue

            # Send acknowledgment
            await websocket.send_json({
                "type": "start",
                "content": "Processing your message..."
            })

            # Stream the agent's response
            try:
                # Prepare input
                input_data = {"messages": [{"role": "user", "content": user_message}]}

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
                    "content": f"Error: {str(e)}"
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
    uvicorn.run(app, host="0.0.0.0", port=8000)

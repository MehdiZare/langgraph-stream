"""
Chatbot Node

Simple conversational chatbot node for LangGraph.
"""

from langgraph.graph import MessagesState
from services.llm import get_llama_model


def chatbot_node(state: MessagesState):
    """
    Simple conversational chatbot node.

    Args:
        state: MessagesState containing conversation history

    Returns:
        Dict with updated messages list
    """
    model = get_llama_model()
    return {"messages": [model.invoke(state["messages"])]}

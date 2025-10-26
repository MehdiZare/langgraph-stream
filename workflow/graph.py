"""
LangGraph Definition

Defines the LangGraph agent with nodes and edges.
"""

from langgraph.graph import StateGraph, MessagesState, START, END
from workflow.nodes.chatbot import chatbot_node


def create_agent():
    """
    Create a simple conversational agent using LangGraph.

    The agent consists of a single chatbot node that processes
    messages and returns responses.

    Returns:
        Compiled LangGraph agent
    """
    # Build the graph
    graph_builder = StateGraph(MessagesState)
    graph_builder.add_node("chatbot", chatbot_node)
    graph_builder.add_edge(START, "chatbot")
    graph_builder.add_edge("chatbot", END)

    return graph_builder.compile()

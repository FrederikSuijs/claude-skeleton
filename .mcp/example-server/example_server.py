"""Example MCP server — drop in a tool implementation and wire it below.

Run with:
    python .mcp/example-server/example_server.py

Or register it in your client's config (see .mcp/README.md).
"""
from __future__ import annotations

import asyncio
import sys


def hello(name: str) -> str:
    """Greet someone. Replace this with your real tool logic."""
    return f"Hello, {name}!"


# MCP transports are typically registered here. The two patterns are:
#   1. mcp[cli] — official SDK: see https://github.com/modelcontextprotocol/python-sdk
#   2. fastmcp — lighter wrapper: see https://github.com/jlowin/fastmcp
#
# The shape below is the minimum you need to add real tools. Keep this
# file as a runnable reference; copy it per server and prune the example.

async def main() -> None:
    try:
        from mcp.server import Server  # type: ignore
        from mcp.server.stdio import stdio_server  # type: ignore
        from mcp.types import Tool, TextContent  # type: ignore
    except ImportError:
        sys.stderr.write(
            "MCP SDK not installed. Install with:\n"
            "    pip install mcp\n"
            "Then re-run this script.\n"
        )
        sys.exit(1)

    server = Server("example-server")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="hello",
                description="Greet someone by name.",
                inputSchema={
                    "type": "object",
                    "properties": {"name": {"type": "string"}},
                    "required": ["name"],
                },
            )
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name == "hello":
            return [TextContent(type="text", text=hello(arguments["name"]))]
        raise ValueError(f"Unknown tool: {name}")

    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())

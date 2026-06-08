# MCP servers

Drop-in directory for Model Context Protocol servers. Each subdirectory
is one server. The `example-server/` subdirectory is a runnable
reference — copy it, rename it, and replace the tool with your real
implementation.

## Layout

```
.mcp/
├── README.md           # this file
└── example-server/     # stub, safe to delete once you have a real server
    └── example_server.py
```

## Adding a new server

```bash
cp -r .mcp/example-server .mcp/my-server
# edit .mcp/my-server/example_server.py: replace the `hello` tool
mv .mcp/my-server/example_server.py .mcp/my-server/my_server.py
```

## Registering with a client

Claude Code (`.mcp.json` at repo root, alongside `package.json` / `pyproject.toml`):

```json
{
  "mcpServers": {
    "my-server": {
      "command": "python",
      "args": [".mcp/my-server/my_server.py"]
    }
  }
}
```

Cursor / other clients use a similar `mcpServers` block — see your
client's docs for the exact location.

## Dependencies

The example uses the official [`mcp`](https://github.com/modelcontextprotocol/python-sdk)
SDK. Add it to your project with:

```bash
pip install mcp
# or, with uv / poetry, your usual workflow
```

If the SDK isn't installed, the script exits with a clear install
message rather than a stack trace.

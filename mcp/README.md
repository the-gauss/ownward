# Ownward MCP server

The MCP bridge exposes Ownward's loopback-only API to Codex and ChatGPT. Launch
Ownward first; the app creates a private token at
`~/Library/Application Support/Ownward/api-token`.

Example MCP configuration:

```json
{
  "mcpServers": {
    "ownward": {
      "command": "/usr/bin/python3",
      "args": ["/Users/gauss/sandbox/ownward/mcp/ownward_mcp.py"]
    }
  }
}
```

The bridge contains no third-party Python dependencies. It offers board creation,
full task reads, team-aware task creation and updates, atomic Team/status/manual-
order moves, timeline shifting and edge resizing, structured link updates, categorized mini-tasks,
bidirectional completion references, completion actions, and a dedicated
`ownward_day_starter_context` tool.

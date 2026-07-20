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
      "args": ["/Users/gauss/Library/Application Support/Ownward/Automation/ownward_mcp.py"]
    }
  }
}
```

The bridge contains no third-party Python dependencies. It offers board creation,
full task reads, team-aware task creation and updates, atomic Team/status/manual-
order moves, timeline shifting and edge resizing, structured link updates, categorized mini-tasks,
bidirectional completion references, completion actions, a dedicated
`ownward_day_starter_context` tool, and `ownward_append_scheduled_log` for the
final Markdown response shown in Daily Log or Weekly Log.

Job Search adds six tools used by the Weekly Canada Roles Search:

- `ownward_job_search_context` returns every durable role, accumulated contact, and activity.
- `ownward_list_job_contacts` reads contacts with usefulness, response, relationship, follow-up, search, and sort filters. It is read-only so user-owned relationship judgments stay human-managed.
- `ownward_list_job_roles` supports scope, track, stage, search, and sort filters.
- `ownward_get_job_role` returns one complete record.
- `ownward_upsert_job_role` inserts or refreshes verified research idempotently.
- `ownward_update_job_role` updates user/application state and writes an activity.

These tools intentionally contain no browsing, AI, fit scoring, or resume-writing
logic. The scheduled task performs the reasoning; Ownward owns the durable data
and native management interface.

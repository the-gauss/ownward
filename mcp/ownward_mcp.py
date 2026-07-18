#!/usr/bin/env python3
"""Dependency-free MCP bridge for Ownward's loopback automation API."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


API_BASE = os.environ.get("OWNWARD_API_BASE", "http://127.0.0.1:47771")
TOKEN_PATH = Path(os.environ.get(
    "OWNWARD_API_TOKEN_FILE",
    "~/Library/Application Support/Ownward/api-token",
)).expanduser()


class OwnwardClient:
    def __init__(self, base_url: str = API_BASE, token_path: Path = TOKEN_PATH) -> None:
        self.base_url = base_url.rstrip("/")
        self.token_path = token_path

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        try:
            token = self.token_path.read_text(encoding="utf-8").strip()
        except FileNotFoundError as error:
            raise RuntimeError("Open Ownward once to create its local API token.") from error
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            try:
                message = json.loads(detail).get("error", detail)
            except json.JSONDecodeError:
                message = detail
            raise RuntimeError(f"Ownward API returned {error.code}: {message}") from error
        except urllib.error.URLError as error:
            raise RuntimeError("Ownward is not reachable. Launch the app and try again.") from error


TOOLS: list[dict[str, Any]] = [
    {
        "name": "ownward_list_boards",
        "description": "List Ownward boards and their teams.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "ownward_create_board",
        "description": "Create a new Ownward board.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string", "minLength": 1}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_list_tasks",
        "description": "List full tasks, including structured mini-tasks, links, deadlines, and status.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "board_id": {"type": "string"},
                "status": {"type": "string", "enum": ["to_do", "in_progress", "paused", "done", "discarded"]},
                "search": {"type": "string"},
                "team": {"type": "string"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_get_task",
        "description": "Read one task with its notes, links, and first-class checklist mini-tasks.",
        "inputSchema": {
            "type": "object",
            "properties": {"task_id": {"type": "string"}},
            "required": ["task_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_list_references",
        "description": "List bidirectional completion-reference groups across tasks and mini-tasks.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "ownward_create_task",
        "description": "Create a task. Markdown checklist lines in notes_markdown become structured mini-tasks.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "board_id": {"type": "string"},
                "title": {"type": "string", "minLength": 1},
                "status": {"type": "string", "enum": ["to_do", "in_progress", "paused", "done", "discarded"]},
                "team": {"type": "string"},
                "deadline_start": {"type": "string", "description": "ISO-8601 date or datetime"},
                "deadline_end": {"type": "string", "description": "ISO-8601 date or datetime"},
                "notes_markdown": {"type": "string"},
            },
            "required": ["board_id", "title"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_update_task",
        "description": "Update task fields without replacing its structured mini-tasks.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "title": {"type": "string"},
                "status": {"type": "string", "enum": ["to_do", "in_progress", "paused", "done", "discarded"]},
                "team": {"type": "string"},
                "deadline_start": {"type": "string"},
                "deadline_end": {"type": "string"},
                "notes_markdown": {"type": "string"},
                "links": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "minLength": 1},
                            "url": {"type": "string", "minLength": 1},
                        },
                        "required": ["title", "url"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["task_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_move_task",
        "description": "Atomically move a task to a workflow status and optionally a Team/manual position. Moving to Done propagates through completion references.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "status": {"type": "string", "enum": ["to_do", "in_progress", "paused", "done", "discarded"]},
                "team": {"type": "string", "description": "Destination Team. Use an empty string to remove the Team."},
                "before_task_id": {"type": "string", "description": "Place the task immediately before this task in Default Order."},
            },
            "required": ["task_id", "status"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_shift_task_schedule",
        "description": "Shift a task's timeline start and end dates together by a number of calendar days.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "days": {"type": "integer", "description": "Positive moves later; negative moves earlier."},
            },
            "required": ["task_id", "days"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_resize_task_schedule",
        "description": "Move one edge of a task's timeline range; Ownward prevents inverted date ranges.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "edge": {"type": "string", "enum": ["start", "end"]},
                "date": {"type": "string", "description": "ISO-8601 date or datetime."},
            },
            "required": ["task_id", "edge", "date"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_add_mini_task",
        "description": "Add a first-class checklist mini-task to a task.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "task_id": {"type": "string"},
                "title": {"type": "string", "minLength": 1},
                "complete": {"type": "boolean"},
                "depth": {"type": "integer", "minimum": 0},
                "category": {"type": "string"},
            },
            "required": ["task_id", "title"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_update_mini_task",
        "description": "Rename, categorize, re-indent, complete, or reopen a checklist mini-task.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "mini_task_id": {"type": "string"},
                "title": {"type": "string"},
                "complete": {"type": "boolean"},
                "depth": {"type": "integer", "minimum": 0},
                "category": {"type": "string"},
            },
            "required": ["mini_task_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_set_completion",
        "description": "Complete or reopen a task or mini-task and propagate to every referenced item.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "target_type": {"type": "string", "enum": ["task", "mini_task"]},
                "target_id": {"type": "string"},
                "complete": {"type": "boolean"},
            },
            "required": ["target_type", "target_id", "complete"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_create_reference",
        "description": "Reference completion between two tasks or mini-tasks. Completion becomes bidirectionally shared.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source_type": {"type": "string", "enum": ["task", "mini_task"]},
                "source_id": {"type": "string"},
                "target_type": {"type": "string", "enum": ["task", "mini_task"]},
                "target_id": {"type": "string"},
            },
            "required": ["source_type", "source_id", "target_type", "target_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_day_starter_context",
        "description": "Return the complete actionable context for Daily Day Starter: both boards, To Do and In Progress tasks, deadlines, notes, links, and structured mini-task workload.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
]


class MCPServer:
    def __init__(self, client: OwnwardClient | None = None) -> None:
        self.client = client or OwnwardClient()

    def handle(self, message: dict[str, Any]) -> dict[str, Any] | None:
        request_id = message.get("id")
        method = message.get("method")
        if request_id is None:
            return None
        try:
            if method == "initialize":
                result = {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "ownward", "version": "0.3.0"},
                }
            elif method == "ping":
                result = {}
            elif method == "tools/list":
                result = {"tools": TOOLS}
            elif method == "tools/call":
                params = message.get("params") or {}
                result = self.call_tool(params.get("name", ""), params.get("arguments") or {})
            else:
                return self.error(request_id, -32601, f"Method not found: {method}")
            return {"jsonrpc": "2.0", "id": request_id, "result": result}
        except Exception as error:  # MCP clients need a tool result, not a crashed bridge.
            if method == "tools/call":
                return {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {"content": [{"type": "text", "text": str(error)}], "isError": True},
                }
            return self.error(request_id, -32603, str(error))

    @staticmethod
    def error(request_id: Any, code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name == "ownward_list_boards":
            data = self.client.request("GET", "/v1/boards")
        elif name == "ownward_create_board":
            data = self.client.request("POST", "/v1/boards", {"name": arguments["name"]})
        elif name == "ownward_list_tasks":
            query = urllib.parse.urlencode({
                key: value for key, value in {
                    "board_id": arguments.get("board_id"),
                    "status": arguments.get("status"),
                    "search": arguments.get("search"),
                    "team": arguments.get("team"),
                }.items() if value is not None
            })
            data = self.client.request("GET", "/v1/tasks" + (f"?{query}" if query else ""))
        elif name == "ownward_get_task":
            data = self.client.request("GET", f"/v1/tasks/{arguments['task_id']}")
        elif name == "ownward_list_references":
            data = self.client.request("GET", "/v1/references")
        elif name == "ownward_create_task":
            body = self._task_body(arguments)
            body["boardID"] = arguments["board_id"]
            data = self.client.request("POST", "/v1/tasks", body)
        elif name == "ownward_update_task":
            data = self.client.request("PATCH", f"/v1/tasks/{arguments['task_id']}", self._task_body(arguments))
        elif name == "ownward_move_task":
            body = {"status": arguments["status"]}
            if "team" in arguments:
                body["team"] = arguments["team"]
            if "before_task_id" in arguments:
                body["beforeTaskID"] = arguments["before_task_id"]
            data = self.client.request("POST", f"/v1/tasks/{arguments['task_id']}/move", body)
        elif name == "ownward_shift_task_schedule":
            data = self.client.request(
                "POST", f"/v1/tasks/{arguments['task_id']}/schedule/shift", {"days": arguments["days"]}
            )
        elif name == "ownward_resize_task_schedule":
            data = self.client.request(
                "POST",
                f"/v1/tasks/{arguments['task_id']}/schedule/resize",
                {"edge": arguments["edge"], "date": arguments["date"]},
            )
        elif name == "ownward_add_mini_task":
            body = {"title": arguments["title"]}
            if "complete" in arguments:
                body["isCompleted"] = arguments["complete"]
            if "depth" in arguments:
                body["depth"] = arguments["depth"]
            if "category" in arguments:
                body["category"] = arguments["category"]
            data = self.client.request("POST", f"/v1/tasks/{arguments['task_id']}/mini-tasks", body)
        elif name == "ownward_update_mini_task":
            body = {}
            if "title" in arguments:
                body["title"] = arguments["title"]
            if "complete" in arguments:
                body["isCompleted"] = arguments["complete"]
            if "depth" in arguments:
                body["depth"] = arguments["depth"]
            if "category" in arguments:
                body["category"] = arguments["category"]
            data = self.client.request("PATCH", f"/v1/mini-tasks/{arguments['mini_task_id']}", body)
        elif name == "ownward_set_completion":
            data = self.client.request("POST", "/v1/completion", {
                "target": {"type": arguments["target_type"], "id": arguments["target_id"]},
                "complete": arguments["complete"],
            })
        elif name == "ownward_create_reference":
            data = self.client.request("POST", "/v1/references", {
                "source": {"type": arguments["source_type"], "id": arguments["source_id"]},
                "target": {"type": arguments["target_type"], "id": arguments["target_id"]},
            })
        elif name == "ownward_day_starter_context":
            data = self.client.request("GET", "/v1/day-starter/context")
        else:
            raise ValueError(f"Unknown Ownward tool: {name}")
        return {
            "content": [{"type": "text", "text": json.dumps(data, indent=2, ensure_ascii=False)}],
            "structuredContent": {"data": data},
            "isError": False,
        }

    @staticmethod
    def _task_body(arguments: dict[str, Any]) -> dict[str, Any]:
        mapping = {
            "title": "title",
            "status": "status",
            "team": "team",
            "deadline_start": "deadlineStart",
            "deadline_end": "deadlineEnd",
            "notes_markdown": "notesMarkdown",
            "links": "links",
        }
        return {target: arguments[source] for source, target in mapping.items() if source in arguments}


def main() -> None:
    server = MCPServer()
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
            response = server.handle(message)
        except json.JSONDecodeError as error:
            response = MCPServer.error(None, -32700, f"Parse error: {error}")
        if response is not None:
            sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()

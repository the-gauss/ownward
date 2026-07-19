#!/usr/bin/env python3
"""Dependency-free MCP bridge for Ownward's loopback automation API."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
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


DATE_OR_NULL = {
    "anyOf": [
        {"type": "string", "description": "ISO-8601 date or datetime"},
        {"type": "null", "description": "Clear the stored date"},
    ]
}
OPTIONAL_INTEGER = {"anyOf": [{"type": "integer"}, {"type": "null"}]}
OPTIONAL_ID = {"anyOf": [{"type": "string"}, {"type": "null"}]}
TRACK_SCHEMA = {"type": "string", "enum": ["backup", "canon", "backup_extreme"]}
STAGE_SCHEMA = {
    "type": "string",
    "enum": ["researching", "ready_to_apply", "applied", "interviewing", "offer", "rejected", "closed", "archived"],
}
LOCATION_SCHEMA = {
    "type": "object",
    "properties": {
        "city": {"type": "string"},
        "province": {"type": "string"},
        "work_arrangement": {"type": "string"},
    },
    "additionalProperties": False,
}
POSTING_SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string"},
        "verification_tier": {"type": "string"},
        "job_url": {"type": "string"},
        "official_careers_url": {"type": "string"},
        "posted_date": DATE_OR_NULL,
        "deadline_date": DATE_OR_NULL,
        "deadline_notes": {"type": "string"},
        "last_verified": DATE_OR_NULL,
    },
    "additionalProperties": False,
}
POSITION_SCHEMA = {
    "type": "object",
    "properties": {
        "compensation": {"type": "string"},
        "employment_type": {"type": "string"},
        "experience_requirement": {"type": "string"},
        "relevant_skills": {"type": "string"},
    },
    "additionalProperties": False,
}
CONTACT_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "name": {"type": "string"},
        "title_or_department": {"type": "string"},
        "email": {"type": "string"},
        "phone": {"type": "string"},
        "source_url": {"type": "string"},
        "confidence": {"type": "string"},
        "is_primary": {"type": "boolean"},
    },
    "additionalProperties": False,
}
OUTREACH_SCHEMA = {
    "type": "object",
    "properties": {
        "best_channel": {"type": "string"},
        "suggested_angle": {"type": "string"},
        "confidence": {"type": "string"},
    },
    "additionalProperties": False,
}
APPLICATION_SCHEMA = {
    "type": "object",
    "properties": {
        "applied": {"type": "boolean"},
        "date_applied": DATE_OR_NULL,
        "contacted": {"type": "boolean"},
        "follow_up_date": DATE_OR_NULL,
        "response": {"type": "string"},
        "notes": {"type": "string"},
        "last_mail_checked": DATE_OR_NULL,
    },
    "additionalProperties": False,
}
RESUME_SCHEMA = {
    "type": "object",
    "properties": {
        "source_path": {"type": "string"},
        "fact_check_status": {"type": "string"},
        "last_reviewed": DATE_OR_NULL,
    },
    "additionalProperties": False,
}
EVIDENCE_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "title": {"type": "string", "minLength": 1},
        "url": {"type": "string", "minLength": 1},
        "note": {"type": "string"},
    },
    "required": ["title", "url"],
    "additionalProperties": False,
}


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
    {
        "name": "ownward_append_scheduled_log",
        "description": "Persist the final Markdown result of a scheduled run in its read-only Ownward log. Retention is enforced by Ownward.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "kind": {"type": "string", "enum": ["daily_day_starter", "weekly_canada_roles_search"]},
                "markdown": {"type": "string", "minLength": 1},
            },
            "required": ["kind", "markdown"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_job_search_context",
        "description": "Return every durable job-role record and activity entry. Use this first instead of tracker files, Notion, or task memory.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "ownward_list_job_roles",
        "description": "List durable job roles with optional lifecycle, track, stage, search, and sort filters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "track": TRACK_SCHEMA,
                "stage": STAGE_SCHEMA,
                "scope": {
                    "type": "string",
                    "enum": ["all", "needsAction", "applications", "interviews", "followUps", "closed", "archive"],
                },
                "search": {"type": "string"},
                "sort": {"type": "string", "enum": ["nextAction", "recentlyUpdated", "employer", "priority"]},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_get_job_role",
        "description": "Read one complete job-role record, including verified evidence and protected human application history.",
        "inputSchema": {
            "type": "object",
            "properties": {"job_role_id": {"type": "string"}},
            "required": ["job_role_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_upsert_job_role",
        "description": "Create or idempotently refresh a verified role. Existing application history, advanced stage, and linked task are preserved.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "track": TRACK_SCHEMA,
                "priority": OPTIONAL_INTEGER,
                "employer": {"type": "string", "minLength": 1},
                "role": {"type": "string", "minLength": 1},
                "location": LOCATION_SCHEMA,
                "posting": POSTING_SCHEMA,
                "position": POSITION_SCHEMA,
                "contacts": {"type": "array", "items": CONTACT_SCHEMA},
                "outreach": OUTREACH_SCHEMA,
                "application": APPLICATION_SCHEMA,
                "resume": RESUME_SCHEMA,
                "evidence": {"type": "array", "items": EVIDENCE_SCHEMA},
                "stage": STAGE_SCHEMA,
                "linked_task_id": OPTIONAL_ID,
            },
            "required": ["track", "employer", "role"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ownward_update_job_role",
        "description": "Patch only the supplied fields of one role. Omitted fields are preserved; null clears an optional date, priority, or linked task.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "job_role_id": {"type": "string"},
                "track": TRACK_SCHEMA,
                "priority": OPTIONAL_INTEGER,
                "employer": {"type": "string"},
                "role": {"type": "string"},
                "location": LOCATION_SCHEMA,
                "posting": POSTING_SCHEMA,
                "position": POSITION_SCHEMA,
                "contacts": {"type": "array", "items": CONTACT_SCHEMA},
                "outreach": OUTREACH_SCHEMA,
                "application": APPLICATION_SCHEMA,
                "resume": RESUME_SCHEMA,
                "evidence": {"type": "array", "items": EVIDENCE_SCHEMA},
                "stage": STAGE_SCHEMA,
                "linked_task_id": OPTIONAL_ID,
                "activity_kind": {
                    "type": "string",
                    "enum": ["updated", "stage_changed", "application_updated", "mailbox_updated", "linked_task_updated", "resume_updated"],
                },
                "activity_detail": {"type": "string"},
            },
            "required": ["job_role_id"],
            "additionalProperties": False,
        },
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
                    "serverInfo": {"name": "ownward", "version": "0.5.0"},
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
        elif name == "ownward_append_scheduled_log":
            data = self.client.request("POST", "/v1/scheduled-logs", {
                "kind": arguments["kind"], "markdown": arguments["markdown"],
            })
        elif name == "ownward_job_search_context":
            data = self.client.request("GET", "/v1/job-search/context")
        elif name == "ownward_list_job_roles":
            query = urllib.parse.urlencode({
                key: value for key, value in {
                    "track": arguments.get("track"),
                    "stage": arguments.get("stage"),
                    "scope": arguments.get("scope"),
                    "search": arguments.get("search"),
                    "sort": arguments.get("sort"),
                }.items() if value is not None
            })
            data = self.client.request("GET", "/v1/job-search/roles" + (f"?{query}" if query else ""))
        elif name == "ownward_get_job_role":
            data = self.client.request("GET", f"/v1/job-search/roles/{arguments['job_role_id']}")
        elif name == "ownward_upsert_job_role":
            data = self.client.request("POST", "/v1/job-search/roles/upsert", self._job_role_body(arguments))
        elif name == "ownward_update_job_role":
            body = {"patch": self._job_role_patch(arguments)}
            if "activity_kind" in arguments:
                body["activityKind"] = arguments["activity_kind"]
            if "activity_detail" in arguments:
                body["activityDetail"] = arguments["activity_detail"]
            data = self.client.request("PATCH", f"/v1/job-search/roles/{arguments['job_role_id']}", body)
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

    @staticmethod
    def _map_fields(source: dict[str, Any], mapping: dict[str, str]) -> dict[str, Any]:
        return {target: source[key] for key, target in mapping.items() if key in source}

    @classmethod
    def _location(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "city": "city", "province": "province", "work_arrangement": "workArrangement",
        })
        if complete:
            return {"city": "", "province": "", "workArrangement": ""} | result
        return result

    @classmethod
    def _posting(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "status": "status",
            "verification_tier": "verificationTier",
            "job_url": "jobURL",
            "official_careers_url": "officialCareersURL",
            "posted_date": "postedDate",
            "deadline_date": "deadlineDate",
            "deadline_notes": "deadlineNotes",
            "last_verified": "lastVerified",
        })
        if complete:
            defaults = {
                "status": "", "verificationTier": "", "jobURL": "",
                "officialCareersURL": "", "deadlineNotes": "",
            }
            return defaults | result
        return result

    @classmethod
    def _position(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "compensation": "compensation",
            "employment_type": "employmentType",
            "experience_requirement": "experienceRequirement",
            "relevant_skills": "relevantSkills",
        })
        if complete:
            defaults = {key: "" for key in ["compensation", "employmentType", "experienceRequirement", "relevantSkills"]}
            return defaults | result
        return result

    @classmethod
    def _outreach(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "best_channel": "bestChannel", "suggested_angle": "suggestedAngle", "confidence": "confidence",
        })
        if complete:
            return {"bestChannel": "", "suggestedAngle": "", "confidence": ""} | result
        return result

    @classmethod
    def _application(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "applied": "applied",
            "date_applied": "dateApplied",
            "contacted": "contacted",
            "follow_up_date": "followUpDate",
            "response": "response",
            "notes": "notes",
            "last_mail_checked": "lastMailChecked",
        })
        if complete:
            defaults = {"applied": False, "contacted": False, "response": "", "notes": ""}
            return defaults | result
        return result

    @classmethod
    def _resume(cls, value: dict[str, Any], complete: bool = False) -> dict[str, Any]:
        result = cls._map_fields(value, {
            "source_path": "sourcePath", "fact_check_status": "factCheckStatus", "last_reviewed": "lastReviewed",
        })
        if complete:
            return {"sourcePath": "", "factCheckStatus": ""} | result
        return result

    @classmethod
    def _contacts(cls, values: list[dict[str, Any]]) -> list[dict[str, Any]]:
        mapped = []
        for value in values:
            item = cls._map_fields(value, {
                "id": "id",
                "name": "name",
                "title_or_department": "titleOrDepartment",
                "email": "email",
                "phone": "phone",
                "source_url": "sourceURL",
                "confidence": "confidence",
                "is_primary": "isPrimary",
            })
            defaults = {
                "id": str(uuid.uuid4()), "name": "", "titleOrDepartment": "", "email": "",
                "phone": "", "sourceURL": "", "confidence": "", "isPrimary": False,
            }
            mapped.append(defaults | item)
        return mapped

    @classmethod
    def _evidence(cls, values: list[dict[str, Any]]) -> list[dict[str, Any]]:
        mapped = []
        for value in values:
            item = cls._map_fields(value, {"id": "id", "title": "title", "url": "url", "note": "note"})
            mapped.append({"id": str(uuid.uuid4()), "note": ""} | item)
        return mapped

    @classmethod
    def _job_role_body(cls, arguments: dict[str, Any]) -> dict[str, Any]:
        body: dict[str, Any] = {
            "track": arguments["track"],
            "employer": arguments["employer"],
            "role": arguments["role"],
            "location": cls._location(arguments.get("location", {}), complete=True),
            "posting": cls._posting(arguments.get("posting", {}), complete=True),
            "position": cls._position(arguments.get("position", {}), complete=True),
            "contacts": cls._contacts(arguments.get("contacts", [])),
            "outreach": cls._outreach(arguments.get("outreach", {}), complete=True),
            "application": cls._application(arguments.get("application", {}), complete=True),
            "resume": cls._resume(arguments.get("resume", {}), complete=True),
            "evidence": cls._evidence(arguments.get("evidence", [])),
            "stage": arguments.get("stage", "researching"),
        }
        if "priority" in arguments:
            body["priority"] = arguments["priority"]
        if "linked_task_id" in arguments:
            body["linkedTaskID"] = arguments["linked_task_id"]
        return body

    @classmethod
    def _job_role_patch(cls, arguments: dict[str, Any]) -> dict[str, Any]:
        patch = cls._map_fields(arguments, {
            "track": "track", "priority": "priority", "employer": "employer", "role": "role",
            "stage": "stage", "linked_task_id": "linkedTaskID",
        })
        if "location" in arguments:
            patch["location"] = cls._location(arguments["location"])
        if "posting" in arguments:
            patch["posting"] = cls._posting(arguments["posting"])
        if "position" in arguments:
            patch["position"] = cls._position(arguments["position"])
        if "contacts" in arguments:
            patch["contacts"] = cls._contacts(arguments["contacts"])
        if "outreach" in arguments:
            patch["outreach"] = cls._outreach(arguments["outreach"])
        if "application" in arguments:
            patch["application"] = cls._application(arguments["application"])
        if "resume" in arguments:
            patch["resume"] = cls._resume(arguments["resume"])
        if "evidence" in arguments:
            patch["evidence"] = cls._evidence(arguments["evidence"])
        return patch


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

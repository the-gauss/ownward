import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("ownward_mcp.py")
SPEC = importlib.util.spec_from_file_location("ownward_mcp", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class FakeClient:
    def __init__(self):
        self.calls = []

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        return {"ok": True}


class MCPServerTests(unittest.TestCase):
    def test_lists_tools_over_stdio(self):
        messages = "\n".join([
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}),
            json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}),
            json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}),
        ]) + "\n"
        result = subprocess.run([sys.executable, str(SCRIPT)], input=messages, text=True, capture_output=True, check=True)
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(responses[0]["result"]["serverInfo"]["name"], "ownward")
        self.assertEqual(responses[0]["result"]["serverInfo"]["version"], "0.5.0")
        tool_names = {tool["name"] for tool in responses[1]["result"]["tools"]}
        self.assertIn("ownward_day_starter_context", tool_names)
        self.assertIn("ownward_append_scheduled_log", tool_names)
        self.assertIn("ownward_shift_task_schedule", tool_names)
        self.assertIn("ownward_resize_task_schedule", tool_names)
        self.assertIn("ownward_job_search_context", tool_names)
        self.assertIn("ownward_list_job_contacts", tool_names)
        self.assertIn("ownward_list_job_roles", tool_names)
        self.assertIn("ownward_get_job_role", tool_names)
        self.assertIn("ownward_upsert_job_role", tool_names)
        self.assertIn("ownward_update_job_role", tool_names)
        list_roles = next(tool for tool in responses[1]["result"]["tools"] if tool["name"] == "ownward_list_job_roles")
        self.assertIn("archive", list_roles["inputSchema"]["properties"]["scope"]["enum"])

    def test_job_search_context_and_lists_map_to_durable_api(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)

        server.call_tool("ownward_job_search_context", {})
        server.call_tool("ownward_list_job_roles", {
            "track": "backup", "scope": "needsAction", "search": "municipal"
        })
        server.call_tool("ownward_list_job_contacts", {
            "response_status": "responded", "relationship_level": 5, "sort": "relationship_level"
        })

        self.assertEqual(client.calls[0], ("GET", "/v1/job-search/context", None))
        self.assertTrue(client.calls[1][0] == "GET")
        self.assertTrue(client.calls[1][1].startswith("/v1/job-search/roles?"))
        self.assertIn("track=backup", client.calls[1][1])
        self.assertIn("scope=needsAction", client.calls[1][1])
        self.assertIn("search=municipal", client.calls[1][1])
        self.assertEqual(
            client.calls[2],
            ("GET", "/v1/job-search/contacts?response_status=responded&relationship_level=5&sort=relationship_level", None),
        )

    def test_scheduled_log_maps_final_markdown_to_ownward(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)

        server.call_tool("ownward_append_scheduled_log", {
            "kind": "daily_day_starter", "markdown": "# Today\n- [ ] Focus"
        })

        self.assertEqual(client.calls[0], (
            "POST", "/v1/scheduled-logs",
            {"kind": "daily_day_starter", "markdown": "# Today\n- [ ] Focus"},
        ))

    def test_upsert_job_role_maps_complete_research_record_without_fit_features(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_upsert_job_role", {
            "track": "backup",
            "priority": 1,
            "employer": "Wesway",
            "role": "Data Specialist",
            "location": {"city": "Thunder Bay", "province": "ON"},
            "posting": {
                "status": "Open",
                "verification_tier": "Official exact posting",
                "job_url": "https://example.ca/job",
                "last_verified": "2026-07-18",
            },
            "contacts": [{
                "name": "Recruitment",
                "email": "jobs@example.ca",
                "source_url": "https://example.ca/contact",
                "is_primary": True,
            }],
            "resume": {"source_path": "/tmp/Wesway.tex"},
            "stage": "ready_to_apply",
        })

        method, path, body = client.calls[0]
        self.assertEqual((method, path), ("POST", "/v1/job-search/roles/upsert"))
        self.assertEqual(body["posting"]["verificationTier"], "Official exact posting")
        self.assertEqual(body["posting"]["lastVerified"], "2026-07-18")
        self.assertEqual(body["contacts"][0]["sourceURL"], "https://example.ca/contact")
        self.assertEqual(body["resume"]["sourcePath"], "/tmp/Wesway.tex")
        self.assertNotIn("fit", json.dumps(body).lower())

    def test_update_job_role_preserves_omitted_fields_and_forwards_explicit_nulls(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_update_job_role", {
            "job_role_id": "role-1",
            "stage": "applied",
            "application": {
                "applied": True,
                "date_applied": "2026-07-18",
                "follow_up_date": None,
                "notes": "Submitted by me",
            },
            "linked_task_id": None,
            "activity_kind": "application_updated",
            "activity_detail": "Marked applied",
        })

        method, path, body = client.calls[0]
        self.assertEqual((method, path), ("PATCH", "/v1/job-search/roles/role-1"))
        self.assertEqual(body["patch"]["stage"], "applied")
        self.assertIsNone(body["patch"]["application"]["followUpDate"])
        self.assertIsNone(body["patch"]["linkedTaskID"])
        self.assertNotIn("posting", body["patch"])
        self.assertEqual(body["activityKind"], "application_updated")

    def test_get_job_role_maps_record_id(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_get_job_role", {"job_role_id": "role-1"})
        self.assertEqual(client.calls[0], ("GET", "/v1/job-search/roles/role-1", None))

    def test_maps_create_task_to_api(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        response = server.call_tool("ownward_create_task", {
            "board_id": "board-1", "title": "System Design", "notes_markdown": "- [ ] API design"
        })
        self.assertFalse(response["isError"])
        self.assertEqual(client.calls[0], (
            "POST", "/v1/tasks", {"title": "System Design", "notesMarkdown": "- [ ] API design", "boardID": "board-1"}
        ))

    def test_update_task_forwards_structured_links(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        links = [{"title": "Design notes", "url": "https://example.com/design"}]
        server.call_tool("ownward_update_task", {"task_id": "task-1", "links": links})
        self.assertEqual(client.calls[0], ("PATCH", "/v1/tasks/task-1", {"links": links}))

    def test_completion_tool_targets_mini_tasks(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_set_completion", {
            "target_type": "mini_task", "target_id": "mini-1", "complete": True
        })
        self.assertEqual(client.calls[0][2]["target"], {"type": "mini_task", "id": "mini-1"})

    def test_adds_structured_mini_task(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_add_mini_task", {"task_id": "task-1", "title": "API design", "depth": 1, "category": "Architecture"})
        self.assertEqual(client.calls[0], ("POST", "/v1/tasks/task-1/mini-tasks", {"title": "API design", "depth": 1, "category": "Architecture"}))

    def test_creates_board_and_maps_team(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_create_board", {"name": "Personal"})
        server.call_tool("ownward_create_task", {"board_id": "board-1", "title": "Plan", "team": "Strategy"})
        self.assertEqual(client.calls[0], ("POST", "/v1/boards", {"name": "Personal"}))
        self.assertEqual(client.calls[1][2]["team"], "Strategy")

    def test_swimlane_move_maps_team_and_manual_target_atomically(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_move_task", {
            "task_id": "task-1",
            "status": "in_progress",
            "team": "Tutorials",
            "before_task_id": "task-2",
        })
        self.assertEqual(client.calls[0], (
            "POST",
            "/v1/tasks/task-1/move",
            {"status": "in_progress", "team": "Tutorials", "beforeTaskID": "task-2"},
        ))

    def test_timeline_schedule_tools_map_to_invariant_preserving_routes(self):
        client = FakeClient()
        server = MODULE.MCPServer(client)
        server.call_tool("ownward_shift_task_schedule", {"task_id": "task-1", "days": 4})
        server.call_tool("ownward_resize_task_schedule", {
            "task_id": "task-1", "edge": "end", "date": "2026-08-30"
        })
        self.assertEqual(client.calls[0], (
            "POST", "/v1/tasks/task-1/schedule/shift", {"days": 4}
        ))
        self.assertEqual(client.calls[1], (
            "POST", "/v1/tasks/task-1/schedule/resize", {"edge": "end", "date": "2026-08-30"}
        ))


if __name__ == "__main__":
    unittest.main()

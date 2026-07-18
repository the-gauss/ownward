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
        self.assertEqual(responses[0]["result"]["serverInfo"]["version"], "0.3.0")
        tool_names = {tool["name"] for tool in responses[1]["result"]["tools"]}
        self.assertIn("ownward_day_starter_context", tool_names)
        self.assertIn("ownward_shift_task_schedule", tool_names)
        self.assertIn("ownward_resize_task_schedule", tool_names)

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

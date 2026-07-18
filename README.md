# Ownward

Ownward is a native macOS project and task manager built to replace the Minkops
and Myndral Notion Kanbans without becoming a general-purpose Notion clone.

The initial app includes:

- A full-height, collapsible macOS source sidebar.
- Kanban, table, and timeline views in the main pane.
- A selection-driven inspector for deadlines, teams, notes, links, and categorized mini-tasks.
- Three active Kanban columns: To Do, In Progress, and Done; Paused and Discarded live as saved views.
- Drag-and-drop status movement, including aligned Team swimlanes across every status.
- Subtly tinted To Do, In Progress, and Done headers plus compact, scan-friendly cards.
- Contextual grouping and sorting across Kanban, table, and Gantt-style timeline views, with explicit None and Default Order resets.
- A resizable Table task column controlled from the toolbar.
- A date-scaled timeline with a compact task column, progress fills, drag-to-shift bars, and independently resizable start/end edges.
- Apple System, Paper Light, and Paper Dark appearance choices, plus Command +/- zoom.
- First-class checklist mini-tasks extracted from Markdown checklists.
- Bidirectional completion references between any tasks or mini-tasks.
- Atomic local persistence under `~/Library/Application Support/Ownward`.
- A bearer-protected loopback API and dependency-free MCP bridge for Codex and ChatGPT.
- A dedicated Daily Day Starter context endpoint/tool.
- Locked-screen API readiness after the first login following a reboot, so auto-wake schedules do not depend on a visible window.

## Run

```bash
./script/build_and_run.sh
```

Build and validate the local release bundle:

```bash
./script/build_and_run.sh --release --verify
```

The resulting locally signed app is written to `dist/Ownward.app`. Public distribution still requires an Apple Developer ID signature and notarization.

Install the final local build in `/Applications`, place the MCP bridge at its
stable Application Support path, and register the 3:55 a.m. scheduled launcher:

```bash
./script/install_local.sh
```

The Codex Run action uses the same script. Tests:

```bash
swift test
python3 -m unittest mcp/test_ownward_mcp.py -v
```

API details are in [docs/API.md](docs/API.md), and MCP setup is in
[mcp/README.md](mcp/README.md).

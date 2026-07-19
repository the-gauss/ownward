# Ownward

Ownward is a native macOS workspace with two focused modes:

- **Project Management** replaces the Minkops and Myndral Notion Kanbans.
- **Job Search** is the durable system of record for scheduled role research,
  application tracking, contacts, evidence, and follow-ups.

Project Management includes:

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
- A read-only Daily Log with only the current scheduled briefing and a native
  Ownward notification for each persisted result.
- Locked-screen API readiness after the first login following a reboot, so auto-wake schedules do not depend on a visible window.

Job Search includes:

- A responsive opportunity list that progressively reveals columns as the
  window grows, with native search, track filters, sorting, and focused smart views.
- A selection-driven inspector for application state, posting details, public
  contacts, outreach guidance, evidence, linked project tasks, and immutable activity history.
- A single **Show Resume in Finder** action that resolves the role's recorded
  `.tex` baseline, opens its containing folder, and selects the exact source;
  resume writing, compilation, and fit scoring intentionally stay outside the app.
- An editable native form for user-owned status, dates, notes, contacts, and
  research data.
- Idempotent job-role upserts that refresh research evidence without overwriting
  application history or advanced pipeline state.
- A complete loopback API and five MCP tools used by the Weekly Canada Roles
  Search, so the schedule no longer depends on JSON, Notion, or conversational memory.
- A read-only Weekly Log with only the current scheduled summary.

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

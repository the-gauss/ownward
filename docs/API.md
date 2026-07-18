# Ownward local API

Ownward serves a versioned JSON API on `127.0.0.1:47771`. It never binds to a
LAN or public interface. Except for health checks, requests require:

```text
Authorization: Bearer <token>
```

The app creates the token with owner-only file permissions at
`~/Library/Application Support/Ownward/api-token`. Identifiers are UUID strings,
dates are ISO-8601, and statuses are `to_do`, `in_progress`, `paused`, `done`, or
`discarded`.

The API starts during application bootstrap rather than waiting for a window to
appear. Workspace and token files use protection-until-first-authentication, so
the Daily Day Starter can connect after macOS auto-wakes while the screen remains
locked, provided the user has logged in once since the last reboot.

The local installer registers a user LaunchAgent that opens Ownward at login and
again at 3:55 a.m. The app starts the API during bootstrap, before its window is
needed, so a scheduled Codex task can read and write through MCP while the screen
is locked.

## Read routes

| Route | Purpose |
|---|---|
| `GET /v1/health` | Process/API readiness; no token required. |
| `GET /v1/boards` | Boards and their actual teams. |
| `GET /v1/tasks` | Full tasks; supports `board_id`, `status`, `team`, and `search`. |
| `GET /v1/tasks/{id}` | One task with notes, links, and structured mini-tasks. |
| `GET /v1/references` | Completion-reference groups across both item kinds. |
| `GET /v1/day-starter/context` | Both boards plus every To Do/In Progress task, mini-task workload, deadlines, links, notes, and references. |

## Write routes

| Route | Purpose |
|---|---|
| `POST /v1/boards` | Create a board. |
| `POST /v1/tasks` | Create a task; Markdown checklist lines are promoted into mini-tasks. |
| `PATCH /v1/tasks/{id}` | Update title, status, team, deadline, notes, or links. |
| `POST /v1/tasks/{id}/move` | Atomically move a task to a status, Team, and optional position before another task. |
| `POST /v1/tasks/{id}/schedule/shift` | Shift both timeline dates by a signed number of calendar days. |
| `POST /v1/tasks/{id}/schedule/resize` | Move the start or end edge while preventing an inverted range. |
| `POST /v1/tasks/{id}/mini-tasks` | Add a categorized structured checklist item. |
| `PATCH /v1/mini-tasks/{id}` | Rename, categorize, re-indent, complete, or reopen a mini-task. |
| `POST /v1/completion` | Complete/reopen a task or mini-task with reference propagation. |
| `POST /v1/references` | Create or merge a bidirectional completion reference. |

## Reference semantics

A reference is a shared-completion group, not a hyperlink. When any member is
completed or reopened, every member is updated in the same persisted mutation.
Full tasks retain their previous active status so reopening restores the correct
column. References may contain tasks, mini-tasks, or both, and overlapping groups
merge to avoid cyclic propagation.

## Daily Day Starter

`GET /v1/day-starter/context` is the replacement for the schedule's Notion pass.
It intentionally returns the complete structured context rather than a summary:
the schedule can count remaining mini-tasks, calculate quotas, prioritize deadline
ranges, inspect links/notes, and then write status or completion changes through
the same API. Existing Codex schedules are not modified by this repository.

Grouping, sorting, theme, zoom, and Table column width remain local presentation preferences rather than automation data. Team/status/manual-position changes and timeline edits are exposed because they mutate the shared task model.

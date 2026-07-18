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
| `GET /v1/job-search/context` | Every job role plus its activity history; intended as the schedule's complete source of truth. |
| `GET /v1/job-search/roles` | Filtered and sorted roles; supports `scope`, `track`, `stage`, `search`, and `sort`. |
| `GET /v1/job-search/roles/{id}` | One complete job role. |

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
| `POST /v1/job-search/roles/upsert` | Idempotently insert or refresh a role by canonical posting URL, with employer/role/location fallback identity. |
| `PATCH /v1/job-search/roles/{id}` | Update selected role fields and append a dated activity entry. Explicit JSON `null` clears nullable values. |

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

## Weekly role search

`GET /v1/job-search/context` replaces the schedule's JSON list, Notion tracker,
and conversational-memory dependency. Each role carries its track and priority;
employer, title, location, and stage; canonical and official posting URLs;
verification, posted, deadline, and last-checked data; compensation and position
details; public contacts with evidence URLs; outreach guidance; application and
mail-check history; a resume source path; linked Project Management task; and
supporting evidence.

Upserts are deliberately asymmetric: fresh research can update posting,
position, contact, outreach, resume, and evidence fields, while existing
application history, a more advanced user stage, creation time, and linked task
are preserved. Every insert, refresh, stage change, application update, mailbox
update, link change, and resume update can be recorded in the activity ledger.

Valid role filters are:

- `scope`: `all`, `needsAction`, `applications`, `interviews`, `followUps`, `closed`, `archive`
- `track`: `backup`, `canon`, `backup_extreme`
- `stage`: `researching`, `ready_to_apply`, `applied`, `interviewing`, `offer`, `rejected`, `closed`, `archived`
- `sort`: `nextAction`, `recentlyUpdated`, `employer`, `priority`

Fit scoring and resume generation are intentionally absent. The app stores only
the path metadata required to resolve the role-specific TeX source. **Show Resume
in Finder** opens its containing folder and selects the exact `.tex` file; Ownward
does not compile or open a PDF.

Grouping, sorting, theme, zoom, and Table column width remain local presentation preferences rather than automation data. Team/status/manual-position changes and timeline edits are exposed because they mutate the shared task model.

# Design QA

## Source visual truth

- Rich timeline reference: `/Users/gauss/sandbox/ownward/design-qa-artifacts/reference-rich-dark-timeline.png`
- Categorized checklist issue: `/Users/gauss/sandbox/ownward/design-qa-artifacts/reference-categorized-checklist.png`
- Over-wide reference picker issue: `/Users/gauss/sandbox/ownward/design-qa-artifacts/reference-wide-picker.png`

## Rendered implementation

- Paper Dark Gantt timeline: `/Users/gauss/sandbox/ownward/design-qa-artifacts/final-dark-gantt-timeline.png`
- Categorized checklist inspector: `/Users/gauss/sandbox/ownward/design-qa-artifacts/final-categorized-checklist.png`
- Compact searchable reference picker: `/Users/gauss/sandbox/ownward/design-qa-artifacts/final-compact-reference-picker.png`
- Adaptive Apple System window with Readex Pro wordmark: `/Users/gauss/sandbox/ownward/design-qa-artifacts/release-adaptive-window.jpeg`
- Paper Dark release with dark cube icon treatment: `/Users/gauss/sandbox/ownward/design-qa-artifacts/release-paper-dark.jpeg`
- Final installed Apple System release: `/Users/gauss/sandbox/ownward/design-qa-artifacts/final-installed-apple-system.jpeg`
- Light/dark icon comparison: `/Users/gauss/sandbox/ownward/design-qa-artifacts/icon-light-dark-comparison.jpg`

## State and viewport

- App: native macOS Ownward window
- Board: Minkops Kanban
- Timeline state: Paper Dark, grouped by Status, centered on Today
- Checklist state: Leetcode DSA selected, inspector open, first eight mini-tasks shown
- Timeline implementation viewport: 1349 x 732
- Inspector/picker implementation viewport: 1171 x 732
- Source timeline crop: 1364 x 442
- Final adaptive window: 1240 x 746; verified settable at 1000 x 600

## Comparison evidence

- Full timeline comparison: `/Users/gauss/sandbox/ownward/design-qa-artifacts/timeline-comparison.png`
- Focused checklist comparison: `/Users/gauss/sandbox/ownward/design-qa-artifacts/checklist-comparison.png`
- Focused reference-picker comparison: `/Users/gauss/sandbox/ownward/design-qa-artifacts/reference-picker-comparison.png`

The timeline reference is an inspirational chart crop rather than a full-window mock, so the implementation comparison focuses on its calendar axis, current-date marker, proportional bars, lane hierarchy, density, and dark visual treatment. Ownward intentionally keeps its native sidebar, toolbar, task labels, true date span, status groups, and checklist-progress information.

## Findings

No actionable P0, P1, or P2 issues remain.

- Fonts and typography: Apple System uses San Francisco and native control typography. Paper Light and Paper Dark consistently use Ubuntu for UI and metadata. Task/bar labels remain readable at default size and at supported zoom limits.
- Spacing and layout rhythm: the timeline has fixed task labels, aligned 52-point rows, 34-point calendar days, compact group headers, and proportional bars. The compact picker is fixed at 300 x 360 rather than expanding to the window width.
- Colors and tokens: Apple System follows macOS appearance. Paper Light uses `#f0ead8` / `#1d1d1b`; Paper Dark reverses them. Completion, destructive, status, weekend, selection, progress, and today-marker colors retain semantic contrast.
- Image quality and assets: the views use native SF Symbols and SwiftUI drawing primitives appropriate for functional charts. No raster product imagery, placeholder art, handwritten SVG, or substituted visual asset is present.
- Brand assets: generated light and dark macOS squircle icons use a hollow monochrome cube with two internal mini-cubes. The sidebar wordmark uses bundled Readex Pro Semibold and follows the active ink color.
- Copy and content: `Team` replaces `Workstream` throughout the UI. Group, sort, Today, category, board, and reference labels are direct and self-explanatory.
- Accessibility and resilience: controls expose native labels and keyboard focus, Command +/- zoom is bounded from 70% to 150%, toolbar chrome stays unscaled and unclipped, and the timeline scrolls horizontally without collapsing the task-label column.

## Comparison history

1. P1: the original timeline was a vertically stacked date list with full-width decorative bars, so duration, overlap, chronology, progress, and current date could not be understood visually.
   - Fix: replaced it with a Gantt-style calendar axis, proportional task spans, progress fill, status color, grouped lanes, today marker, horizontal navigation, and a working Today action.
   - Post-fix evidence: `final-dark-gantt-timeline.png` and `timeline-comparison.png`.
2. P2: Markdown `##` headings remained in notes while checklist items lost their semantic categories.
   - Fix: parser and schema now promote level-two headings into mini-task categories, migration enriches existing tasks, and the inspector renders category headers while preserving prose notes.
   - Post-fix evidence: `final-categorized-checklist.png` and `checklist-comparison.png`.
3. P2: the native reference Picker expanded almost across the window and provided poor navigation for hundreds of targets.
   - Fix: replaced it with a fixed-width searchable popover that shows task context for every mini-task.
   - Post-fix evidence: `final-compact-reference-picker.png` and `reference-picker-comparison.png`.
4. P2: the first whole-window zoom implementation could compress and clip toolbar controls at 110%.
   - Fix: zoom now scales task content and the inspector while leaving native window chrome and the source sidebar stable.
   - Post-fix evidence: Command + and Command - were exercised at runtime with all toolbar controls still visible.
5. P1: the restored 1488 x 960 legacy window could exceed the comfortable display canvas and obscured the bottom resize edge.
   - Fix: adaptive default placement now targets 92% width and 90% height, caps at 1240 x 800, has a 760 x 500 minimum, and performs a one-time legacy-frame migration.
   - Post-fix evidence: `release-adaptive-window.jpeg`; accessibility resizing changed both dimensions to 1000 x 600.

## Primary interactions tested

- Command +, Command -, and Command 0 zoom behavior.
- Apple System, Paper Light, and Paper Dark selection paths; Apple System and Paper Dark were visually inspected.
- Kanban, table, and timeline switching.
- Timeline Today centering and horizontal calendar navigation.
- Timeline grouping by Status and Team; start-date ordering remains fixed.
- Table status grouping and deadline ordering.
- Kanban drag/drop/manual ordering code path plus deadline/checklist sort logic under automated tests.
- Categorized mini-task rendering and notes cleanup on migrated data.
- Compact reference picker opening, searching surface, and bounded dimensions.
- Add-board control exposure and board creation through domain/API/MCP tests.
- One-time legacy window migration, vertical and horizontal size mutability, and installed-app launch geometry.
- Light/dark cube icon assets, Readex Pro wordmark registration, and final Apple System/Paper Dark comparison.

## Residual P3 polish

- The reference timeline uses a denser edge-to-edge crop, while Ownward reserves space for its native toolbar, sidebar, fixed labels, and richer task metadata. This is an intentional product difference.
- Paper Dark follows the requested Ubuntu type system rather than the reference's Apple/system typography.

final result: passed

# Changelog

## 0.11.2 (release candidate; native Windows PowerShell 5.1 validation pending)

- **Fluent application renderer** (opt-in): `Export-PSIReport -Renderer Fluent|Auto|Classic`, or `$env:PSINSIGHTHTML_RENDERER`. Renders the existing report objects unchanged - no provider changes - as a navigation-rail application with data grids, detail pane, evidence pane, an "All findings" master/detail page, a search palette across pages, findings, metrics and table rows, Light/Dark/Auto themes and print of every page. Supports Text, KeyValue, KPI, Sparkline, EmptyState, Insight, Finding, Status, Alert, Recommendation, Table, Chart, Explorer, AssessmentOverview, Tree, Topology, RelationshipExplorer and the resource workspace. `Auto` falls back to Classic for unknown component types. See [docs/Fluent-Renderer.md](docs/Fluent-Renderer.md).
- Fluent reports are 2-3x smaller and up to 9x faster to generate than Classic for the same report (table cells are projected without per-cell helper calls).
- Module import: about 13 s down to about 2 s. Sources are loaded from a generated `PSInsightHTML.Bundle.ps1` (one file instead of ~95) when its fingerprint matches the sources; otherwise the sources load as before with a warning. Regenerate with `Build/Build-PSInsightHTML.ps1`.
- Version is read from the manifest (was hard-coded `0.10.0` in `New-PSIReport`).
- Added `Build/New-PSISampleReports.ps1` (regenerate every sample report into a labelled folder with timings) and `Build/Test-PSIFluentParity.ps1` (table data parity between report objects and the Fluent model).
- Added `docs/Component-Contract.md`, the as-implemented contract of every component.
- The Fluent Light palette now uses the muted canvas and off-white surfaces established in the earlier application styling.
- Added direct Fluent renderer tests; the full PowerShell 7/Pester suite passes 550 tests.
- Classic renderer output is unchanged. The module export default remains Classic; the sample build selects Fluent.

## 0.10.0

- Added sticky generic report section navigation with active-section tracking, accessible current-location state, dynamic anchor offsets, and composed-assessment navigation support.
- Refined KPI interaction feedback with a restrained lift, keyboard focus treatment, pointer-aware hover behavior, reduced-motion support, and static print output.
- Added severity-aware Finding recommendation treatments using the existing canonical status tokens and print-readable borders.
- Added a generic client-side Findings Explorer based on `Finding.AffectedObject`, including priority-based defaults, counts, status summaries, `Unspecified` and `All findings` options, independent section controls, accessible native selection, and complete print output.
- Preserved the existing public command surface, Finding schema, standalone HTML model, and no-JavaScript fallback.

## 0.9.1

- Made executable PowerShell source and embedded CSS/JavaScript runtime assets ASCII-safe for Windows PowerShell 5.1 decoding.
- Preserved rendered Unicode symbols through HTML entities, runtime character construction, and JavaScript/CSS escapes.
- Added source-compatibility regression tests and Windows PowerShell 5.1 release-validation guidance.

## 0.9.0

- Generic report, section, row, and component model with assessment composition and a derived report overview.
- Responsive Light, Dark, Auto, and print visual system with sticky assessment navigation.
- Searchable, sortable, filterable, paginated tables with CSV, XLSX, and print actions; declarative conditional formatting.
- Inline SVG bar, line, doughnut, and pie charts with supported chart-driven filtering.
- Structured findings, reusable evidence references, and a shared investigation dialog.
- Fictional Active Directory sample providers for User Inventory, DNS, Replication, Sites and Subnets, Groups, and Group Policy.
- Standalone HTML with embedded CSS, JavaScript, SVG icons, and no CDN dependency.

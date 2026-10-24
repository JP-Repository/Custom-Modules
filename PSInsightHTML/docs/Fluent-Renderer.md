# Fluent renderer

The Fluent renderer turns any PSInsightHTML report object into an offline, single-file application. Providers and scripts do not change: the same `New-PSIReport` / `Add-PSI*` objects are exported with a different renderer.

```powershell
Export-PSIReport -Report $Report -Path ./Reports/Example.html -Renderer Fluent

# or for every export in the session (including provider commands that export internally)
$env:PSINSIGHTHTML_RENDERER = 'Fluent'   # Classic (module default) | Fluent | Auto
New-PSIADGroupAssessment -UseSampleData -Path ./Reports/Groups.html -NoBrowser
```

`Auto` uses Fluent when every component in the report is supported, otherwise Classic. `Build/New-PSISampleReports.ps1` now selects Fluent by default for the visual sample run. The module export default remains Classic for existing scripts that depend on its HTML contract.

## What the user gets

- **Navigation rail.** Pages come from `Add-PSIView` views, from `NavigationGroups`, or from sections, grouped by composed assessment. Long navigations collapse to one expanded group. Each item shows its finding count and a marker for critical or warning findings. Pages within a group have Previous and Next buttons.
- **All findings.** A synthetic page with severity tiles, status, category and affected-object filters, and a master/detail list. Each finding's evidence appears inline as a grid.
- **Data grids.** Search, `Add-PSIFilter` controls (chips for Select, a dropdown for MultiSelect or long value lists), removable filter tags, sorting, paging and row/cell condition colours. Export goes through the shared `PSIExport` helper (CSV, Excel, Print), so file contents match the classic renderer. Long identifiers truncate with a tooltip; prose columns wrap.
- **Detail pane.** Clicking a row shows every column, with copy buttons and the findings whose evidence includes that row.
- **Evidence pane.** Finding and Insight evidence uses the same client-side operator set as the classic viewer. **Open in table** applies the evidence conditions to the source table as removable tags. Unlike the classic dialog, evidence ignores filters the user set elsewhere in the table, so a finding always shows the same rows.
- **Cross-links.** KPI `-Filter`, KPI `-Action` (`ScrollTo` / `FilterTable`) and chart `-FilterMetadata` open the target page and filter the table.
- **Search palette.** Ctrl+K or `/` searches pages, findings, metrics, tables and table rows.
- **Themes and print.** Light, Dark and Auto, stored in `localStorage['psi-report-theme']` as before. Print renders every page.

## Design rules

- Fluent 2 tokens in one stylesheet (`Assets/Fluent/psi-fluent.css`); the legacy stylesheets are not loaded.
- Status colours are reserved for status, always paired with an icon and a label. Chart series use a separate validated categorical palette. A category that is itself a status keeps its status colour.
- Icons come from curated Fluent System Icons SVGs first (`Assets/Icons/Fluent`, MIT, see `NOTICE`). Missing roles use the same Fluent glyph extracted from the Windows Segoe Fluent Icons font at export time. Everything is embedded, so reports render identically offline.
- Table cell text is the classic renderer's text (status canonicalisation, `[string]` formatting), so filters, evidence and exports keep their semantics. `Build/Test-PSIFluentParity.ps1` checks row and cell parity.

## Component coverage and release checks

The Fluent model and client renderer include `Explorer`, `AssessmentOverview`, `Tree`, `Topology`, `RelationshipExplorer`, Resource Explorer and Context Inspector. The previous unsupported list was stale. `Test-PSIFluentSupport` selects Fluent for the known component types; unknown component types still fall back to Classic with `Auto` and show a placeholder with explicit `Fluent`.

Run `Tests/PSInsightHTML.FluentRenderer.Tests.ps1` for direct shell, theme, projection, table/evidence and standalone-output checks. `Build/Test-PSIFluentParity.ps1` checks table row and non-null cell parity. A full sample run is `./Build/New-PSISampleReports.ps1 -Label ReleaseCandidate -Renderer Fluent`; inspect the generated `Reports/ReleaseCandidate/index.html` and each report in a browser. Native Windows PowerShell 5.1 and cross-browser interaction checks are still separate release gates.

## Files

| File | Role |
|---|---|
| `Private/ConvertTo-PSIFluentModel.ps1` | report object to JSON model (pages, sections, components, findings) |
| `Private/ConvertTo-PSIFluentHtml.ps1` | validation, template assembly, `Test-PSIFluentSupport` |
| `Private/Get-PSIFluentIconSet.ps1` | icon role resolution |
| `Assets/Fluent/psi-fluent.html`, `.css`, `.js` | shell, styles, application |

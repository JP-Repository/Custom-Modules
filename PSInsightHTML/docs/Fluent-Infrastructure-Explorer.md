# Fluent Infrastructure Explorer

The Fluent Infrastructure Explorer is an **opt-in** PSInsightHTML Application shell for compact infrastructure dashboards. It uses a narrow global navigation rail on desktop, a narrower rail on tablet, and an accessible navigation drawer on mobile. Existing Application views and the normal Report layout remain available without visual changes.

```powershell
$Report = New-PSIReport -Title 'Infrastructure Explorer' -Layout Application `
    -Navigation FluentExplorer -Density Compact -Theme Auto
$Report | Add-PSIView -Id overview -Title Overview -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Summary' | Add-PSIRow | Out-Null
```

`-Navigation` accepts `Sidebar` (existing default) or `FluentExplorer`. `-Density` accepts `Comfortable` (existing default) or `Compact`. These options require `-Layout Application`; existing `New-PSIReport` calls continue to work. FluentExplorer uses the existing `Add-PSIView` and `NavigationGroups` contracts, embedded Fluent System Icons, theme control, search, export, and print projection. The shell is generic and does not change data providers or assessment semantics.

The `Compact` density shortens the command area, KPI cards, tabs, table rows, and section spacing. FluentExplorer uses the full available workspace width and a centralized Light, Dark, and Auto palette. No network assets or runtime `fetch()` calls are required.

Run `Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1` to generate a small synthetic HTML example in the same directory. Pass `-Theme Light`, `-Theme Dark`, or `-Theme Auto` to choose its initial theme; the embedded theme control can switch modes after opening the file.

Resource Explorer, Context Inspector, evidence-contract correction, and lazy rendering are later milestones. This shell foundation does not implement them.

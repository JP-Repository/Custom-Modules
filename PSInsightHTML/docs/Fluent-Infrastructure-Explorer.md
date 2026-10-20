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

## Resource Explorer and Context Inspector

`Add-PSIResourceExplorer` adds an optional, provider-neutral navigation tree between the global rail and the workspace. It accepts nodes with `Id`, `Label`, `Type`, `Icon`, `ParentId`, `Status`, `Count`, `Metadata`, `Target`, `Selectable`, and `Expandable`. IDs are unique and stable; parents must exist and cycles are rejected. `Target` can name an existing application view. The tree provides search, expand/collapse, keyboard navigation, selected state, counts, text status, and embedded regular/filled Fluent icons. Tree markup carries identifiers and display labels, not full resource objects.

`Add-PSIInspector` adds an optional right-side panel after a Resource Explorer. Its `-Items` collection maps one detail record to each `ResourceId`. Each item can provide `Id`, `Title`, `Subtitle`, `Status`, ordered `Properties`, `Metadata` tags, and `Sections`. The Properties tab is automatic. Sections can represent Evidence, Findings, Recommendations, Related Resources, or other generic detail blocks. A block can contain `Title`, `Text`, `Status`, `ResourceId`, `TargetView`, and `ActionLabel`. These are presentation references, not new evidence semantics.

```powershell
$Report | Add-PSIResourceExplorer -Id inventory -Title Resources -SelectedId node1 -Nodes @(
    @{ Id='node1'; Label='Example server'; Type='Server'; Icon='ResourceServer'; Status='Healthy' }
) | Add-PSIInspector -Id details -Title 'Context Inspector' -Items @(
    @{ Id='detail1'; ResourceId='node1'; Title='Example server'; Subtitle='Fictional example';
       Status='Healthy'; Properties=[ordered]@{ Site='Example'; OS='Sample OS' };
       Sections=@(@{ Id='Evidence'; Title='Evidence'; Blocks=@(@{ Title='Sample reference'; Text='Fictional only' }) }) }
) | Out-Null
```

Selection updates the highlighted tree node, compact resource header, status, tags, and inspector content without reloading the page. Inspector records are embedded once in a small JSON lookup keyed by resource ID. The inspector creates tabs and detail blocks only for the selected resource. Untrusted text is placed into DOM nodes with `textContent`. The current shell has one Resource Explorer and one Context Inspector per report.

Desktop uses the global rail, 270 px explorer, remaining workspace, and 340 px inspector. The explorer can be hidden; the inspector can be hidden independently. At tablet widths, the inspector moves below the workspace and the explorer becomes a drawer. At mobile widths, the explorer is a drawer and the inspector stacks below the workspace. Existing Report layout, previous Application shells, and in-view `Add-PSIExplorer` remain unchanged.

The synthetic benchmark includes a fictional domain and six fictional domain controllers. It exercises Healthy, Warning, and Critical selection states without collecting Active Directory data.

Compact component overhaul, Sparkline API, evidence-contract correction, lazy rendering, and AD Health migration remain future milestones.

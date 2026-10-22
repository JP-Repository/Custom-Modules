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

## Compact component system (0.11C)

The opt-in `Application` + `FluentExplorer` + `Compact` combination now uses 88 px KPI cards, restrained status color, 34 px table rows, contained table scrolling, 12-14 px panel padding, and a 38 px workspace tab strip. Standard Report layouts retain their existing table and KPI presentation. The shared Light/Dark/Auto theme tokens drive all component colors; the benchmark remains standalone.

The existing Resource Explorer header now displays the selected resource icon, title, subtitle, status badge, metadata tags, and optional breadcrumb/action data from its corresponding `Add-PSIInspector -Items` record. An item may include `Breadcrumb = @('Infrastructure','Site')` and `Actions = @(@{ Label='View evidence'; TargetView='evidence' })`. Actions may instead name a known `ResourceId`. The header continues to update from the single selected-resource lookup; it does not duplicate the resource model.

`Add-PSIView` accepts optional `-TabCount` (nonnegative) and `-Disabled`. Fluent compact reports render the registered views as lightweight tabs with a selected underline. The tabs call the existing application view activation path, so sidebar navigation, search results, filter actions, and tab clicks share one active view. Arrow keys and Home/End move between enabled tabs. Existing reports without Fluent compact navigation do not gain another tab bar.

`Add-PSISparkline` accepts 2-120 finite numeric `-Values`, optional `-Label`, `-CurrentValue`, canonical `-Status`, `-Minimum`, `-Maximum`, and `-Span`. It emits one small inline SVG with encoded labels and no chart library. Place two to four sparklines in a normal row for a compact metric panel:

```powershell
$Report | Add-PSISection -Title 'Key Metrics' | Add-PSIRow |
    Add-PSISparkline -Label CPU -CurrentValue '12%' -Values @(18,17,14,12) -Status Healthy -Span 3 |
    Add-PSISparkline -Label Memory -CurrentValue '58%' -Values @(50,54,57,58) -Status Healthy -Span 3 | Out-Null
```

`Add-PSIEmptyState` accepts `-Title`, `-Explanation`, optional `-Icon`, and optional `-ActionLabel` with `-TargetView`. It uses encoded text and an embedded icon. Compact tables also show an explanatory no-results state. Status cells in compact Fluent tables recognize Healthy, Ready, Warning, Review, Critical, Blocked, Info, Unknown, NotTested, NotSupported, and NA as presentation badges with an icon and label. This visual mapping does not alter the existing canonical status or assessment/scoring rules. Standard Report tables retain their prior status rendering.

The synthetic benchmark includes six KPIs, five workspace tabs, four sparkline metrics, service evidence, controller checks, an interactive topology, and two sample follow-up actions alongside the Resource Explorer and Context Inspector. It contains no collected infrastructure facts.

## Topology tab

The benchmark's Topology view uses the existing `Add-PSITopology` component. Providers create a generic `New-PSIApplicationModel` with `New-PSIResource` records and explicitly declared `New-PSIRelationship` records, then attach it with `Set-PSIApplicationModel`. `Add-PSITopology -Nodes` accepts lightweight node references (`NodeId`, `ResourceId`, optional `ParentId`, label, and icon); full resource records stay in the application model. A view needs a section and row before the component is added.

The fictional example has one forest, one domain, three sites, and six controllers. `Containment` relationships describe the forest/domain/site/controller hierarchy and appear as dashed neutral lines. `Replication` relationships are separately declared fictional links and use their own status-colored solid lines. Site membership never creates a replication link. `Unknown` means no health conclusion. External `EvidenceOnly` endpoints, when supplied, provide context and are not assessed resources.

Selecting a controller in the graph emits the existing relationship selection event with its stable `ResourceId`. The Resource Workspace uses that ID to highlight the tree node and update the header and Inspector without leaving Topology. The graph also shows a selected-node detail panel and a relationship list. The existing controls support zoom in/out, fit, reset, keyboard node/edge selection, search, filters, and native scrolling to pan. The diagram is also visible on mobile in FluentExplorer; the relationship list remains available below it. Other Application layouts retain their previous mobile list fallback.

The graph uses a fixed-size SVG layout inside a scrollable viewport. Large or dense provider graphs can require horizontal and vertical panning, and `MaxNodes` limits what is drawn until filters narrow the scope. It does not infer connectivity, run a force simulation, or fetch data at runtime. Evidence-contract redesign, lazy rendering, and assessment migrations remain outside this milestone.

# Relationship, tree and topology views

PSInsightHTML application reports can present generic resources and relationships as a hierarchy, an SVG topology, or a relationship list with details. The reporting core renders records; providers choose what the records mean and which fields are safe to display.

## Contracts

`New-PSIResource` supplies the assessed resource ID, name, type, status, description, and optional properties. `New-PSIRelationship` keeps its existing `SourceResourceId`, `TargetResourceId`, and `Type` fields. Optional presentation fields include `Label`, `Direction` (`Directed` or `Bidirectional`), `Status`, `Severity`, `Category`, `Description`, `EvidenceIds`, `FindingIds`, `DisplayWeight`, `IsExternal`, and `EvidenceOnly`. Existing relationships continue to work.

Tree nodes may be supplied as generic objects or hashtables with `NodeId`, `ParentId`, `ResourceId`, `Label`, `NodeType`, `Status`, `Icon`, and `SortOrder`. A node normally links to an existing resource. Omitting `-Nodes` derives one root node per resource. Duplicate IDs are omitted; missing parents and hierarchy cycles are reported in the view and repaired into roots. Multiple roots are supported.

An endpoint outside the assessed resource scope must be explicitly marked `IsExternal = $true` and `EvidenceOnly = $true`. It can be selected and described, but it does not become a resource or affect assessment scope. A provider may add such a node explicitly or allow the presentation helper to synthesize it from an evidence-only relationship. The live collector and scoring rules do not use this display metadata.

## Use in an application report

Create an application report, set its model, add a view and row, then add one of the three components. For example:

```powershell
$Report = New-PSIReport -Title 'Fictional service map' -Layout Application
$Report | Set-PSIApplicationModel -Model $Model | Out-Null
$Report |
    Add-PSIView -Id topology -Title 'Topology' |
    Add-PSISection -Title 'Connections' |
    Add-PSIRow |
    Add-PSITopology -Id service-topology -Title 'Service topology' -Nodes $Nodes -MaxNodes 100 | Out-Null
```

`Add-PSITree` uses the same `-Nodes`, `-Relationships`, `-DetailProperties`, and `-LinkViews` options. `Add-PSIRelationshipExplorer` presents the same normalized model as a relationship list and detail panel. The default `-LinkViews` names are `resources`, `findings`, and `evidence`; change them when the report uses other view IDs. Only existing target explorers become navigation buttons. A provider should pass a reviewed `-DetailProperties` allowlist; sensitive key names are also excluded by the renderer.

The tree uses `role="tree"` and `role="treeitem"`, selected and expanded state, and Up, Down, Left, Right, Home, End, Enter, and Space keys. The topology has keyboard operable SVG nodes, edges, and zoom controls, plus a text relationship list. Search and filters cover generic node type, status, relationship type, and category. Selecting nodes or edges shows safe details, related records, and available cross-view actions. Global Search and the Command Palette discover the views from the existing view registry; the resource index remains the source of resource search results.

The SVG uses a deterministic layered layout and is capped at 100 nodes by default (`-MaxNodes`, maximum 500). When the visible set exceeds the cap, the graph displays a message and the relationship list remains available. On narrow screens the relationship list and detail panel replace the graph. The interactive canvas is excluded from the dedicated print projection; existing print summaries remain in place. All scripts, styles, icons, and data are embedded in the standalone HTML.

The fictional provider-neutral example is `Examples/New-AdaptiveDemoReport.ps1`. The fictional DC example is `Examples/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1 -TargetOS 2025 -UseSampleData -NoBrowser`. Both exercise the same public component APIs.

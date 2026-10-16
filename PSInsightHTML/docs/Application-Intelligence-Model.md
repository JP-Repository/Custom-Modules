# Application intelligence model (Milestone 11.4)

The model is opt-in for `New-PSIReport -Layout Application`. It is independent of the existing `New-PSIFinding` report card and evidence table APIs. Existing provider reports do not need to migrate.

```powershell
$resource = New-PSIResource -Definition @{
    Id = 'resource-one'; Name = 'Fictional service'; Type = 'Service'; Status = 'Warning'
    Properties = @{ Region = 'Sample West' }
}
$evidence = New-PSIEvidenceRecord -Definition @{
    Id = 'evidence-one'; Title = 'Sample observation'; Type = 'Observation'
    Source = 'Fictional monitor'; CollectedAt = [datetime] '2026-10-16'
    Data = @{ LatencyMs = 240 }; ResourceIds = @('resource-one')
    FindingIds = @('finding-one')
}
$finding = New-PSIApplicationFinding -Definition @{
    Id = 'finding-one'; Title = 'Response review'; Summary = 'Sample observation'
    Severity = 'Warning'; Status = 'Open'; Category = 'Performance'
    AffectedResourceIds = @('resource-one'); EvidenceIds = @('evidence-one')
    Recommendation = @{ Action = 'Review capacity'; ExpectedState = 'Response within target' }
    Validation = @{ Method = 'Compare the next snapshot'; ExpectedResult = 'Within target' }
}
$resource.FindingIds = @('finding-one')
$resource.EvidenceIds = @('evidence-one')
$model = New-PSIApplicationModel -Findings @($finding) -Resources @($resource) -Evidence @($evidence)
$report = New-PSIReport -Title 'Sample' -Layout Application
$report | Set-PSIApplicationModel -Model $model | Out-Null
```

`New-PSIApplicationModel` validates IDs and every declared cross-reference, then exposes `Summary` counts by finding severity/category/status, resource status, resources with critical findings, and evidence count. `Set-PSIApplicationModel` attaches it to an Application report; export validates references again. No HTML command execution or automatic remediation is provided. `AutomationHint` and validation `Command` are descriptive data.

For interactive views, use `Add-PSIExplorer -EntityType Finding`, `Resource`, or `Evidence` with the corresponding model collection. The renderer encodes supplied text and data, shows related records, and emits generic cross-view actions. The application script selects the target view and record without reloading. `-LinkViews @{ Finding='observations'; Resource='assets'; Evidence='proof' }` maps links when an application uses other view IDs; export rejects missing target views or target views without the matching explorer. Evidence remains typed in the model; the existing evidence table/viewer remains available separately.

The schema is intentionally provider-neutral. A provider decides what a resource type, finding category, evidence source, relationship type, remediation action, and validation method mean. Resource names and sample measurements in the adaptive demo are fictional.

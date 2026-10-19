function New-PSIContractObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Finding','Resource','Evidence','Relationship')][string] $Kind,
        [Parameter(Mandatory = $true)][hashtable] $Definition
    )

    $Fields = switch ($Kind) {
        Finding { @('Id','Title','Summary','Severity','Status','Category','Subcategory','ReadinessImpact','Frameworks','AffectedResourceIds','EvidenceIds','Recommendation','Validation','Owner','RemediationState','Relationships','Tags','Metadata') }
        Resource { @('Id','Name','Type','Status','Description','Properties','FindingIds','EvidenceIds','RelationshipIds','Tags','Metadata') }
        Evidence { @('Id','Title','Type','Source','CollectedAt','Summary','Data','FindingIds','ResourceIds','Tags','Metadata') }
        Relationship { @('Id','SourceResourceId','TargetResourceId','Type','Direction','Status','Impact','FindingIds','EvidenceIds','Label','Severity','Category','Description','IsExternal','EvidenceOnly','DisplayWeight','Metadata') }
    }
    $Required = switch ($Kind) {
        Finding { @('Id','Title','Severity','Status') }
        Resource { @('Id','Name','Type','Status') }
        Evidence { @('Id','Title','Type','Source') }
        Relationship { @('Id','SourceResourceId','TargetResourceId','Type') }
    }
    foreach ($Key in $Definition.Keys) {
        if ($Key -notin $Fields) { throw "$Kind contains unknown field '$Key'." }
    }
    foreach ($Key in $Required) {
        if ([string]::IsNullOrWhiteSpace([string] $Definition[$Key])) { throw "$Kind requires a non-empty $Key." }
    }
    if ([string] $Definition.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind Id must begin with a letter and contain only letters, digits, underscores or hyphens." }
    if ($Kind -eq 'Finding') {
        if ($Definition.Severity -notin @('Critical','Warning','Info','Healthy','Unknown')) { throw "Finding '$($Definition.Id)' has invalid Severity '$($Definition.Severity)'." }
        if ($Definition.Status -notin @('Open','Acknowledged','Resolved','AcceptedRisk','NotApplicable','NotTested')) { throw "Finding '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
        foreach ($NestedName in @('Recommendation','Validation')) {
            $Nested = $Definition[$NestedName]
            if ($null -ne $Nested -and $Nested -isnot [System.Collections.IDictionary]) { throw "Finding '$($Definition.Id)' $NestedName must be a dictionary." }
            $Allowed = if ($NestedName -eq 'Recommendation') { @('Summary','Rationale','Priority','Action','ExpectedState','ChangeImpact','RequiresRestart','RequiresReboot','Validation','References','AutomationHint') } else { @('Method','Description','ExpectedResult','Command','EvidenceRequired','Status') }
            if ($null -ne $Nested) { foreach ($Field in $Nested.Keys) { if ($Field -notin $Allowed) { throw "Finding '$($Definition.Id)' $NestedName has unknown field '$Field'." } } }
        }
    }
    if ($Kind -eq 'Resource' -and -not (Resolve-PSIStatus -Status ([string] $Definition.Status) -AllowInvalid)) { throw "Resource '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
    if ($Kind -eq 'Relationship') {
        if ([string]::IsNullOrWhiteSpace([string] $Definition.Direction)) { $Definition.Direction = 'Directed' }
        if ($Definition.Direction -notin @('Directed','Bidirectional')) { throw "Relationship '$($Definition.Id)' has invalid Direction." }
        if ($Definition.Status -and -not (Resolve-PSIStatus -Status ([string] $Definition.Status) -AllowInvalid)) { throw "Relationship '$($Definition.Id)' has invalid Status." }
        if ($Definition.Severity -and -not (Resolve-PSIStatus -Status ([string] $Definition.Severity) -AllowInvalid)) { throw "Relationship '$($Definition.Id)' has invalid Severity." }
        if ($null -ne $Definition.DisplayWeight -and ($Definition.DisplayWeight -isnot [ValueType] -or [double] $Definition.DisplayWeight -lt 0)) { throw "Relationship '$($Definition.Id)' has invalid DisplayWeight." }
        if ($Definition.IsExternal -and -not $Definition.EvidenceOnly) { throw "Relationship '$($Definition.Id)' external endpoints must be evidence-only." }
    }
    if ($Kind -eq 'Evidence' -and $null -ne $Definition.CollectedAt -and $Definition.CollectedAt -isnot [datetime]) { throw "Evidence '$($Definition.Id)' CollectedAt must be a DateTime." }
    $Lists = @('Frameworks','AffectedResourceIds','EvidenceIds','Relationships','Tags','FindingIds','RelationshipIds','ResourceIds')
    $Maps = @('Metadata','Properties')
    $Result = [ordered]@{}
    foreach ($Field in $Fields) {
        if ($Definition.ContainsKey($Field)) { $Result[$Field] = $Definition[$Field] }
        elseif ($Field -in $Lists) { $Result[$Field] = @() }
        elseif ($Field -in $Maps) { $Result[$Field] = @{} }
        else { $Result[$Field] = $null }
        if ($Field -in $Lists) { $Result[$Field] = @($Result[$Field] | Where-Object { $null -ne $_ }) }
    }
    [pscustomobject] $Result
}

function New-PSIAssessmentContractObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Category','Check','Exception')][string] $Kind,
        [Parameter(Mandatory = $true)][hashtable] $Definition
    )
    $Fields = switch ($Kind) {
        Category { @('Id','Name','Description','Icon','Weight','Status','Score','CheckIds','FindingIds','ResourceIds','Metadata') }
        Check { @('Id','Name','Description','CategoryId','Status','Severity','Weight','IsBlocking','ObservedState','ExpectedState','FindingIds','ResourceIds','EvidenceIds','Recommendation','Validation','Frameworks','Tags','Metadata') }
        Exception { @('Id','Title','Description','CheckId','FindingId','ResourceIds','Reason','Owner','ApprovedBy','ApprovedAt','ExpiresAt','Status','Metadata') }
    }
    $Required = switch ($Kind) {
        Category { @('Id','Name') }
        Check { @('Id','Name','CategoryId','Status') }
        Exception { @('Id','Title','Reason','Status') }
    }
    foreach ($Key in $Definition.Keys) { if ($Key -notin $Fields) { throw "$Kind contains unknown field '$Key'." } }
    foreach ($Key in $Required) { if ([string]::IsNullOrWhiteSpace([string] $Definition[$Key])) { throw "$Kind requires a non-empty $Key." } }
    if ([string] $Definition.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind Id is invalid." }
    if ($Kind -eq 'Category' -or $Kind -eq 'Check') {
        $Weight = if ($Definition.ContainsKey('Weight')) { [double] $Definition.Weight } else { 1.0 }
        if ($Weight -le 0 -or [double]::IsNaN($Weight) -or [double]::IsInfinity($Weight)) { throw "$Kind '$($Definition.Id)' Weight must be a positive finite number." }
        $Definition.Weight = $Weight
    }
    if ($Kind -eq 'Category') {
        if ($Definition.ContainsKey('Score') -or $Definition.ContainsKey('Status')) { throw 'Category Score and Status are calculated by the posture engine.' }
        $Icon = [string] (Get-PSIProperty -InputObject $Definition -Name Icon -DefaultValue 'Document')
        [void] (Get-PSIIcon -Name $Icon -Strict)
        $Definition.Icon = $Icon
    }
    if ($Kind -eq 'Check') {
        if ($Definition.Status -notin @('Ready','Review','Blocked','NotTested','NotApplicable','Unknown')) { throw "Check '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
        if ($Definition.Severity -and $Definition.Severity -notin @('Critical','Warning','Info','Healthy','Unknown')) { throw "Check '$($Definition.Id)' has invalid Severity." }
        foreach ($NestedName in @('Recommendation','Validation')) {
            $Nested = $Definition[$NestedName]
            if ($null -ne $Nested -and $Nested -isnot [System.Collections.IDictionary]) { throw "Check '$($Definition.Id)' $NestedName must be a dictionary." }
            $Allowed = if ($NestedName -eq 'Recommendation') { @('Summary','Rationale','Priority','Action','ExpectedState','ChangeImpact','RequiresRestart','RequiresReboot','Validation','References','AutomationHint') } else { @('Method','Description','ExpectedResult','Command','EvidenceRequired','Status') }
            if ($null -ne $Nested) { foreach ($Field in $Nested.Keys) { if ($Field -notin $Allowed) { throw "Check '$($Definition.Id)' $NestedName has unknown field '$Field'." } } }
        }
    }
    if ($Kind -eq 'Exception') {
        if ($Definition.Status -notin @('Approved','Pending','Expired','Revoked')) { throw "Exception '$($Definition.Id)' has invalid Status." }
        foreach ($DateField in @('ApprovedAt','ExpiresAt')) {
            if ($null -ne $Definition[$DateField] -and $Definition[$DateField] -isnot [datetime]) { throw "Exception '$($Definition.Id)' $DateField must be a DateTime." }
        }
        if ($Definition.Status -eq 'Approved' -and ([string]::IsNullOrWhiteSpace([string] $Definition.ApprovedBy) -or $null -eq $Definition.ApprovedAt)) { throw "Approved exception '$($Definition.Id)' requires ApprovedBy and ApprovedAt." }
    }
    $Lists = @('CheckIds','FindingIds','ResourceIds','EvidenceIds','Frameworks','Tags')
    $Result = [ordered]@{}
    foreach ($Field in $Fields) {
        if ($Definition.ContainsKey($Field)) { $Result[$Field] = $Definition[$Field] }
        elseif ($Field -in $Lists) { $Result[$Field] = @() }
        elseif ($Field -eq 'Metadata') { $Result[$Field] = @{} }
        elseif ($Field -eq 'IsBlocking') { $Result[$Field] = $false }
        else { $Result[$Field] = $null }
        if ($Field -in $Lists) { $Result[$Field] = @($Result[$Field] | Where-Object { $null -ne $_ }) }
    }
    [pscustomobject] $Result
}

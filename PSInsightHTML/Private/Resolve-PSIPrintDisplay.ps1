function Resolve-PSIPrintDisplay {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Configuration,
        [AllowNull()][object] $LegacyConfiguration
    )

    $Defaults = @{
        Resources = @(
            @{ Property='Name'; Label='Name'; Format='Text' },
            @{ Property='Type'; Label='Type'; Format='Text' },
            @{ Property='Status'; Label='Status'; Format='Status' }
        )
        Evidence = @(
            @{ Property='Id'; Label='Evidence ID'; Format='Text' },
            @{ Property='Type'; Label='Type'; Format='Text' },
            @{ Property='Source'; Label='Source'; Format='Text' },
            @{ Property='CollectionState'; Label='Collection state'; Format='Text' },
            @{ Property='Scope'; Label='Scope'; Format='Text' },
            @{ Property='CollectedAt'; Label='Collected'; Format='DateTime' },
            @{ Property='Summary'; Label='Summary'; Format='Text' },
            @{ Property='FindingIds'; Label='Findings'; Format='List' },
            @{ Property='CheckIds'; Label='Checks'; Format='List' }
        )
        Checks = @(
            @{ Property='Id'; Label='Check ID'; Format='Text' },
            @{ Property='Name'; Label='Check'; Format='Text' },
            @{ Property='Status'; Label='Status'; Format='Status' },
            @{ Property='Weight'; Label='Weight'; Format='Number' },
            @{ Property='Observation'; Label='Observation'; Format='Text' }
        )
        Findings = @(
            @{ Property='Summary'; Label='Observed'; Format='Text' },
            @{ Property='ReadinessImpact'; Label='Expected'; Format='Text' },
            @{ Property='AffectedResourceIds'; Label='Affected resources'; Format='List' },
            @{ Property='Recommendation'; Label='Recommendation'; Format='Text' },
            @{ Property='Validation'; Label='Validation'; Format='Text' },
            @{ Property='EvidenceIds'; Label='Evidence IDs'; Format='List' }
        )
    }
    $Allowed = @{
        Resources = @('Id','Name','Type','Status','Description')
        Evidence = @('Id','Title','Type','Source','CollectionState','Scope','CollectedAt','Summary','FindingIds','ResourceIds','CheckIds')
        Checks = @('Id','Name','Status','Weight','Observation','ObservedState','ExpectedState','Description','Severity')
        Findings = @('Summary','ReadinessImpact','AffectedResourceIds','Recommendation','Validation','EvidenceIds','Owner','RemediationState','Category')
    }
    $Result = @{}
    foreach ($Kind in @('Resources','Evidence','Checks','Findings')) {
        $Section = Get-PSIProperty -InputObject $Configuration -Name $Kind -DefaultValue $null
        $PropertyName = if ($Kind -in @('Resources','Checks')) { 'Columns' } else { 'Fields' }
        $Requested = Get-PSIProperty -InputObject $Section -Name $PropertyName -DefaultValue $null
        if ($null -eq $Requested -and $Kind -eq 'Resources') {
            $Legacy = Get-PSIProperty -InputObject $LegacyConfiguration -Name 'ResourceColumns' -DefaultValue $null
            if ($null -ne $Legacy) { $Requested = @($Legacy | ForEach-Object { @{ Property=[string] $_ } }) }
        }
        if ($null -eq $Requested) { $Requested = $Defaults[$Kind] }
        $Fields = [System.Collections.Generic.List[object]]::new()
        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Index = 0
        foreach ($Spec in @($Requested)) {
            $Index++
            $Property = if ($Spec -is [string]) { [string] $Spec } else { [string] (Get-PSIProperty -InputObject $Spec -Name 'Property' -DefaultValue '') }
            if ($Property -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$' -or $Property -match '(?i)password|secret|token|credential|private.?key|auth|keytab|bearer|^Data$|^Metadata$|^Properties$') { continue }
            if ($Kind -ne 'Resources' -and $Property -notin $Allowed[$Kind]) { continue }
            if ($Kind -eq 'Resources' -and $Property -notin $Allowed.Resources -and $Property -in @('FindingIds','EvidenceIds','RelationshipIds','Tags')) { continue }
            if (-not $Seen.Add($Property)) { continue }
            $Visible = Get-PSIProperty -InputObject $Spec -Name 'Visible' -DefaultValue $true
            if ($Visible -isnot [bool] -or -not $Visible) { continue }
            $Format = [string] (Get-PSIProperty -InputObject $Spec -Name 'Format' -DefaultValue $(if ($Property -eq 'Status') { 'Status' } else { 'Text' }))
            if ($Format -notin @('Text','Boolean','DateTime','Number','Percent','Status','List')) { continue }
            $Order = Get-PSIProperty -InputObject $Spec -Name 'Order' -DefaultValue $Index
            if ($Order -isnot [int] -or $Order -lt 0 -or $Order -gt 1000) { $Order = $Index }
            $Label = [string] (Get-PSIProperty -InputObject $Spec -Name 'Label' -DefaultValue $Property)
            if ([string]::IsNullOrWhiteSpace($Label) -or $Label.Length -gt 80) { $Label = $Property }
            $Fields.Add([pscustomobject]@{ Property=$Property; Label=$Label; Format=$Format; Visible=$true; Order=$Order; Index=$Index })
        }
        if ($Fields.Count -eq 0) {
            $Index = 0
            foreach ($Spec in $Defaults[$Kind]) {
                $Index++
                $Fields.Add([pscustomobject]@{ Property=$Spec.Property; Label=$Spec.Label; Format=$Spec.Format; Visible=$true; Order=$Index; Index=$Index })
            }
        }
        $Result[$Kind] = @($Fields | Sort-Object Order,Index | Select-Object -First $(if ($Kind -in @('Resources','Checks')) { 6 } else { 12 }))
    }
    $Identity = Get-PSIProperty -InputObject $Configuration -Name 'ReportIdentity' -DefaultValue $null
    $Kicker = Get-PSIProperty -InputObject $Identity -Name 'Kicker' -DefaultValue $null
    $Result.ReportIdentity = if ($Kicker -is [string] -and $Kicker.Length -le 100 -and -not [string]::IsNullOrWhiteSpace($Kicker)) { $Kicker } else { 'PSInsightHTML / Assessment document' }
    [pscustomobject] $Result
}

function Get-PSIPrintFieldValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Resources','Evidence','Checks','Findings')][string] $Kind,
          [Parameter(Mandatory)][object] $Record,
          [Parameter(Mandatory)][string] $Property,
          [AllowNull()][object] $CheckIds)

    if ($Kind -eq 'Resources') {
        if ($Property -in @('Id','Name','Type','Status','Description')) { return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null }
        return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Properties' -DefaultValue $null) -Name $Property -DefaultValue $null
    }
    if ($Kind -eq 'Checks') {
        if ($Property -eq 'Observation') {
            $Observed = Get-PSIProperty -InputObject $Record -Name 'ObservedState' -DefaultValue ''
            $Expected = Get-PSIProperty -InputObject $Record -Name 'ExpectedState' -DefaultValue ''
            return "Observed: $Observed; Expected: $Expected"
        }
        return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null
    }
    if ($Kind -eq 'Findings') {
        if ($Property -eq 'Recommendation') { return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Recommendation' -DefaultValue $null) -Name 'Action' -DefaultValue $null }
        if ($Property -eq 'Validation') { return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Validation' -DefaultValue $null) -Name 'Method' -DefaultValue $null }
        return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null
    }
    switch ($Property) {
        'CheckIds' { return $CheckIds }
        'Scope' {
            $Scope = Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Metadata' -DefaultValue $null) -Name 'Scope' -DefaultValue $null
            if ($null -ne $Scope) { return $Scope }
            return @(Get-PSIProperty -InputObject $Record -Name 'ResourceIds' -DefaultValue @())
        }
        'CollectionState' {
            $Metadata = Get-PSIProperty -InputObject $Record -Name 'Metadata' -DefaultValue $null
            $State = Get-PSIProperty -InputObject $Metadata -Name 'CollectionState' -DefaultValue $null
            if ($State -in @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')) { return $State }
            $Applicability = Get-PSIProperty -InputObject $Metadata -Name 'CollectionStateApplicability' -DefaultValue $null
            if ($Applicability -eq 'NotApplicable') { return 'Not applicable' }
            return 'Not supplied'
        }
        default { return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null }
    }
}

function Format-PSIPrintField {
    [CmdletBinding()]
    param([AllowNull()][object] $Value, [Parameter(Mandatory)][string] $Format)

    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Collections.IDictionary]) { return '' }
    if ($Value -is [array] -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])) {
        $Items = @($Value | Where-Object { $null -ne $_ -and ($_ -is [string] -or $_ -is [ValueType]) -and -not [string]::IsNullOrWhiteSpace([string] $_) })
        if ($Items.Count -eq 0) { return '' }
        $Value = $Items -join ', '
    }
    if ($Value -isnot [string] -and $Value -isnot [ValueType]) { return '' }
    if ([string]::IsNullOrWhiteSpace([string] $Value)) { return '' }
    switch ($Format) {
        Boolean { if ($Value -is [bool]) { return $(if ($Value) { 'Yes' } else { 'No' }) } }
        DateTime { if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm zzz') } }
        Number { if ($Value -is [ValueType] -and $Value -isnot [bool]) { return [string] $Value } }
        Percent { if ($Value -is [ValueType] -and $Value -isnot [bool]) { return ([string] $Value) + '%' } }
    }
    return [string] $Value
}

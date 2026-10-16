function Assert-PSIApplicationAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter()][AllowNull()][pscustomobject] $Model = $null
    )
    foreach ($Field in @('Id','Name','AssessmentType','Target','Profile')) {
        if ([string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Assessment -Name $Field))) { throw "Assessment requires a non-empty $Field." }
    }
    if ([string] $Assessment.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'Assessment Id is invalid.' }
    if ($Assessment.GeneratedAt -isnot [datetime]) { throw 'Assessment GeneratedAt must be a DateTime.' }
    if ([double] $Assessment.Thresholds.Review -lt 0 -or [double] $Assessment.Thresholds.Ready -gt 100 -or
        [double] $Assessment.Thresholds.Review -gt [double] $Assessment.Thresholds.Ready) { throw 'Assessment score thresholds are invalid.' }
    $Ids = @{}
    foreach ($Kind in @('Categories','Checks','Exceptions')) {
        $Ids[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in @($Assessment.$Kind)) {
            if ($null -eq $Record) { throw "$Kind cannot contain a null record." }
            $Definition = @{}
            foreach ($Property in $Record.PSObject.Properties) { $Definition[$Property.Name] = $Property.Value }
            if ($Kind -eq 'Categories') { $Definition.Remove('Score'); $Definition.Remove('Status') }
            $ContractKind = switch ($Kind) { Categories { 'Category' } Checks { 'Check' } Exceptions { 'Exception' } }
            [void] (New-PSIAssessmentContractObject -Kind $ContractKind -Definition $Definition)
            if (-not $Ids[$Kind].Add([string] $Record.Id)) { throw "$Kind contains duplicate Id '$($Record.Id)'." }
        }
    }
    if ($Assessment.Categories.Count -eq 0 -or $Assessment.Checks.Count -eq 0) { throw 'Assessment requires at least one category and one check.' }
    $CategoryMembership = @{}
    foreach ($Category in $Assessment.Categories) {
        foreach ($CheckId in @($Category.CheckIds)) {
            if (-not $Ids.Checks.Contains([string] $CheckId)) { throw "Category '$($Category.Id)' references missing Check '$CheckId'." }
            if ($CategoryMembership.ContainsKey([string] $CheckId)) { throw "Check '$CheckId' is assigned to multiple categories." }
            $CategoryMembership[[string] $CheckId] = [string] $Category.Id
        }
    }
    foreach ($Check in $Assessment.Checks) {
        if (-not $Ids.Categories.Contains([string] $Check.CategoryId)) { throw "Check '$($Check.Id)' references missing Category '$($Check.CategoryId)'." }
        if (-not $CategoryMembership.ContainsKey([string] $Check.Id) -or $CategoryMembership[[string] $Check.Id] -ine [string] $Check.CategoryId) {
            throw "Check '$($Check.Id)' and Category '$($Check.CategoryId)' have inconsistent CheckIds."
        }
    }
    foreach ($Exception in $Assessment.Exceptions) {
        if ($Exception.CheckId -and -not $Ids.Checks.Contains([string] $Exception.CheckId)) { throw "Exception '$($Exception.Id)' references missing Check '$($Exception.CheckId)'." }
        if ($Exception.ApprovedAt -and $Exception.ExpiresAt -and $Exception.ExpiresAt -le $Exception.ApprovedAt) { throw "Exception '$($Exception.Id)' ExpiresAt must follow ApprovedAt." }
    }
    if ($null -ne $Model) {
        [void] (Assert-PSIApplicationModel -Model $Model)
        $ModelIds = @{}
        foreach ($Kind in @('Findings','Resources','Evidence')) {
            $ModelIds[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Record in @($Model.$Kind)) { [void] $ModelIds[$Kind].Add([string] $Record.Id) }
        }
        $References = @(
            @{ Records=@($Assessment); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment); Field='EvidenceIds'; Target='Evidence' },
            @{ Records=@($Assessment.Categories); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment.Categories); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment.Checks); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment.Checks); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment.Checks); Field='EvidenceIds'; Target='Evidence' },
            @{ Records=@($Assessment.Exceptions); Field='ResourceIds'; Target='Resources' }
        )
        foreach ($Reference in $References) {
            foreach ($Record in $Reference.Records) {
                $Values = Get-PSIProperty -InputObject $Record -Name $Reference.Field -DefaultValue @()
                foreach ($Id in @($Values)) {
                    if ([string]::IsNullOrWhiteSpace([string] $Id) -or -not $ModelIds[$Reference.Target].Contains([string] $Id)) {
                        throw "'$($Record.Id)' has broken $($Reference.Field) reference '$Id' to $($Reference.Target)."
                    }
                }
            }
        }
        foreach ($Exception in $Assessment.Exceptions) {
            if ($Exception.FindingId -and -not $ModelIds.Findings.Contains([string] $Exception.FindingId)) { throw "Exception '$($Exception.Id)' references missing Finding '$($Exception.FindingId)'." }
        }
        foreach ($Field in @('FindingIds','ResourceIds','EvidenceIds')) {
            $AssessmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Id in @($Assessment.$Field)) { [void] $AssessmentIds.Add([string] $Id) }
            foreach ($Check in $Assessment.Checks) {
                foreach ($Id in @($Check.$Field)) {
                    if (-not $AssessmentIds.Contains([string] $Id)) { throw "Check '$($Check.Id)' links '$Id' outside Assessment.$Field." }
                }
            }
        }
    }
    $true
}

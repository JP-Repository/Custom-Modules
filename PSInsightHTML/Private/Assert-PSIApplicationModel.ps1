function Assert-PSIApplicationModel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Model)

    $Kinds = @('Findings','Resources','Evidence','Relationships')
    $Ids = @{}
    foreach ($Kind in $Kinds) {
        $Ids[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in @((Get-PSIProperty -InputObject $Model -Name $Kind -DefaultValue @()))) {
            if ($null -eq $Record) { throw "$Kind cannot contain a null record." }
            $Definition = @{}
            foreach ($Property in $Record.PSObject.Properties) { $Definition[$Property.Name] = $Property.Value }
            $ContractKind = if ($Kind -eq 'Evidence') { 'Evidence' } else { $Kind.TrimEnd('s') }
            [void] (New-PSIContractObject -Kind $ContractKind -Definition $Definition)
            $Id = [string] (Get-PSIProperty -InputObject $Record -Name Id)
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind contains an invalid or missing Id." }
            if (-not $Ids[$Kind].Add($Id)) { throw "$Kind contains duplicate Id '$Id'." }
        }
    }
    $References = @(
        @{ Kind='Findings'; Field='AffectedResourceIds'; Target='Resources' },
        @{ Kind='Findings'; Field='EvidenceIds'; Target='Evidence' },
        @{ Kind='Findings'; Field='Relationships'; Target='Relationships' },
        @{ Kind='Resources'; Field='FindingIds'; Target='Findings' },
        @{ Kind='Resources'; Field='EvidenceIds'; Target='Evidence' },
        @{ Kind='Resources'; Field='RelationshipIds'; Target='Relationships' },
        @{ Kind='Evidence'; Field='FindingIds'; Target='Findings' },
        @{ Kind='Evidence'; Field='ResourceIds'; Target='Resources' },
        @{ Kind='Relationships'; Field='SourceResourceId'; Target='Resources' },
        @{ Kind='Relationships'; Field='TargetResourceId'; Target='Resources' },
        @{ Kind='Relationships'; Field='FindingIds'; Target='Findings' }
    )
    foreach ($Reference in $References) {
        foreach ($Record in @((Get-PSIProperty -InputObject $Model -Name $Reference.Kind -DefaultValue @()))) {
            $Value = Get-PSIProperty -InputObject $Record -Name $Reference.Field
            if ($null -eq $Value) { continue }
            foreach ($ReferenceId in @($Value)) {
                if ([string]::IsNullOrWhiteSpace([string] $ReferenceId) -or -not $Ids[$Reference.Target].Contains([string] $ReferenceId)) {
                    throw "$($Reference.Kind) '$($Record.Id)' has broken $($Reference.Field) reference '$ReferenceId' to $($Reference.Target)."
                }
            }
        }
    }
    $true
}

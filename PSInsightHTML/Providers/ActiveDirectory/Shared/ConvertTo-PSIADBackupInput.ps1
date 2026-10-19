function ConvertTo-PSIADBackupInput {
    <# .SYNOPSIS Validate explicitly supplied system-state backup observations. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][psobject] $InputObject,
        [Parameter(Mandatory)][string] $Domain,
        [Parameter(Mandatory)][string[]] $DomainControllers
    )
    process {
        $DC=[string]$InputObject.DC
        if ([string]::IsNullOrWhiteSpace($DC) -or $DC -notin $DomainControllers) { throw "Backup input DC '$DC' is not in the collected domain scope." }
        if ($null -eq $InputObject.PSObject.Properties['LastSuccessfulSystemStateBackup']) { throw 'Backup input requires LastSuccessfulSystemStateBackup (a DateTime or null).' }
        $Last=$InputObject.LastSuccessfulSystemStateBackup
        if ($null -ne $Last -and $Last -isnot [datetime]) { throw 'LastSuccessfulSystemStateBackup must be a typed DateTime or null.' }
        $Source=[string]$InputObject.Source
        if ([string]::IsNullOrWhiteSpace($Source)) { throw 'Backup input requires a named Source.' }
        $State=if ($null -ne $InputObject.PSObject.Properties['CollectionState'] -and $InputObject.CollectionState) { [string]$InputObject.CollectionState } else { 'Collected' }
        if ($State -notin @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')) { throw "Invalid backup collection state '$State'." }
        $Confidence=if ($InputObject.Confidence) { [string]$InputObject.Confidence } else { 'Low' }
        if ($Confidence -notin @('High','Medium','Low')) { throw "Invalid backup confidence '$Confidence'." }
        if ($null -ne $InputObject.PSObject.Properties['EvidenceTimestamp'] -and $null -ne $InputObject.EvidenceTimestamp -and $InputObject.EvidenceTimestamp -isnot [datetime]) { throw 'Backup EvidenceTimestamp must be a typed DateTime.' }
        [pscustomobject]@{
            DC=$DC; Domain=$Domain; LastSuccessfulSystemStateBackup=$Last; Source=$Source
            EvidenceTimestamp=if ($InputObject.EvidenceTimestamp -is [datetime]) { [datetime]$InputObject.EvidenceTimestamp } else { Get-Date }
            CollectionState=$State; CollectionMethod='Provider input'; Confidence=$Confidence
        }
    }
}

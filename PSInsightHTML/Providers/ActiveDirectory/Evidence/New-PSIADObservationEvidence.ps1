function New-PSIADObservationEvidence {
    <# .SYNOPSIS Create PSI evidence from a normalized collection result without asserting a finding. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory)][pscustomobject] $Snapshot,
        [Parameter(Mandatory)][object] $CollectionResult,
        [string] $Summary = '',
        [string[]] $ResourceIds = @(),
        [ValidateSet('High','Medium','Low','Unknown')][string] $Confidence = 'Unknown'
    )
    $State=[string] $CollectionResult.Status
    if (-not $State) { $State='Unknown' }
    $RecordedAt=if ($CollectionResult.CompletedAt -is [datetime]) { [datetime] $CollectionResult.CompletedAt } else { [datetime] $Snapshot.CollectedAt }
    New-PSIEvidenceRecord -Definition @{
        Id=$Id; Title=$Title; Type='AD collection observation'; Source=$Snapshot.Source
        CollectedAt=$RecordedAt; Summary=$Summary
        Data=@{ Collector=[string] $CollectionResult.CollectorId; CollectionState=$State; Scope=[string] $CollectionResult.Scope; Confidence=$Confidence }
        Metadata=@{ CollectionState=$State; Scope=[string] $CollectionResult.Scope; Confidence=$Confidence }
        ResourceIds=$ResourceIds
    }
}

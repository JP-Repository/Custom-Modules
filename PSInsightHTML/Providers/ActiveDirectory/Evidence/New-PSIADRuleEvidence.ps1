function New-PSIADRuleEvidence {
    <# .SYNOPSIS Convert a provider observation into one PSI evidence record. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Inventory,
          [Parameter(Mandatory)][string] $RuleId,
          [Parameter(Mandatory)][string] $RuleName,
          [Parameter(Mandatory)][string] $TargetOS,
          [Parameter(Mandatory)][pscustomobject] $Outcome,
          [Parameter(Mandatory)][object] $Source,
          [string[]] $ResourceIds=@(),
          [string[]] $FindingIds=@())
    New-PSIEvidenceRecord -Definition @{
        Id="evidence-$RuleId"; Title="$RuleName observation"; Type='Provider rule observation'
        Source=$Inventory.Source; CollectedAt=$Inventory.CollectedAt; Summary=$Outcome.Observed
        Data=@{ RuleId=$RuleId; TargetOS=$TargetOS; Observed=$Outcome.Observed; Expected=$Outcome.Expected; SourceUrl=$Source.Url; SourceName=$Source.Name }
        Metadata=@{ CollectionStateApplicability='NotApplicable' }
        FindingIds=$FindingIds; ResourceIds=$ResourceIds
    }
}

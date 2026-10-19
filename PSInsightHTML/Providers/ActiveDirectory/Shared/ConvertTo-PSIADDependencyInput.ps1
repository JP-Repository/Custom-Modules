function ConvertTo-PSIADDependencyInput {
    <# .SYNOPSIS Normalize explicitly supplied dependency records without assessing them. #>
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][object] $InputObject)
    process {
        $Name=[string] $InputObject.Name
        $Type=[string] $InputObject.Type
        if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Type)) {
            throw 'Provider dependency input requires Name and Type.'
        }
        [pscustomobject]@{
            Id='provider-input-' + ([guid]::NewGuid().ToString('N'))
            Name=$Name; Type=$Type; Version=[string] $InputObject.Version
            Owner=[string] $InputObject.Owner; Criticality=[string] $InputObject.Criticality
            Notes=[string] $InputObject.Notes; EvidenceSource=[string] $InputObject.EvidenceSource
            CU=$null; Confidence='ProviderInput'; Status='NotTested'; QueryState='ProviderInput'
            ProviderInputRequired=$false; Detail=[string] $InputObject.Notes
        }
    }
}

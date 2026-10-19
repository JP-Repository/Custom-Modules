function Get-PSIADSecurityRuleOutcome {
    <# .SYNOPSIS Interpret one scoped security observation without collection or remediation. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Rule,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Observations,
        [Parameter(Mandatory)][hashtable] $Thresholds,
        [AllowNull()][pscustomobject] $DC,
        [Parameter(Mandatory)][string] $Domain
    )
    $Scope=if ($Rule.Scope -eq 'Domain') { $Domain } elseif ($null -ne $DC) { [string]$DC.Name } else { '' }
    $Matched=@($Observations | Where-Object { $_.RuleId -eq $Rule.Id -and $_.DC -eq $Scope })
    $State='NotTested'; $Observed='Required security evidence was not collected.'; $Expected='A sufficiently complete, attributable observation.'
    if ($Rule.Role -eq 'DNS' -and $null -ne $DC -and $DC.DNSRole -eq $false) {
        return [pscustomobject]@{ Status='NotApplicable'; Observed='DNS Server role is not present on this controller.'; Expected='Applicable only to DNS servers.'; Observations=$Matched }
    }
    if (-not $Matched.Count) { return [pscustomobject]@{ Status=$State; Observed=$Observed; Expected=$Expected; Observations=@() } }
    $Fact=$Matched[0]
    $Observed="Collection $($Fact.CollectionState); $($Fact.EvidenceType); value: $(if ($null -eq $Fact.Value) { 'unavailable' } else { [string]$Fact.Value })"
    if ($Fact.CollectionState -eq 'Partial' -and $Fact.EvidenceType -eq 'SelectedRegistry' -and $Fact.Value -is [int]) {
        $Weak=$false
        switch ([string]$Rule.Id) {
            'ldap-signing' { $Weak=$Fact.Value -lt 2 }
            'ldap-channel-binding' { $Weak=$Fact.Value -eq 0 }
            'ntlm-policy' { $Weak=$Fact.Value -lt 5 }
            'smb-signing' { $Weak=$Fact.Value -eq 0 }
        }
        if ($Weak) { $State='Review'; $Observed+='; selected registry value suggests exposure, but effective policy is unverified.'; $Expected='Confirm effective policy and dependent client behavior.' }
        else { $Observed+='; selected registry value is insufficient to conclude effective policy or a Secure state.' }
    }
    elseif ($Fact.CollectionState -eq 'Collected' -and $Fact.EvidenceType -eq $Rule.Evidence -and $null -ne $Fact.Value) {
        if ($Rule.Threshold) {
            $Limit=[double]$Thresholds[[string]$Rule.Threshold]
            if ($Fact.Value -is [ValueType]) {
                $State=if ($Rule.Id -eq 'event-retention') { if ([double]$Fact.Value -lt $Limit) { 'Review' } else { 'Ready' } }
                    elseif ([double]$Fact.Value -ge $Limit) { 'Review' } else { 'Ready' }
                $Expected=if ($Rule.Id -eq 'event-retention') { "At least $Limit MB, subject to local retention policy." } else { "Below $Limit days, subject to local rotation policy." }
            }
        }
        else {
            $Value=[string]$Fact.Value
            if ($Value -in @($Rule.Good)) { $State='Ready' }
            elseif ($Value -in @($Rule.Review)) { $State='Review' }
            elseif ($Value -in @($Rule.Bad)) { $State='Blocked' }
            $Expected=if (@($Rule.Good).Count) { @($Rule.Good) -join ' or ' } else { 'Reviewed expected security state.' }
        }
    }
    elseif ($Fact.CollectionState -eq 'Partial') { $Observed+='; partial evidence lacks the facts required by this rule.' }
    elseif ($Fact.CollectionState -in @('Failed','NotSupported','NotRequested','NotTested')) { $Observed+='; no secure conclusion is possible.' }
    else { $Observed+='; evidence type or value is insufficient for this rule.' }
    [pscustomobject]@{ Status=$State; Observed=$Observed; Expected=$Expected; Observations=$Matched }
}

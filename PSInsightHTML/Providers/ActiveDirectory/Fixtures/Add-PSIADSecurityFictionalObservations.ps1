function Add-PSIADSecurityFictionalObservations {
    <# .SYNOPSIS Add explicitly fictional security measurements to evidence, never to the snapshot. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot,[Parameter(Mandatory)][pscustomobject] $Evidence)
    if ($Snapshot.Source -ne 'Fictional sample' -or $Evidence.Kind -ne 'ActiveDirectory.SecurityEvidence') { throw 'Fictional security observations require the fictional normalized snapshot and matching evidence.' }
    $Secure=@{
        'ldap-signing'='Required'; 'ldap-channel-binding'='Required'; 'ldaps-capability'='Valid'; 'ldaps-usage'='Observed'
        'ntlm-policy'='NtlmV2Only'; 'ntlmv1-usage'='NotObserved'; 'kerberos-aes'='Supported'; 'rc4-policy'='Disallowed'; 'rc4-usage'='NotObserved'
        'smb-signing'='Required'; 'tls10'='Disabled'; 'tls11'='Disabled'; 'tls12'='Enabled'; 'dc-options'='Expected'
        'audit-policy'='Complete'; 'event-retention'=2048; 'powershell-logging'='Enabled'; 'firewall'='Enabled'; 'defender'='Healthy'
        'credential-guard'='Enabled'; 'lsass-protection'='Enabled'; 'wdigest'='Disabled'; 'rdp'='Restricted'; 'smbv1'='Disabled'; 'dns-zone-transfer'='Restricted'
    }
    $DomainValues=@{ 'auth-policy'='Approved'; 'privileged-members'='Unexpected'; 'privileged-hygiene'='Inactive'; 'krbtgt-age'=390 }
    foreach ($Observation in @($Evidence.Observations)) {
        $Value=$null
        if ($Observation.DC -eq $Evidence.Domain -and $DomainValues.ContainsKey($Observation.RuleId)) { $Value=$DomainValues[$Observation.RuleId] }
        elseif ($Observation.DC -eq 'dc-02.corp.example' -and $Secure.ContainsKey($Observation.RuleId)) { $Value=$Secure[$Observation.RuleId] }
        elseif ($Observation.DC -eq 'dc-03.corp.example' -and $Observation.RuleId -in @('ldap-signing','ldap-channel-binding','smb-signing','tls12','audit-policy')) {
            $Value=if ($Observation.RuleId -eq 'ldap-channel-binding') { 'WhenSupported' } else { $Secure[$Observation.RuleId] }
        }
        elseif ($Observation.DC -eq 'dc-05.corp.example' -and $Observation.RuleId -in @('ldap-signing','ntlm-policy','ntlmv1-usage','rc4-policy','rc4-usage','smb-signing','tls10','tls12','audit-policy')) {
            $Value=switch ($Observation.RuleId) { 'ntlmv1-usage' { 'Observed' }; 'rc4-policy' { 'DependencyRequired' }; 'rc4-usage' { 'Observed' }; 'tls10' { 'Enabled' }; default { $Secure[$Observation.RuleId] } }
        }
        elseif ($Observation.DC -eq 'dc-01.corp.example' -and $Observation.RuleId -in @('ldap-signing','smb-signing','tls12')) { $Value=$Secure[$Observation.RuleId] }
        if ($null -ne $Value -and $Observation.CollectionState -ne 'Collected') {
            $Observation.Value=$Value; $Observation.CollectionState='Collected'; $Observation.EvidenceType=if ($Observation.RuleId -in @('ntlmv1-usage','rc4-usage','ldaps-usage')) { 'CompletedTrafficTelemetry' } elseif ($Observation.RuleId -eq 'audit-policy') { 'EffectiveAuditPolicy' } elseif ($Observation.RuleId -eq 'event-retention') { 'EventLogConfiguration' } elseif ($Observation.RuleId -in @('ldaps-capability')) { 'CertificateInspection' } elseif ($Observation.RuleId -in @('defender')) { 'ProductHealth' } elseif ($Observation.RuleId -eq 'dns-zone-transfer') { 'EffectiveDnsConfiguration' } elseif ($Observation.RuleId -in @('tls10','tls11','tls12','firewall','credential-guard','lsass-protection','wdigest','smbv1')) { 'EffectiveConfiguration' } elseif ($Observation.RuleId -in @('privileged-members')) { 'ReviewedMembership' } elseif ($Observation.RuleId -in @('privileged-hygiene')) { 'ReviewedAccountInventory' } elseif ($Observation.RuleId -in @('krbtgt-age')) { 'AccountMetadata' } else { 'EffectivePolicy' }
            $Observation.CollectionMethod='Fictional scenario, explicitly reviewed sample fact'; $Observation.Confidence='Sample'; $Observation.Source='Fictional fixture'; $Observation.SourceType='ProviderInput'
        }
    }
    $Evidence.EvidenceCompleteness.Collected=@($Evidence.Observations | Where-Object CollectionState -eq Collected).Count
    $Evidence.EvidenceCompleteness.Percent=[math]::Round(100*$Evidence.EvidenceCompleteness.Collected/$Evidence.EvidenceCompleteness.Total,1)
    $Evidence
}

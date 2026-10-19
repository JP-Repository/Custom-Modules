function New-PSIADSecurityEvidenceModel {
    <# .SYNOPSIS Project per-DC security facts and explicit gaps from one normalized snapshot. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot)
    if (@($Snapshot.Domains).Count -ne 1 -or $null -eq $Snapshot.PSObject.Properties['SecurityCollectionResults']) {
        throw 'Security evidence requires a normalized single-domain snapshot with SecurityCollectionResults.'
    }
    $Pack=Import-PowerShellDataFile (Join-Path $PSScriptRoot '../Rules/Security/SecurityRules.psd1')
    $Domain=[string]$Snapshot.Domains[0].Name
    $Observations=[System.Collections.Generic.List[object]]::new()
    foreach ($Rule in @($Pack.Rules)) {
        $Targets=if ($Rule.Scope -eq 'Domain') { @($Domain) } else { @($Snapshot.DomainControllers | ForEach-Object Name) }
        foreach ($Target in $Targets) {
            $State='NotRequested'; $Value=$null; $EvidenceType=[string]$Rule.Evidence; $Method='No complete reusable evidence in the snapshot'; $Confidence='None'; $SourceType='None'; $SimulatedSourceType=$null; $Detail=$null; $ErrorClass=''; $Window=$null; $Stamp=[datetime]$Snapshot.CollectedAt
            $Match=@($Snapshot.SecurityCollectionResults | Where-Object DC -eq $Target | Select-Object -Last 1)
            if ($Rule.Scope -eq 'DC' -and $Match.Count) {
                $State=[string]$Match[0].State
                if ($State -notin @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')) { $State='NotTested' }
                $RegistryKey=if ($Rule.Id -eq 'ntlm-policy') { 'ntlm' } else { [string]$Rule.Id }
                if ($Match[0].Values -and $Match[0].Values.ContainsKey($RegistryKey)) {
                    $Raw=[string]$Match[0].Values[$RegistryKey]
                    $Method='Selected registry DWORD; effective policy not established'
                    $EvidenceType='SelectedRegistry'; $SourceType='RegistryPolicy'; $Confidence='Medium'
                    if ($Raw -match '^Observed registry DWORD: (\d+)$') { $Value=[int]$Matches[1]; if ($State -eq 'Collected') { $State='Partial' } }
                    else { $Value=$Raw; $State='Partial' }
                }
                elseif ($State -in @('Collected','Partial')) { $State='NotTested' }
            }
            if ($Rule.Scope -eq 'DC') {
                $Runtime=@($Snapshot.SecurityRuntimeResults | Where-Object DC -eq $Target | Select-Object -Last 1)
                if ($Runtime.Count) {
                    $Candidates=@($Runtime[0].Facts | Where-Object { $_.RuleId -eq $Rule.Id })
                    if ($Rule.Id -in @('tls10','tls11','tls12')) { $Candidates=@($Runtime[0].Facts | Where-Object { $_.RuleId -eq "$($Rule.Id)-server" }) }
                    $Candidate=@($Candidates | Where-Object CollectionState -eq Collected | Select-Object -First 1)
                    if (-not $Candidate.Count) { $Candidate=@($Candidates | Select-Object -First 1) }
                    if ($Candidate.Count) {
                        $Fact=$Candidate[0]; $State=[string]$Fact.CollectionState; $Value=$Fact.Value; $EvidenceType=[string]$Fact.EvidenceType
                        if ($State -eq 'Collected' -and $EvidenceType -ne [string]$Rule.Evidence) { $State='Partial' }
                        $SourceType=[string]$Fact.SourceType; $Confidence=[string]$Fact.Confidence; $Detail=$Fact.Detail; $ErrorClass=[string]$Fact.ErrorClass
                        $SimulatedSourceType=$Fact.SimulatedSourceType
                        $Method=[string]$Runtime[0].Method; if ($Fact.Timestamp) { $Stamp=[datetime]$Fact.Timestamp }; $Window=$Fact.QueryWindowHours
                    } elseif ($State -eq 'NotRequested') { $State=[string]$Runtime[0].State; $ErrorClass=[string]$Runtime[0].ErrorClass }
                }
                if ($Rule.Id -in @('ntlmv1-usage','rc4-usage')) {
                    $Kind=if ($Rule.Id -eq 'ntlmv1-usage') { 'NTLM' } else { 'Kerberos' }
                    $Version=if ($Kind -eq 'NTLM') { 'NTLMv1' } else { 'RC4' }
                    $Hits=@($Snapshot.SecurityTelemetry | Where-Object { $_.DC -eq $Target -and $_.Kind -eq $Kind -and $_.Version -eq $Version })
                    if ($Hits.Count) { $State='Collected'; $Value='Observed'; $EvidenceType='CompletedTrafficTelemetry'; $SourceType=[string]$Hits[0].SourceType; $Confidence=[string]$Hits[0].Confidence; $Detail=$Hits; $Method='Bounded Security event telemetry'; $Stamp=[datetime]$Hits[0].Timestamp; $Window=$Hits[0].CollectionWindowHours; $ErrorClass='' }
                }
                if ($Rule.Id -eq 'dns-zone-transfer') {
                    $DCRecord=@($Snapshot.DomainControllers | Where-Object Name -eq $Target | Select-Object -First 1)
                    if ($DCRecord.Count -and $DCRecord[0].DNSQueryStates.Zones -eq 'Collected') {
                        $Zones=@($DCRecord[0].DNSZones | Where-Object { $_.ZoneType -eq 'Primary' })
                        $Known=@($Zones | Where-Object { [string]$_.SecureSecondaries -in @('NoTransfer','TransferAnyServer','TransferToZoneNameServer','TransferToSecureServers') })
                        if ($Zones.Count -and $Known.Count -eq $Zones.Count) {
                            $State='Collected'; $Value=if (@($Known | Where-Object SecureSecondaries -eq TransferAnyServer).Count) { 'Unrestricted' } else { 'Restricted' }
                            $EvidenceType='EffectiveDnsConfiguration'; $SourceType='DNS'; $Confidence='Medium'; $Detail=$Known; $Method='DNS zone configuration, not a network transfer test'
                        }
                    }
                }
            } elseif ($Rule.Id -eq 'krbtgt-age' -and $Snapshot.PrivilegedEvidence -and $Snapshot.PrivilegedEvidence.Krbtgt -and $Snapshot.PrivilegedEvidence.Krbtgt.CollectionState -eq 'Collected' -and $Snapshot.PrivilegedEvidence.Krbtgt.PasswordLastSet -is [datetime]) {
                $K=$Snapshot.PrivilegedEvidence.Krbtgt; $State='Collected'; $Value=[math]::Max(0,[math]::Floor(($Stamp-[datetime]$K.PasswordLastSet).TotalDays)); $EvidenceType='AccountMetadata'
                $SourceType=if ($K.SourceType) { [string]$K.SourceType } else { 'Directory' }
                $Confidence=if ($K.Confidence) { [string]$K.Confidence } else { 'High' }
                $SimulatedSourceType=$K.SimulatedSourceType; $Detail=$K
                $Method=if ($SourceType -eq 'ProviderInput') { 'Fictional KRBTGT account metadata' } else { 'Domain-scoped KRBTGT account metadata' }
            }
            $Observations.Add([pscustomobject]@{
                RuleId=[string]$Rule.Id; DC=[string]$Target; Domain=$Domain; CollectionState=$State
                Value=$Value; EvidenceType=$EvidenceType; CollectionMethod=$Method; Confidence=$Confidence
                Timestamp=$Stamp; Source='Shared normalized AD snapshot'; SourceType=$SourceType; SimulatedSourceType=$SimulatedSourceType; Detail=$Detail; QueryWindowHours=$Window; ErrorClass=$ErrorClass
            })
        }
    }
    [pscustomobject]@{
        ContractVersion='1.0'; Kind='ActiveDirectory.SecurityEvidence'; Domain=$Domain
        CollectedAt=[datetime]$Snapshot.CollectedAt; NoSecurityVerdict=$true
        Observations=$Observations.ToArray(); CollectionCoverage=$Snapshot.CollectionCoverage
        PrivilegedAccess=$Snapshot.PrivilegedEvidence; AuthenticationTelemetry=@($Snapshot.SecurityTelemetry)
        GpoIntent=@($Snapshot.GpoIntent)
        Policy=@($Observations | Where-Object { $_.EvidenceType -in @('EffectivePolicy','SelectedRegistry','RegistryConfiguration') })
        Audit=@($Observations | Where-Object { $_.EvidenceType -in @('EffectiveAuditPolicy','EventLogConfiguration') })
        ProtocolConfiguration=@($Observations | Where-Object { $_.RuleId -in @('ldap-signing','ldap-channel-binding','smb-signing','smbv1','tls10','tls11','tls12','dns-zone-transfer') })
        EndpointProtection=@($Observations | Where-Object RuleId -eq defender)
        CredentialProtection=@($Observations | Where-Object { $_.RuleId -in @('credential-guard','lsass-protection','wdigest') })
        Certificates=@($Observations | Where-Object RuleId -eq ldaps-capability)
        Firewall=@($Observations | Where-Object RuleId -eq firewall)
        EvidenceCompleteness=[pscustomobject]@{ Total=$Observations.Count; Collected=@($Observations | Where-Object CollectionState -eq Collected).Count; Percent=if ($Observations.Count) { [math]::Round(100*@($Observations | Where-Object CollectionState -eq Collected).Count/$Observations.Count,1) } else { 0 } }
        CollectionResults=@($Snapshot.CollectionResults | Where-Object { $_.CollectorId -in @('Security','SecurityRuntime','Privileged') })
    }
}

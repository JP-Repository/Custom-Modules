function Add-PSIADSecuritySampleFacts {
    <# .SYNOPSIS Attach fictional reusable facts to the raw shared snapshot. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Raw)
    if (-not $Raw.Sample) { throw 'Security sample facts require a fictional snapshot.' }
    $Now=[datetime]$Raw.CollectedAt; $Results=[System.Collections.Generic.List[object]]::new(); $Telemetry=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in @($Raw.DomainControllers)) {
        $Facts=[System.Collections.Generic.List[object]]::new()
        $Index=[array]::IndexOf(@($Raw.DomainControllers | ForEach-Object Name),[string]$DC.Name)
        if ($Index -in @(0,1,2,4)) {
            foreach ($Spec in @(
                @('smb-signing',$(if ($Index -eq 4) { 'EnabledNotRequired' } else { 'Required' }),'EffectivePolicy','RuntimeConfiguration'),
                @('smbv1','Disabled','EffectiveConfiguration','RuntimeConfiguration'),
                @('firewall',$(if ($Index -eq 4) { 'Partial' } else { 'Enabled' }),'EffectiveConfiguration','RuntimeConfiguration'),
                @('defender','Healthy','ProductHealth','ProductRuntime'),
                @('event-retention',2048,'EventLogConfiguration','EventLog')
            )) { $Facts.Add([pscustomobject]@{ RuleId=$Spec[0]; Value=$Spec[1]; EvidenceType=$Spec[2]; SourceType=$Spec[3]; CollectionState='Collected'; Confidence='High'; Detail=$null; ErrorClass=''; Timestamp=$Now; QueryWindowHours=$null }) }
            $Facts.Add([pscustomobject]@{ RuleId='credential-guard'; Value=$null; EvidenceType='EffectiveConfiguration'; SourceType='CIM'; CollectionState='NotSupported'; Confidence='None'; Detail=$null; ErrorClass='Unsupported'; Timestamp=$Now; QueryWindowHours=$null })
            $Facts.Add([pscustomobject]@{ RuleId='audit-policy'; Value=$null; EvidenceType='EffectiveAuditPolicy'; SourceType='AuditPolicy'; CollectionState='Partial'; Confidence='High'; Detail=@([pscustomobject]@{ Subcategory='Logon'; Setting='Success and Failure' }); ErrorClass=''; Timestamp=$Now; QueryWindowHours=$null })
            $Facts.Add([pscustomobject]@{ RuleId='ldaps-capability'; Value=$null; EvidenceType='CertificateInspection'; SourceType='CertificateStore'; CollectionState='Partial'; Confidence='Medium'; Detail=@([pscustomobject]@{ Subject="CN=$($DC.Name)"; HasPrivateKey=$true; NotAfter=$Now.AddDays(90) }); ErrorClass=''; Timestamp=$Now; QueryWindowHours=$null })
        }
        if ($Index -eq 4) {
            $Telemetry.Add([pscustomobject]@{ Kind='NTLM'; Version='NTLMv1'; DC=$DC.Name; Domain='corp.example'; Timestamp=$Now.AddHours(-2); Account='legacy-operator'; Client='legacy-console'; Service=$null; SourceEvent=4624; SourceType='EventLog'; CollectionState='Collected'; Confidence='Sample'; ErrorClass=''; CollectionWindowHours=72 })
            $Telemetry.Add([pscustomobject]@{ Kind='Kerberos'; Version='RC4'; DC=$DC.Name; Domain='corp.example'; Timestamp=$Now.AddHours(-1); Account='legacy-svc'; Client='10.40.3.90'; Service='HTTP/legacy.corp.example'; SourceEvent=4769; SourceType='EventLog'; CollectionState='Collected'; Confidence='Sample'; ErrorClass=''; CollectionWindowHours=72 })
        }
        if ($Index -eq 1) { $Telemetry.Add([pscustomobject]@{ Kind='Kerberos'; Version='AES256'; DC=$DC.Name; Domain='corp.example'; Timestamp=$Now.AddHours(-1); Account='app-svc'; Client='10.40.1.90'; Service='HTTP/app.corp.example'; SourceEvent=4769; SourceType='EventLog'; CollectionState='Collected'; Confidence='Sample'; ErrorClass=''; CollectionWindowHours=72 }) }
        foreach ($Fact in $Facts) {
            $Fact | Add-Member -NotePropertyName SimulatedSourceType -NotePropertyValue $Fact.SourceType
            $Fact.SourceType='ProviderInput'
            if ($Fact.Confidence -ne 'None') { $Fact.Confidence='Sample' }
        }
        $State=if ($Index -eq 7) { 'Failed' } elseif ($Facts.Count) { 'Partial' } else { 'NotSupported' }
        $Results.Add([pscustomobject]@{ DC=$DC.Name; Domain='corp.example'; State=$State; Facts=$Facts.ToArray(); QueryWindowHours=72; Timestamp=$Now; ErrorClass=if ($Index -eq 7) { 'FictionalTimeout' } else { '' }; Method='Fictional read-only runtime fixture' })
    }
    $Members=@(
        [pscustomobject]@{ Group='Domain Admins'; SourceGroup='Domain Admins'; Principal='admin-01'; PrincipalType='user'; SID='S-1-5-21-100-200-300-1101'; Direct=$true; NestedPath=@('Domain Admins','admin-01'); ResolutionState='Resolved'; CollectionState='Collected'; Domain='corp.example'; Scope='AssessedDomain'; Metadata=[pscustomobject]@{ Enabled=$true; PasswordLastSet=$Now.AddDays(-45); PasswordNeverExpires=$false; LastLogonDate=$Now.AddDays(-2); HasServicePrincipalName=$false }; ErrorClass=''; Timestamp=$Now },
        [pscustomobject]@{ Group='Domain Admins'; SourceGroup='Operations Admins'; Principal='admin-02'; PrincipalType='user'; SID='S-1-5-21-100-200-300-1102'; Direct=$false; NestedPath=@('Domain Admins','Operations Admins','admin-02'); ResolutionState='Resolved'; CollectionState='Collected'; Domain='corp.example'; Scope='AssessedDomain'; Metadata=[pscustomobject]@{ Enabled=$true; PasswordLastSet=$Now.AddDays(-400); PasswordNeverExpires=$true; LastLogonDate=$Now.AddDays(-200); HasServicePrincipalName=$false }; ErrorClass=''; Timestamp=$Now },
        [pscustomobject]@{ Group='Enterprise Admins'; SourceGroup='Foreign Admins'; Principal='unresolved-foreign'; PrincipalType='Unresolved'; SID=$null; Direct=$false; NestedPath=@('Enterprise Admins','Foreign Admins','unresolved-foreign'); ResolutionState='Failed'; CollectionState='Partial'; Domain='corp.example'; Scope='ForestRoot'; Metadata=$null; ErrorClass='CrossDomainResolution'; Timestamp=$Now }
    )
    foreach ($Item in $Telemetry) {
        $Item | Add-Member -NotePropertyName SimulatedSourceType -NotePropertyValue $Item.SourceType
        $Item.SourceType='ProviderInput'
    }
    foreach ($Item in $Members) {
        $Item | Add-Member -NotePropertyName SourceType -NotePropertyValue ProviderInput
        $Item | Add-Member -NotePropertyName SimulatedSourceType -NotePropertyValue Directory
        $Item | Add-Member -NotePropertyName Confidence -NotePropertyValue $(if ($Item.CollectionState -eq 'Collected') { 'Sample' } else { 'None' })
    }
    $Groups=@('Domain Admins','Administrators','Enterprise Admins','Schema Admins' | ForEach-Object { [pscustomobject]@{ Group=$_; Domain='corp.example'; Scope=if ($_ -in @('Enterprise Admins','Schema Admins')) { 'ForestRoot' } else { 'AssessedDomain' }; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; Timestamp=$Now; ErrorClass='' } })
    $Raw | Add-Member -NotePropertyName SecurityRuntimeResults -NotePropertyValue $Results.ToArray() -Force
    $Raw | Add-Member -NotePropertyName SecurityTelemetry -NotePropertyValue $Telemetry.ToArray() -Force
    $Raw | Add-Member -NotePropertyName PrivilegedEvidence -NotePropertyValue ([pscustomobject]@{ Groups=$Groups; Members=$Members; Krbtgt=[pscustomobject]@{ Domain='corp.example'; Enabled=$false; PasswordLastSet=$Now.AddDays(-390); PasswordNeverExpires=$false; LastLogonTimestamp=$null; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; Timestamp=$Now; ErrorClass='' } }) -Force
    $Raw | Add-Member -NotePropertyName GpoIntent -NotePropertyValue @([pscustomobject]@{ Domain='corp.example'; Container='OU=Domain Controllers,DC=corp,DC=example'; GpLink='[LDAP://CN=Fictional DC Policy,CN=Policies,CN=System,DC=corp,DC=example;0]'; GpOptions=0; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; EffectivePolicyEstablished=$false; ErrorClass='' }) -Force
    $Raw
}

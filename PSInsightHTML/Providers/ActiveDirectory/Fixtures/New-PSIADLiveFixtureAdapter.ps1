function New-PSIADLiveFixtureAdapter {
    <# .SYNOPSIS Fictional command adapter. No AD, CIM, DNS, remoting, or network commands are invoked. #>
    [CmdletBinding()]
    param()
    @{
        Domain = { param($Name) [pscustomobject]@{ DNSRoot='root.example.test'; Forest='example.test'; DomainMode='Windows2016Domain'; NetBIOSName='ROOT'; DomainSID='S-1-5-21-100-200-300'; PDCEmulator='dc-a.root.example.test'; RIDMaster='dc-a.root.example.test'; InfrastructureMaster='dc-b.root.example.test' } }
        Forest = { param($Name) [pscustomobject]@{ Name='example.test'; ForestMode='Windows2016Forest'; SchemaMaster='dc-a.root.example.test'; DomainNamingMaster='dc-a.root.example.test' } }
        DCs = { param($Name) if ($Name -ne 'root.example.test') { throw 'Fixture domain mismatch' }; @(
            [pscustomobject]@{ HostName='dc-a.root.example.test'; Domain='root.example.test'; Site='North'; IPv4Address='192.0.2.11'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true },
            [pscustomobject]@{ HostName='dc-b.root.example.test'; Domain='root.example.test'; Site='South'; IPv4Address='192.0.2.12'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true },
            [pscustomobject]@{ HostName='dc-c.root.example.test'; Domain='root.example.test'; Site='North'; IPv4Address='192.0.2.13'; OperatingSystem='Windows Server 2022'; OperatingSystemVersion='20348'; IsReadOnly=$false; IsGlobalCatalog=$true },
            [pscustomobject]@{ HostName='dc-child.child.example.test'; Domain='child.example.test'; Site='Child'; IPv4Address='192.0.2.21'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true }
        ) }
        Sites = { param($Name) @([pscustomobject]@{ Name='North' },[pscustomobject]@{ Name='South' }) }
        Subnets = { param($Name) @([pscustomobject]@{ Name='192.0.2.0/25'; Site='North' },[pscustomobject]@{ Name='192.0.2.128/25'; Site='South' },[pscustomobject]@{ Name='198.51.100.0/24'; Site=$null }) }
        SiteLinks = { param($Name) @([pscustomobject]@{ Name='North-South'; SitesIncluded=@('North','South'); Cost=100; ReplicationFrequencyInMinutes=180; Schedule=$null }) }
        Partners = { param($HostName) @(
            [pscustomobject]@{ Partner='dc-b.root.example.test'; Partition='DC=root,DC=example,DC=test'; ConsecutiveReplicationFailures=0; LastReplicationSuccess=(Get-Date).AddMinutes(-12); LastReplicationResult=0 },
            [pscustomobject]@{ Partner='dc-child.child.example.test'; Partition='CN=Configuration,DC=example,DC=test'; ConsecutiveReplicationFailures=0; LastReplicationSuccess=(Get-Date).AddMinutes(-15); LastReplicationResult=0 },
            [pscustomobject]@{ Partner='dc-a.root.example.test'; Partition='CN=Schema,CN=Configuration,DC=example,DC=test'; ConsecutiveReplicationFailures=0; LastReplicationSuccess=(Get-Date).AddMinutes(-18); LastReplicationResult=0 }
        ) }
        Failures = { param($HostName) @() }
        Remote = { param($HostName) if ($HostName -like 'dc-c*') { throw 'Fictional remote management unavailable' }; [pscustomobject]@{ OS=[pscustomobject]@{ LastBootUpTime=(Get-Date).AddDays(-8); SystemDrive='C:'; TotalVisibleMemorySize=33554432; FreePhysicalMemory=16777216 }; Disk=[pscustomobject]@{ DeviceID='C:'; FreeSpace=24GB; Size=100GB }; Services=@{ NTDS='Running'; Netlogon='Running'; DNS='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }; ServiceDetails=@([pscustomobject]@{ Name='NTDS'; DisplayName='Active Directory Domain Services'; State='Running'; StartMode='Auto' }); NICs=@([pscustomobject]@{ IPAddress=@('192.0.2.11'); IPSubnet=@('255.255.255.128'); DNSServerSearchOrder=@('192.0.2.11','192.0.2.12') }) } }
        Cpu = { param($HostName) if ($HostName -like 'dc-c*') { throw [System.TimeoutException]::new('Fictional CPU query timeout') }; @(24,36) }
        Features = { param($HostName) if ($HostName -like 'dc-b*') { throw [System.NotSupportedException]::new('Fictional feature query unsupported') }; @([pscustomobject]@{ ID=10; Name='AD-Domain-Services' },[pscustomobject]@{ ID=12; Name='DNS' }) }
        Events = { param($HostName,$WindowHours) [pscustomobject]@{ Observations=@([pscustomobject]@{ DC=$HostName; Log='System'; Provider='FictionalProvider'; EventId=1000; Level='Information'; Timestamp=(Get-Date).AddHours(-1); MessageSummary='Fictional service startup event'; EvidenceCategory='System'; CollectionState='Collected'; QueryWindowHours=$WindowHours }); Queries=@([pscustomobject]@{ Log='System'; State='Collected'; ErrorClass=''; Message='' },[pscustomobject]@{ Log='DNS Server'; State='Failed'; ErrorClass='AccessDenied'; Message='Fictional access denied' }) } }
        Shares = { param($HostName) @('SYSVOL','NETLOGON') }
        Time = { param($HostName) 'time.root.example.test' }
        DNS = { param($HostName) throw [System.NotSupportedException]::new('DNS Server PowerShell management cmdlets are unavailable on the collector host.') }
        Dependencies = { param($Name) [pscustomobject]@{ Exchange=@(); PKI=@([pscustomobject]@{ Name='ca-a.root.example.test' }); ExchangeQueryStatus='Failed'; PKIQueryStatus='Collected'; Errors=@('Exchange directory query unavailable (UnauthorizedAccessException): fictional access denied'); Confidence='Directory objects only' } }
        Security = { param($HostName) @{ 'ldap-signing'='Observed registry DWORD: 2'; 'ntlm'='Observed registry DWORD: 5' } }
        SecurityRuntime = { param($HostName,$WindowHours)
            $Now=Get-Date; $Facts=[System.Collections.Generic.List[object]]::new()
            function Add-FictionalFact { param($Id,$Value,$Type,$Source,$State='Collected',$Confidence='High',$Detail=$null)
                $Facts.Add([pscustomobject]@{ RuleId=$Id; Value=$Value; EvidenceType=$Type; SourceType='ProviderInput'; SimulatedSourceType=$Source; CollectionState=$State; Confidence='Sample'; Detail=$Detail; ErrorClass=''; Timestamp=$Now; QueryWindowHours=$null })
            }
            if ($HostName -like 'dc-c*') { throw [System.NotSupportedException]::new('Fictional remoting unavailable') }
            Add-FictionalFact 'smb-signing' $(if ($HostName -like 'dc-a*') { 'Required' } else { 'EnabledNotRequired' }) 'EffectivePolicy' 'RuntimeConfiguration' 'Collected' 'High' ([pscustomobject]@{ ServerEnabled=$true; ServerRequired=($HostName -like 'dc-a*'); ClientEnabled=$true; ClientRequired=$true })
            Add-FictionalFact 'smbv1' 'Disabled' 'EffectiveConfiguration' 'RuntimeConfiguration'
            Add-FictionalFact 'firewall' $(if ($HostName -like 'dc-a*') { 'Enabled' } else { 'Partial' }) 'EffectiveConfiguration' 'RuntimeConfiguration' 'Collected' 'High' @([pscustomobject]@{ Profile='Domain'; Enabled=$true; DefaultInboundAction='Block'; DefaultOutboundAction='Allow' })
            Add-FictionalFact 'defender' 'Healthy' 'ProductHealth' 'ProductRuntime' 'Collected' 'High' ([pscustomobject]@{ AMServiceEnabled=$true; AntivirusEnabled=$true; RealTimeProtectionEnabled=$true; BehaviorMonitorEnabled=$true })
            Add-FictionalFact 'credential-guard' 'Enabled' 'EffectiveConfiguration' 'CIM' 'Collected' 'High' ([pscustomobject]@{ Configured=$true; Running=$true })
            Add-FictionalFact 'lsass-protection' 1 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Configured=1; Running=$null })
            Add-FictionalFact 'wdigest' 'Disabled' 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Configured=0; Effective=$null })
            Add-FictionalFact 'tls10-server' 0 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Enabled=0; DisabledByDefault=1; Side='Server' })
            Add-FictionalFact 'tls12-server' 1 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Enabled=1; DisabledByDefault=0; Side='Server' })
            Add-FictionalFact 'audit-policy' $null 'EffectiveAuditPolicy' 'AuditPolicy' 'Partial' 'High' @([pscustomobject]@{ Subcategory='Logon'; Setting='Success and Failure' })
            Add-FictionalFact 'event-retention' 2048 'EventLogConfiguration' 'EventLog' 'Collected' 'High' ([pscustomobject]@{ Log='Security'; MaximumSizeInBytes=2147483648; LogMode='Circular'; IsEnabled=$true })
            Add-FictionalFact 'ldaps-capability' $null 'CertificateInspection' 'CertificateStore' 'Partial' 'Medium' @([pscustomobject]@{ Thumbprint='FICTIONAL'; Subject='CN=dc-a.root.example.test'; HasPrivateKey=$true; NotAfter=$Now.AddDays(100) })
            Add-FictionalFact 'authentication-events' 3 'EventQuery' 'EventLog'
            $Telemetry=@([pscustomobject]@{ Kind='NTLM'; Version='NTLMv2'; DC=$HostName; Timestamp=$Now.AddMinutes(-10); Account='fictional-user'; Client='workstation-a'; Service=$null; SourceEvent=4624; SourceType='ProviderInput'; Confidence='Sample'; CollectionWindowHours=$WindowHours },[pscustomobject]@{ Kind='Kerberos'; Version='AES256'; DC=$HostName; Timestamp=$Now.AddMinutes(-15); Account='fictional-user'; Client='192.0.2.80'; Service='HTTP/app.example.test'; SourceEvent=4769; SourceType='ProviderInput'; Confidence='Sample'; CollectionWindowHours=$WindowHours })
            if ($HostName -like 'dc-b*') { $Telemetry+=@([pscustomobject]@{ Kind='NTLM'; Version='NTLMv1'; DC=$HostName; Timestamp=$Now.AddMinutes(-5); Account='legacy-user'; Client='legacy-workstation'; Service=$null; SourceEvent=4624; SourceType='ProviderInput'; Confidence='Sample'; CollectionWindowHours=$WindowHours },[pscustomobject]@{ Kind='Kerberos'; Version='RC4'; DC=$HostName; Timestamp=$Now.AddMinutes(-8); Account='legacy-service'; Client='192.0.2.81'; Service='HTTP/legacy.example.test'; SourceEvent=4769; SourceType='ProviderInput'; Confidence='Sample'; CollectionWindowHours=$WindowHours }) }
            [pscustomobject]@{ Facts=$Facts.ToArray(); Telemetry=$Telemetry; QueryWindowHours=$WindowHours }
        }
        Privileged = { param($Name,$Sid,$ForestRoot)
            $Now=Get-Date
            $Result=[pscustomobject]@{
                Groups=@('Domain Admins','Administrators','Enterprise Admins','Schema Admins' | ForEach-Object { [pscustomobject]@{ Group=$_; SID='fictional'; Domain=$Name; Scope=if ($_ -in @('Enterprise Admins','Schema Admins')) { 'ForestRoot' } else { 'AssessedDomain' }; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; Timestamp=$Now; ErrorClass='' } })
                Members=@(
                    [pscustomobject]@{ Group='Domain Admins'; SourceGroup='Domain Admins'; Principal='admin-a'; PrincipalType='user'; SID="$Sid-1101"; Direct=$true; NestedPath=@('Domain Admins','admin-a'); ResolutionState='Resolved'; CollectionState='Collected'; ErrorClass=''; Domain=$Name; Scope='AssessedDomain'; Timestamp=$Now; Metadata=[pscustomobject]@{ Enabled=$true; PasswordLastSet=$Now.AddDays(-50); PasswordNeverExpires=$false; LastLogonDate=$Now.AddDays(-1); HasServicePrincipalName=$false } },
                    [pscustomobject]@{ Group='Domain Admins'; SourceGroup='Operations Admins'; Principal='admin-b'; PrincipalType='user'; SID="$Sid-1102"; Direct=$false; NestedPath=@('Domain Admins','Operations Admins','admin-b'); ResolutionState='Resolved'; CollectionState='Collected'; ErrorClass=''; Domain=$Name; Scope='AssessedDomain'; Timestamp=$Now; Metadata=[pscustomobject]@{ Enabled=$true; PasswordLastSet=$Now.AddDays(-400); PasswordNeverExpires=$true; LastLogonDate=$Now.AddDays(-200); HasServicePrincipalName=$false } },
                    [pscustomobject]@{ Group='Enterprise Admins'; SourceGroup='Foreign Admins'; Principal='unresolved-foreign'; PrincipalType='Unresolved'; SID=$null; Direct=$false; NestedPath=@('Enterprise Admins','Foreign Admins','unresolved-foreign'); ResolutionState='Failed'; CollectionState='Partial'; ErrorClass='CrossDomainResolution'; Domain=$Name; Scope='ForestRoot'; Timestamp=$Now; Metadata=$null }
                )
                Krbtgt=[pscustomobject]@{ Domain=$Name; Enabled=$false; PasswordLastSet=$Now.AddDays(-390); PasswordNeverExpires=$false; LastLogonTimestamp=$null; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; Timestamp=$Now; ErrorClass='' }
            }
            foreach ($Member in $Result.Members) {
                $Member | Add-Member -NotePropertyName SourceType -NotePropertyValue ProviderInput
                $Member | Add-Member -NotePropertyName SimulatedSourceType -NotePropertyValue Directory
                $Member | Add-Member -NotePropertyName Confidence -NotePropertyValue $(if ($Member.CollectionState -eq 'Collected') { 'Sample' } else { 'None' })
            }
            $Result
        }
        GpoIntent = { param($Name,$ComputerDns) [pscustomobject]@{ Domain=$Name; Container='OU=Domain Controllers,DC=root,DC=example,DC=test'; GpLink='[LDAP://CN=Fictional DC Policy,CN=Policies,CN=System,DC=root,DC=example,DC=test;0]'; GpOptions=0; CollectionState='Collected'; SourceType='ProviderInput'; SimulatedSourceType='Directory'; Confidence='Sample'; EffectivePolicyEstablished=$false; ErrorClass='' } }
    }
}

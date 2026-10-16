function New-PSIADDCReadinessSample {
    <# .SYNOPSIS Return a deterministic, wholly fictional AD inventory. #>
    [CmdletBinding()]
    param([datetime] $AsOf = (Get-Date))

    $Names = @('dc-01','dc-02','dc-03','dc-04','dc-05','dc-06','dc-07','dc-08')
    $Sites = @('North','North','Central','Central','West','West','Remote','Remote')
    $Controllers = @(
        for ($I = 0; $I -lt $Names.Count; $I++) {
            $Name = "$($Names[$I]).corp.example"
            $Reachable = $I -ne 7
            $Services = @{ NTDS='Running'; Netlogon='Running'; DNS='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }
            if ($I -eq 7) { $Services.Netlogon='Unknown' }
            [pscustomobject]@{
                Name=$Name; Domain='corp.example'; Site=$Sites[$I]
                OS=if ($I -lt 4) { 'Windows Server 2016' } else { 'Windows Server 2019' }
                Build=if ($I -lt 4) { '14393' } else { '17763' }
                Writable=$I -ne 6; GlobalCatalog=$I -ne 6
                FSMORoles=switch ($I) { 0 { @('Schema Master','Domain Naming Master') } 1 { @('RID Master','PDC Emulator') } 2 { @('Infrastructure Master') } default { @() } }
                Reachable=$Reachable; Maintenance=$I -eq 7
                DNSRole=$I -ne 6; DNSClient=@("10.40.1.$(11 + ($I % 2))","10.40.2.$(11 + ($I % 2))")
                DNSForwarders=@('192.0.2.53','192.0.2.54'); ADIntegratedZone=$true
                ForwardZoneHealthy=$true; ReverseZoneHealthy=$I -ne 5
                ConditionalForwarders=@('partners.example')
                TimeSource=if ($I -eq 1) { 'ntp-a.example' } elseif ($I -eq 5) { 'Local CMOS Clock' } else { 'dc-02.corp.example' }
                Services=$Services; SysvolShare=$I -ne 7; NetlogonShare=$I -ne 7
                DiskFreeGB=if ($I -eq 5) { 8.0 } else { 24.0 + $I }; PendingReboot=$I -eq 4; UptimeDays=14 + $I
            }
        }
    )
    $Replication = @(
        [pscustomobject]@{ Source='dc-01.corp.example'; Destination='dc-02.corp.example'; NamingContext='DC=corp,DC=example'; CurrentFailures=0; ConsecutiveFailures=0; LastSuccess=$AsOf.AddMinutes(-8); LastError='None'; LatencyMinutes=8; Required=$true }
        [pscustomobject]@{ Source='dc-03.corp.example'; Destination='dc-04.corp.example'; NamingContext='CN=Configuration,DC=corp,DC=example'; CurrentFailures=0; ConsecutiveFailures=0; LastSuccess=$AsOf.AddMinutes(-12); LastError='1722 (historical, recovered)'; LatencyMinutes=12; Required=$true }
        [pscustomobject]@{ Source='dc-05.corp.example'; Destination='dc-06.corp.example'; NamingContext='DC=corp,DC=example'; CurrentFailures=0; ConsecutiveFailures=0; LastSuccess=$AsOf.AddMinutes(-15); LastError='None'; LatencyMinutes=15; Required=$true }
        [pscustomobject]@{ Source='dc-07.corp.example'; Destination='dc-05.corp.example'; NamingContext='DC=corp,DC=example'; CurrentFailures=0; ConsecutiveFailures=0; LastSuccess=$AsOf.AddMinutes(-22); LastError='None'; LatencyMinutes=22; Required=$true }
    )
    $Dependencies = @(
        [pscustomobject]@{ Id='exchange'; Name='Exchange Server 2019'; Type='Exchange'; Version='2019'; CU=13; Confidence='High'; Status='Observed'; Detail='Fictional Exchange 2019 CU13; lifecycle and target AD compatibility require review.' }
        [pscustomobject]@{ Id='entra-connect'; Name='Microsoft Entra Connect'; Type='Identity sync'; Version='2.x'; CU=$null; Confidence='Medium'; Status='Review'; Detail='Compatibility owner sign-off pending.' }
        [pscustomobject]@{ Id='adfs'; Name='AD FS'; Type='Federation'; Version='2019'; CU=$null; Confidence='Medium'; Status='Ready'; Detail='Sample lab validation recorded.' }
        [pscustomobject]@{ Id='pki'; Name='Enterprise CA'; Type='PKI'; Version='2019'; CU=$null; Confidence='Medium'; Status='Ready'; Detail='LDAPS chain observed in sample.' }
        [pscustomobject]@{ Id='ldap-app'; Name='Legacy LDAP application'; Type='LDAP/LDAPS'; Version='Unknown'; CU=$null; Confidence='Low'; Status='Review'; Detail='Signing compatibility review needed.' }
        [pscustomobject]@{ Id='fixed-dc'; Name='Batch connector'; Type='Hard-coded DC'; Version='1.0'; CU=$null; Confidence='High'; Status='Review'; Detail='Targets dc-03.corp.example by hostname.' }
        [pscustomobject]@{ Id='nps'; Name='NPS / RADIUS'; Type='NPS'; Version='Unknown'; CU=$null; Confidence='Low'; Status='NotTested'; Detail='Owner has not supplied validation.' }
        [pscustomobject]@{ Id='backup'; Name='Directory backup'; Type='Backup'; Version='Current'; CU=$null; Confidence='Medium'; Status='Ready'; Detail='Sample onboarding record.' }
        [pscustomobject]@{ Id='monitoring'; Name='DC monitoring'; Type='Monitoring'; Version='Current'; CU=$null; Confidence='Medium'; Status='Ready'; Detail='Sample service checks.' }
    )
    $Security = @{
        'ldap-signing'='Review'; 'ldap-channel-binding'='Ready'; 'smb-signing'='Ready'; 'ntlm'='Review'
        'kerberos'='Ready'; 'rc4'='Review'; 'tls'='Ready'; 'audit'='Ready'; 'firewall'='Ready'
        'rdp'='Ready'; 'defender'='Ready'; 'powershell-logging'='Ready'; 'event-retention'='Ready'
        'time-security'='Review'; 'privileged-access'='Ready'; 'local-options'='Ready'; 'user-rights'='Ready'
    }
    $Ports = @(
        foreach ($Port in @(53,88,123,135,389,445,464,636,3268,3269,5722)) {
            [pscustomobject]@{ Port=$Port; Role=if ($Port -in @(636,3268,3269)) { 'Expected by role/topology' } else { 'Required for tested path' }; Source='North site probe'; Destination='dc-02.corp.example'; Result='Reachable' }
        }
        [pscustomobject]@{ Port='Dynamic RPC'; Role='Not tested'; Source='Remote site'; Destination='dc-08.corp.example'; Result='NotTested' }
    )
    [pscustomobject]@{
        ContractVersion='1.0'; Sample=$true; CollectedAt=$AsOf
        Forest=[pscustomobject]@{ Name='corp.example'; FunctionalLevel=2016; SchemaMaster='dc-01.corp.example'; DomainNamingMaster='dc-01.corp.example'; SysvolReplication='DFSR'; DFSRMigrationState='Eliminated' }
        Domains=@([pscustomobject]@{ Name='corp.example'; FunctionalLevel=2016; PDCEmulator='dc-02.corp.example'; RIDMaster='dc-02.corp.example'; InfrastructureMaster='dc-03.corp.example' })
        Sites=@(
            [pscustomobject]@{ Name='North'; Subnets=@('10.40.1.0/24'); DomainControllers=@('dc-01.corp.example','dc-02.corp.example') }
            [pscustomobject]@{ Name='Central'; Subnets=@('10.40.2.0/24'); DomainControllers=@('dc-03.corp.example','dc-04.corp.example') }
            [pscustomobject]@{ Name='West'; Subnets=@('10.40.3.0/24'); DomainControllers=@('dc-05.corp.example','dc-06.corp.example') }
            [pscustomobject]@{ Name='Remote'; Subnets=@('10.40.4.0/24'); DomainControllers=@('dc-07.corp.example','dc-08.corp.example') }
        )
        DomainControllers=$Controllers; Replication=$Replication; Dependencies=$Dependencies; Security=$Security; Ports=$Ports
        SecurityValues=@{
            'ldap-signing'='Audit mode; unsigned binds observed'; 'ldap-channel-binding'='When supported'; 'smb-signing'='Enabled'
            'ntlm'='Legacy NTLM clients observed'; 'kerberos'='AES preferred'; 'rc4'='RC4 service ticket observed'
            'tls'='TLS 1.2 enabled'; 'audit'='Advanced audit enabled'; 'firewall'='Enabled'
            'rdp'='Restricted admin group'; 'defender'='Healthy'; 'powershell-logging'='Enabled'
            'event-retention'='90 days'; 'time-security'='One local-clock source'; 'privileged-access'='Reviewed'
            'local-options'='Reviewed'; 'user-rights'='Reviewed'
        }
        DNS=[pscustomobject]@{ Forwarders=@('192.0.2.53','192.0.2.54'); ForwarderReachability=@{ '192.0.2.53'=$true; '192.0.2.54'=$false }; ClientResolverReachability=@{ '10.40.1.11'=$true; '10.40.1.12'=$true; '10.40.2.11'=$true; '10.40.2.12'=$false }; ADIntegratedZone='corp.example'; ReverseZone='40.10.in-addr.arpa'; ConditionalForwarders=@('partners.example') }
        Time=[pscustomobject]@{ PDCSource='ntp-a.example'; PDCSourceReachable=$true; Hierarchy='PDC external, members domain hierarchy' }
        Thresholds=[pscustomobject]@{ DiskFreeGBReviewBelow=10; ReplicationMaterialLatencyMinutes=120; LifecycleReviewDays=120; ReadyScoreMinimum=90; ReviewScoreMinimum=75; Owner='Fictional organization assessment profile' }
    }
}

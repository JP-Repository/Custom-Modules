function New-PSIADLiveFixtureAdapter {
    <# .SYNOPSIS Fictional command adapter for offline validation. It never invokes AD, CIM, DNS, or network commands. #>
    [CmdletBinding()]
    param()
    @{
        Domain = { param($Name) [pscustomobject]@{ DNSRoot='lab.example.test'; Forest='example.test'; DomainMode='Windows2016Domain'; NetBIOSName='LAB'; DomainSID='S-1-5-21-100-200-300'; PDCEmulator='dc-a.lab.example.test'; RIDMaster='dc-a.lab.example.test'; InfrastructureMaster='dc-b.lab.example.test' } }
        Forest = { param($Name) [pscustomobject]@{ Name='example.test'; ForestMode='Windows2016Forest'; SchemaMaster='dc-a.lab.example.test'; DomainNamingMaster='dc-a.lab.example.test' } }
        DCs = { param($Name) if ($Name -ne 'lab.example.test') { throw 'Fixture domain mismatch' }; @(
            [pscustomobject]@{ HostName='dc-a.lab.example.test'; Domain='lab.example.test'; Site='North'; IPv4Address='192.0.2.11'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true },
            [pscustomobject]@{ HostName='dc-b.lab.example.test'; Domain='lab.example.test'; Site='South'; IPv4Address='192.0.2.12'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true },
            [pscustomobject]@{ HostName='dc-root.example.test'; Domain='example.test'; Site='Root'; IPv4Address='192.0.2.21'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true }
        ) }
        Sites = { param($Name) @([pscustomobject]@{ Name='North' },[pscustomobject]@{ Name='South' }) }
        Subnets = { param($Name) @([pscustomobject]@{ Name='192.0.2.0/25'; Site='North' },[pscustomobject]@{ Name='192.0.2.128/25'; Site='South' }) }
        SiteLinks = { param($Name) @([pscustomobject]@{ Name='North-South'; Cost=100; ReplicationFrequencyInMinutes=180; Schedule=$null }) }
        Partners = { param($HostName) if ($HostName -like 'dc-b*') { throw 'Fictional access denied' }; @([pscustomobject]@{ Partner='dc-b.lab.example.test'; Partition='DC=lab,DC=example,DC=test'; ConsecutiveReplicationFailures=0; LastReplicationSuccess=(Get-Date).AddMinutes(-12); LastReplicationResult=0 }) }
        Failures = { param($HostName) if ($HostName -like 'dc-b*') { throw 'Fictional access denied' }; @() }
        Remote = { param($HostName) if ($HostName -like 'dc-b*') { throw 'Fictional remote management blocked' }; [pscustomobject]@{ OS=[pscustomobject]@{ LastBootUpTime=(Get-Date).AddDays(-8) }; Disk=[pscustomobject]@{ FreeSpace=24GB; Size=100GB }; Services=@{ NTDS='Running'; Netlogon='Running'; DNS='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }; NICs=@([pscustomobject]@{ DNSServerSearchOrder=@('192.0.2.11','192.0.2.12') }) } }
        Shares = { param($HostName) if ($HostName -like 'dc-b*') { throw 'Fictional remote management blocked' }; @('SYSVOL','NETLOGON') }
        Time = { param($HostName) if ($HostName -like 'dc-b*') { throw 'Fictional w32tm timeout' }; 'time.lab.example.test' }
        DNS = { param($HostName) throw [System.NotSupportedException]::new('Fictional DNS module unavailable') }
    }
}

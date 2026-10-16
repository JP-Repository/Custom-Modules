function Get-PSIADReadOnlyAdapter {
    [CmdletBinding()]
    param()
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) { throw 'The ActiveDirectory module is required for live collection.' }
    Import-Module ActiveDirectory -ErrorAction Stop
    @{
        Domain = { param($Name) if ($Name) { Get-ADDomain -Identity $Name -Server $Name -ErrorAction Stop } else { Get-ADDomain -ErrorAction Stop } }
        Forest = { param($Name) Get-ADForest -Identity $Name -ErrorAction Stop }
        DCs = { param($Name) @(Get-ADDomainController -Filter * -Server $Name -ErrorAction Stop) }
        Sites = { param($Name) @(Get-ADReplicationSite -Filter * -Server $Name -ErrorAction Stop) }
        Subnets = { param($Name) @(Get-ADReplicationSubnet -Filter * -Server $Name -ErrorAction Stop) }
        SiteLinks = { param($Name) @(Get-ADReplicationSiteLink -Filter * -Server $Name -ErrorAction Stop) }
        Partners = { param($HostName) @(Get-ADReplicationPartnerMetadata -Target $HostName -Scope Server -Partition * -ErrorAction Stop) }
        Failures = { param($HostName) @(Get-ADReplicationFailure -Target $HostName -Scope Server -ErrorAction Stop) }
        Remote = {
            param($HostName)
            $OS=Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $HostName -ErrorAction Stop
            $Disk=@(Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $HostName -Filter 'DriveType=3' -ErrorAction Stop | Where-Object { $_.DeviceID -eq $OS.SystemDrive -or $_.DeviceID -eq 'C:' } | Select-Object -First 1)[0]
            $Services=@{}
            foreach ($Service in @(Get-CimInstance -ClassName Win32_Service -ComputerName $HostName -ErrorAction Stop | Where-Object { $_.Name -in @('NTDS','Netlogon','DNS','DFSR','KDC','W32Time') })) { $Services[$Service.Name]=[string]$Service.State }
            $NICs=@(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ComputerName $HostName -Filter 'IPEnabled=True' -ErrorAction Stop)
            [pscustomobject]@{ OS=$OS; Disk=$Disk; Services=$Services; NICs=$NICs }
        }
        Shares = { param($HostName) @(Get-CimInstance -ClassName Win32_Share -ComputerName $HostName -ErrorAction Stop | Where-Object { $_.Name -in @('SYSVOL','NETLOGON') } | Select-Object -ExpandProperty Name) }
        Time = { param($HostName) $Text=@(& w32tm /query /computer:$HostName /source 2>&1); if ($LASTEXITCODE -ne 0) { throw "w32tm query failed for $HostName" }; ($Text -join ' ').Trim() }
        DNS = {
            param($HostName)
            if (-not (Get-Module -ListAvailable -Name DnsServer)) { throw [System.NotSupportedException]::new('DnsServer module unavailable') }
            Import-Module DnsServer -ErrorAction Stop
            [pscustomobject]@{ Forwarders=@(Get-DnsServerForwarder -ComputerName $HostName -ErrorAction Stop | ForEach-Object { $_.IPAddress }); Zones=@(Get-DnsServerZone -ComputerName $HostName -ErrorAction Stop); Conditional=@(Get-DnsServerConditionalForwarderZone -ComputerName $HostName -ErrorAction Stop) }
        }
        Port = {
            param($HostName,$Port)
            $Client=[System.Net.Sockets.TcpClient]::new()
            try { $Async=$Client.BeginConnect($HostName,[int]$Port,$null,$null); if (-not $Async.AsyncWaitHandle.WaitOne(750)) { return $false }; $Client.EndConnect($Async); return $true }
            finally { $Client.Close() }
        }
        Security = {
            param($HostName)
            $Keys=@{
                'ldap-signing'=@('SYSTEM\CurrentControlSet\Services\NTDS\Parameters','LDAPServerIntegrity')
                'ldap-channel-binding'=@('SYSTEM\CurrentControlSet\Services\NTDS\Parameters','LdapEnforceChannelBinding')
                'ntlm'=@('SYSTEM\CurrentControlSet\Control\Lsa','LmCompatibilityLevel')
                'smb-signing'=@('SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters','RequireSecuritySignature')
            }
            $Values=@{}
            foreach ($Key in $Keys.Keys) {
                $Result=Invoke-CimMethod -ClassName StdRegProv -Namespace root/default -ComputerName $HostName -MethodName GetDWORDValue -Arguments @{ hDefKey=[uint32]2147483650; sSubKeyName=$Keys[$Key][0]; sValueName=$Keys[$Key][1] } -ErrorAction Stop
                $Values[$Key]=if ($Result.ReturnValue -eq 0) { "Observed registry DWORD: $($Result.uValue)" } elseif ($Result.ReturnValue -eq 2) { 'Not configured (registry value absent)' } else { "Unavailable (registry result $($Result.ReturnValue))" }
            }
            $Values
        }
        Dependencies = {
            param($Name)
            $Root=(Get-ADRootDSE -Server $Name -ErrorAction Stop).ConfigurationNamingContext
            $Exchange=@(); $CA=@(); $Errors=[System.Collections.Generic.List[string]]::new()
            try { $Exchange=@(Get-ADObject -SearchBase $Root -LDAPFilter '(objectClass=msExchExchangeServer)' -Properties serialNumber,adminDisplayVersion -Server $Name -ErrorAction Stop) }
            catch { $Errors.Add('Exchange directory query unavailable') }
            try { $CA=@(Get-ADObject -SearchBase $Root -LDAPFilter '(objectClass=pKIEnrollmentService)' -Properties dNSHostName -Server $Name -ErrorAction Stop) }
            catch { $Errors.Add('Enterprise CA directory query unavailable') }
            [pscustomobject]@{ Exchange=$Exchange; PKI=$CA; Errors=$Errors.ToArray() }
        }
    }
}

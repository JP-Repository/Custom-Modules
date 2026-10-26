function Invoke-PSIADTimedEventQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$LogName,
        [Parameter(Mandatory)][datetime]$StartTime,
        [ValidateRange(5,300)][int]$TimeoutSeconds = 30,
        [scriptblock]$QueryScriptBlock
    )
    if ($null -eq $QueryScriptBlock) {
        $QueryScriptBlock = {
            param($Computer, $Log, $Since)
            try {
                $Items = @(Get-WinEvent -ComputerName $Computer -FilterHashtable @{ LogName=$Log; StartTime=$Since } -MaxEvents 100 -ErrorAction Stop | ForEach-Object {
                    $Summary = ([string]$_.Message -replace '\s+', ' ').Trim()
                    if ($Summary.Length -gt 240) { $Summary = $Summary.Substring(0,240) }
                    [pscustomobject]@{ ProviderName=[string]$_.ProviderName; Id=[int]$_.Id; LevelDisplayName=[string]$_.LevelDisplayName; TimeCreated=[datetime]$_.TimeCreated; MessageSummary=$Summary }
                })
                [pscustomobject]@{ NoMatchingEvents=$false; Items=$Items }
            }
            catch {
                if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                    [pscustomobject]@{ NoMatchingEvents=$true; Items=@() }
                }
                else { throw }
            }
        }
    }
    $Job = $null
    try {
        $Job = Start-Job -ScriptBlock $QueryScriptBlock -ArgumentList @($HostName,$LogName,$StartTime) -ErrorAction Stop
        if ($null -eq (Wait-Job -Job $Job -Timeout $TimeoutSeconds -ErrorAction Stop)) {
            throw [System.TimeoutException]::new("Event log '$LogName' on $HostName exceeded $TimeoutSeconds seconds.")
        }
        $Response = @(Receive-Job -Job $Job -ErrorAction Stop)
        if ($Response.Count -ne 1) { throw [System.InvalidOperationException]::new("Event log '$LogName' returned no query result.") }
        $Response[0]
    }
    finally {
        if ($null -ne $Job) { Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue }
    }
}

function Get-PSIADReadOnlyAdapter {
    [CmdletBinding()]
    param()
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) { throw 'The ActiveDirectory module is required for live collection.' }
    Import-Module ActiveDirectory -ErrorAction Stop -Verbose:$false
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
            $Services=@{}; $ServiceDetails=@()
            foreach ($Service in @(Get-CimInstance -ClassName Win32_Service -ComputerName $HostName -ErrorAction Stop | Where-Object { $_.Name -in @('NTDS','Netlogon','DNS','DFSR','KDC','W32Time') })) {
                $Services[$Service.Name]=[string]$Service.State
                $ServiceDetails+= [pscustomobject]@{ Name=[string]$Service.Name; DisplayName=[string]$Service.DisplayName; State=[string]$Service.State; StartMode=[string]$Service.StartMode }
            }
            $NICs=@(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ComputerName $HostName -Filter 'IPEnabled=True' -ErrorAction Stop)
            [pscustomobject]@{ OS=$OS; Disk=$Disk; Services=$Services; ServiceDetails=$ServiceDetails; NICs=$NICs }
        }
        Cpu = { param($HostName) @(Get-CimInstance -ClassName Win32_Processor -ComputerName $HostName -ErrorAction Stop | Select-Object -ExpandProperty LoadPercentage) }
        Features = { param($HostName) @(Get-CimInstance -ClassName Win32_ServerFeature -ComputerName $HostName -ErrorAction Stop | Select-Object ID,Name) }
        Events = {
            param($HostName,$WindowHours,[int]$EventQueryTimeoutSeconds=30)
            $Start=(Get-Date).AddHours(-[int]$WindowHours)
            $Logs=@('Directory Service','DFS Replication','DNS Server','System')
            $Observations=@(); $Queries=@()
            foreach ($LogName in $Logs) {
                try {
                    Write-Verbose ("Querying event log '{0}' on {1} (timeout {2}s)" -f $LogName,$HostName,$EventQueryTimeoutSeconds)
                    $Response=Invoke-PSIADTimedEventQuery -HostName $HostName -LogName $LogName -StartTime $Start -TimeoutSeconds $EventQueryTimeoutSeconds
                    $Queries+= [pscustomobject]@{ Log=$LogName; State='Collected'; ErrorClass=''; Message=if ($Response.NoMatchingEvents) { 'No matching events' } else { '' } }
                    foreach ($Item in @($Response.Items)) {
                        $Category=switch ($LogName) { 'Directory Service' { 'DirectoryServices' }; 'DFS Replication' { 'DFSR' }; 'DNS Server' { 'DNS' }; default { 'System' } }
                        $Observations+= [pscustomobject]@{ DC=$HostName; Log=$LogName; Provider=[string]$Item.ProviderName; EventId=[int]$Item.Id; Level=[string]$Item.LevelDisplayName; Timestamp=[datetime]$Item.TimeCreated; MessageSummary=[string]$Item.MessageSummary; EvidenceCategory=$Category; CollectionState='Collected'; QueryWindowHours=[int]$WindowHours }
                    }
                } catch {
                    # Event ID 0 is returned by some hosts for an empty matching window.
                    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $Queries+= [pscustomobject]@{ Log=$LogName; State='Collected'; ErrorClass=''; Message='No matching events' } }
                    else { $Queries+= [pscustomobject]@{ Log=$LogName; State='Failed'; ErrorClass=(Resolve-PSIADCollectionError -ErrorRecord $_); Message=$_.Exception.Message } }
                }
            }
            [pscustomobject]@{ Observations=$Observations; Queries=$Queries }
        }
        Shares = { param($HostName) @(Get-CimInstance -ClassName Win32_Share -ComputerName $HostName -ErrorAction Stop | Where-Object { $_.Name -in @('SYSVOL','NETLOGON') } | Select-Object -ExpandProperty Name) }
        Time = { param($HostName) $Text=@(& w32tm /query /computer:$HostName /source 2>&1); if ($LASTEXITCODE -ne 0) { throw "w32tm query failed for $HostName" }; ($Text -join ' ').Trim() }
        DNS = {
            param($HostName)
            $Unavailable='DNS Server PowerShell management cmdlets are unavailable on the collector host.'
            if (-not (Get-Module -ListAvailable -Name DnsServer)) { throw [System.NotSupportedException]::new($Unavailable) }
            try { Import-Module DnsServer -ErrorAction Stop -Verbose:$false }
            catch { throw [System.NotSupportedException]::new($Unavailable) }
            foreach ($Name in @('Get-DnsServerForwarder','Get-DnsServerZone','Get-DnsServerConditionalForwarderZone')) {
                if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) { throw [System.NotSupportedException]::new($Unavailable) }
            }
            $States=@{}; $Errors=[System.Collections.Generic.List[string]]::new(); $Failures=[System.Collections.Generic.List[object]]::new()
            $Forwarders=@(); $Zones=@(); $Conditional=@()
            try { $Forwarders=@(Get-DnsServerForwarder -ComputerName $HostName -ErrorAction Stop | ForEach-Object { $_.IPAddress }); $States.Forwarders='Collected' }
            catch { $States.Forwarders='Failed'; $Errors.Add("Forwarders: $($_.Exception.Message)"); $Failures.Add($_.Exception) }
            try { $Zones=@(Get-DnsServerZone -ComputerName $HostName -ErrorAction Stop); $States.Zones='Collected' }
            catch { $States.Zones='Failed'; $Errors.Add("Zones: $($_.Exception.Message)"); $Failures.Add($_.Exception) }
            try { $Conditional=@(Get-DnsServerConditionalForwarderZone -ComputerName $HostName -ErrorAction Stop); $States.Conditional='Collected' }
            catch { $States.Conditional='Failed'; $Errors.Add("Conditional forwarders: $($_.Exception.Message)"); $Failures.Add($_.Exception) }
            if ($Failures.Count -eq 3) { throw $Failures[0] }
            [pscustomobject]@{ Forwarders=$Forwarders; Zones=$Zones; Conditional=$Conditional; QueryStates=$States; Errors=$Errors.ToArray(); CollectionMethod='Local DnsServer cmdlets targeting DC' }
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
        SecurityRuntime = { param($HostName,$WindowHours) Get-PSIADSecurityRuntimeFacts -HostName $HostName -WindowHours $WindowHours }
        Privileged = { param($Name,$Sid,$ForestRoot) Get-PSIADPrivilegedFacts -Domain $Name -DomainSid $Sid -ForestRoot $ForestRoot }
        GpoIntent = {
            param($Name,$ComputerDns)
            $Paths=@($ComputerDns | Where-Object { $_ -match '^[^,]+,(.+)$' } | ForEach-Object { ($_ -split ',',2)[1] } | Sort-Object -Unique)
            @($Paths | ForEach-Object {
                $Path=$_
                try {
                    $OU=Get-ADOrganizationalUnit -Identity $Path -Server $Name -Properties gPLink,gPOptions -ErrorAction Stop
                    [pscustomobject]@{ Domain=$Name; Container=$Path; GpLink=[string]$OU.gPLink; GpOptions=$OU.gPOptions; CollectionState='Collected'; SourceType='Directory'; Confidence='Low'; EffectivePolicyEstablished=$false; ErrorClass='' }
                } catch { [pscustomobject]@{ Domain=$Name; Container=$Path; GpLink=$null; GpOptions=$null; CollectionState='Failed'; SourceType='Directory'; Confidence='None'; EffectivePolicyEstablished=$false; ErrorClass=$_.Exception.GetType().Name } }
            })
        }
        Dependencies = {
            param($Name)
            $Root=(Get-ADRootDSE -Server $Name -ErrorAction Stop).ConfigurationNamingContext
            $Exchange=@(); $CA=@(); $Errors=[System.Collections.Generic.List[string]]::new()
            $ExchangeState='Failed'; $CAState='Failed'
            try { $Exchange=@(Get-ADObject -SearchBase $Root -LDAPFilter '(objectClass=msExchExchangeServer)' -Properties serialNumber,adminDisplayVersion -Server $Name -ErrorAction Stop); $ExchangeState='Collected' }
            catch { $Errors.Add("Exchange directory query unavailable ($($_.Exception.GetType().Name)): $($_.Exception.Message)") }
            try { $CA=@(Get-ADObject -SearchBase $Root -LDAPFilter '(objectClass=pKIEnrollmentService)' -Properties dNSHostName -Server $Name -ErrorAction Stop); $CAState='Collected' }
            catch { $Errors.Add("Enterprise CA directory query unavailable ($($_.Exception.GetType().Name)): $($_.Exception.Message)") }
            [pscustomobject]@{ Exchange=$Exchange; PKI=$CA; ExchangeQueryStatus=$ExchangeState; PKIQueryStatus=$CAState; Errors=$Errors.ToArray(); CollectionMethod='Configuration partition directory query'; Confidence='Directory objects only' }
        }
    }
}

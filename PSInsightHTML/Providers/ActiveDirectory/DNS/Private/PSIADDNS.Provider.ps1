function Resolve-PSIADDNSRules {
    [CmdletBinding()]
    param([Parameter()][hashtable] $Rules = @{})

    $Resolved = [ordered]@{ MinimumResolverCount = 2 }
    foreach ($Name in $Rules.Keys) {
        if ($Name -notin @($Resolved.Keys)) { throw "Unsupported DNS assessment rule '$Name'." }
        $Parsed = 0
        if (-not [int]::TryParse([string] $Rules[$Name], [ref] $Parsed) -or $Parsed -lt 1 -or $Parsed -gt 4) {
            throw "DNS assessment rule '$Name' must be a whole number from 1 to 4."
        }
        $Resolved[$Name] = $Parsed
    }
    return $Resolved
}

function New-PSIADDNSSampleData {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateRange(50, 60)][int] $DNSServerCount = 56,
        [Parameter()][hashtable] $Rules = @{},
        [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27)
    )

    $Policy = Resolve-PSIADDNSRules -Rules $Rules
    $Sites = @('North','South','East','West','Central','Coastal','Highland','Metro')
    $SiteCodes = @('NTH','STH','EST','WST','CTR','CST','HLD','MTR')
    $RootDomain = 'corp.example.invalid'
    $ChildDomain = 'branch.corp.example.invalid'
    $ExternalResolverCatalog = @('203.0.113.53','203.0.113.54')
    $InternalForwarderCatalog = @('198.51.100.210','198.51.100.211','198.51.100.212')
    $Servers = [System.Collections.Generic.List[object]]::new()
    $Resolvers = [System.Collections.Generic.List[object]]::new()
    $Zones = [System.Collections.Generic.List[object]]::new()
    $Forwarders = [System.Collections.Generic.List[object]]::new()
    $ConditionalForwarders = [System.Collections.Generic.List[object]]::new()

    for ($Index = 0; $Index -lt $DNSServerCount; $Index++) {
        $SiteIndex = $Index % $Sites.Count
        $Ordinal = [int] ([math]::Floor($Index / $Sites.Count) + 1)
        $Domain = if ($Index % 4 -eq 0) { $ChildDomain } else { $RootDomain }
        $Servers.Add([pscustomobject]@{
            ServerName = ('DNS-{0}-{1:D2}.{2}' -f $SiteCodes[$SiteIndex], $Ordinal, $Domain)
            Domain = $Domain
            Site = $Sites[$SiteIndex]
            IPv4Address = ('198.51.100.{0}' -f ($Index + 10))
            OperatingSystem = if ($Index % 3 -eq 0) { 'Windows Server 2022' } else { 'Windows Server 2019' }
            IsDomainController = 'Yes'
            DNSServiceState = if (($Index + 1) % 31 -eq 0) { 'Stopped' } else { 'Running' }
            ForwarderCount = 0
            ForwarderProfile = 'Not assessed'
            ZoneCount = 0
            ScavengingEnabled = if (($Index + 1) % 5 -eq 0) { 'No' } else { 'Yes' }
            ScavengingIntervalDays = $null
            ResolverCount = 0
            PublicResolverCount = 0
            UnrecognizedResolverCount = 0
            HasPublicResolver = 'No'
            HasMixedResolvers = 'No'
            HasDuplicateResolvers = 'No'
            BelowResolverMinimum = 'No'
            HasResolverObservation = 'No'
            ConfigurationState = 'Observed baseline'
        })
    }
    $KnownServerAddresses = @{}
    foreach ($Server in $Servers) { $KnownServerAddresses[$Server.IPv4Address] = $true }

    for ($Index = 1; $Index -le 24; $Index++) {
        $ZoneDomain = if ($Index % 4 -eq 2) { $ChildDomain } else { $RootDomain }
        $ZoneName = switch ($Index) {
            1 { $RootDomain }
            2 { $ChildDomain }
            3 { '_msdcs.corp.example.invalid' }
            4 { '100.51.198.in-addr.arpa' }
            5 { '2.0.192.in-addr.arpa' }
            14 { '113.0.203.in-addr.arpa' }
            default { 'zone{0:D2}.{1}' -f $Index, $ZoneDomain }
        }
        $ReverseLookup = if ($Index -in @(4,5,14)) { 'Yes' } else { 'No' }
        $ZoneType = if ($Index % 13 -eq 0) { 'Stub' } elseif ($Index % 9 -eq 0) { 'Secondary' } else { 'Primary' }
        $ADIntegrated = if ($ZoneType -eq 'Primary') { 'Yes' } else { 'No' }
        $Scope = if ($ADIntegrated -eq 'No') { 'Not applicable' } elseif ($Index -eq 3 -or $Index % 5 -eq 0) { 'Forest' } else { 'Domain' }
        $DynamicUpdate = if ($ADIntegrated -eq 'No' -or $Index % 11 -eq 0) { 'None' }
            elseif ($Index % 8 -eq 0) { 'Nonsecure and secure' }
            else { 'Secure only' }
        $AgingEnabled = if ($Index % 5 -eq 0) { 'No' } else { 'Yes' }
        $Zones.Add([pscustomobject]@{
            ZoneName = $ZoneName
            Domain = $ZoneDomain
            ZoneType = $ZoneType
            IsADIntegrated = $ADIntegrated
            ReplicationScope = $Scope
            DynamicUpdate = $DynamicUpdate
            AgingEnabled = $AgingEnabled
            NoRefreshIntervalDays = if ($AgingEnabled -eq 'Yes') { if ($Index % 6 -eq 0) { 14 } else { 7 } } else { $null }
            RefreshIntervalDays = if ($AgingEnabled -eq 'Yes') { 7 } else { $null }
            RecordCount = 250 + (($Index * 37) % 900)
            ReverseLookup = $ReverseLookup
            ZoneState = if ($Index % 17 -eq 0) { 'Paused' } else { 'Active' }
        })
    }

    for ($Index = 0; $Index -lt $DNSServerCount; $Index++) {
        $Server = $Servers[$Index]
        $ServerNumber = $Index + 1
        $LocalPeerIndex = if ($Index + 8 -lt $DNSServerCount) { $Index + 8 } else { $Index - 8 }
        $PeerAddress = $Servers[$LocalPeerIndex].IPv4Address
        $OtherPeerAddress = $Servers[($Index + 1) % $DNSServerCount].IPv4Address
        $ResolverAddresses = [System.Collections.Generic.List[string]]::new()
        if ($ServerNumber % 13 -ne 0) {
            $ResolverAddresses.Add($PeerAddress)
            if ($ServerNumber % 9 -ne 0) {
                if ($ServerNumber % 11 -eq 0) { $ResolverAddresses.Add($ExternalResolverCatalog[0]) }
                elseif ($ServerNumber % 17 -eq 0) { $ResolverAddresses.Add('198.51.100.240') }
                elseif ($ServerNumber % 19 -eq 0) { $ResolverAddresses.Add($PeerAddress) }
                elseif ($ServerNumber % 23 -eq 0) { $ResolverAddresses.Add($Server.IPv4Address) }
                elseif ($ServerNumber % 29 -eq 0) { $ResolverAddresses.Add('127.0.0.1') }
                else { $ResolverAddresses.Add($OtherPeerAddress) }
            }
            if ($ServerNumber % 7 -eq 0) { $ResolverAddresses.Add($Servers[($Index + 16) % $DNSServerCount].IPv4Address) }
        }
        for ($Order = 0; $Order -lt $ResolverAddresses.Count; $Order++) {
            $Address = $ResolverAddresses[$Order]
            $IsLoopback = $Address -eq '127.0.0.1'
            $IsSelf = $Address -eq $Server.IPv4Address -or $IsLoopback
            $IsExternal = $Address -in $ExternalResolverCatalog
            $IsKnownInternal = $KnownServerAddresses.ContainsKey($Address) -or $IsLoopback
            $ResolverType = if ($IsLoopback) { 'Loopback' }
                elseif ($IsSelf) { 'Self reference' }
                elseif ($IsExternal) { 'External sample' }
                elseif ($IsKnownInternal) { 'Internal peer' }
                else { 'Unrecognized' }
            $Resolvers.Add([pscustomobject]@{
                ServerName = $Server.ServerName
                Site = $Server.Site
                Interface = 'Ethernet0'
                ResolverOrder = $Order + 1
                ResolverAddress = $Address
                ResolverType = $ResolverType
                IsInternalResolver = if ($IsKnownInternal) { 'Yes' } else { 'No' }
                IsPublicResolver = if ($IsExternal) { 'Yes' } else { 'No' }
                IsSelfReference = if ($IsSelf) { 'Yes' } else { 'No' }
                IsLoopback = if ($IsLoopback) { 'Yes' } else { 'No' }
                ResolutionState = if ($IsExternal) { 'External sample' } elseif ($ResolverType -eq 'Unrecognized') { 'Unrecognized' } else { 'Known internal' }
            })
        }
        $ServerResolvers = @($Resolvers | Where-Object ServerName -eq $Server.ServerName)
        $Server.ResolverCount = $ServerResolvers.Count
        $Server.PublicResolverCount = @($ServerResolvers | Where-Object IsPublicResolver -eq 'Yes').Count
        $Server.UnrecognizedResolverCount = @($ServerResolvers | Where-Object ResolutionState -eq 'Unrecognized').Count
        $InternalCount = @($ServerResolvers | Where-Object IsInternalResolver -eq 'Yes').Count
        $Server.HasPublicResolver = if ($Server.PublicResolverCount -gt 0) { 'Yes' } else { 'No' }
        $Server.HasMixedResolvers = if ($Server.PublicResolverCount -gt 0 -and $InternalCount -gt 0) { 'Yes' } else { 'No' }
        $Server.HasDuplicateResolvers = if (@($ServerResolvers.ResolverAddress | Group-Object | Where-Object Count -gt 1).Count -gt 0) { 'Yes' } else { 'No' }
        $Server.BelowResolverMinimum = if ($Server.ResolverCount -lt $Policy.MinimumResolverCount) { 'Yes' } else { 'No' }

        $ForwarderAddresses = [System.Collections.Generic.List[string]]::new()
        $ForwarderAddresses.Add($InternalForwarderCatalog[0])
        if ($ServerNumber % 8 -ne 0) {
            if ($ServerNumber % 10 -eq 0) { $ForwarderAddresses.Add('203.0.113.54') }
            elseif ($ServerNumber % 17 -eq 0) { $ForwarderAddresses.Add($InternalForwarderCatalog[2]) }
            else { $ForwarderAddresses.Add($InternalForwarderCatalog[1]) }
        }
        for ($ForwarderIndex = 0; $ForwarderIndex -lt $ForwarderAddresses.Count; $ForwarderIndex++) {
            $Address = $ForwarderAddresses[$ForwarderIndex]
            $Internal = $Address -in $InternalForwarderCatalog
            $Forwarders.Add([pscustomobject]@{
                ServerName = $Server.ServerName
                Site = $Server.Site
                ForwarderOrder = $ForwarderIndex + 1
                ForwarderAddress = $Address
                ForwarderType = if ($Internal) { 'Internal sample' } else { 'External sample' }
                IsInternal = if ($Internal) { 'Yes' } else { 'No' }
                IsPublic = if ($Internal) { 'No' } else { 'Yes' }
                TimeoutSeconds = if ($ServerNumber % 6 -eq 0) { 5 } else { 3 }
                UseRootHintsIfUnavailable = if ($ServerNumber % 6 -eq 0) { 'No' } else { 'Yes' }
            })
        }
        $Server.ForwarderCount = $ForwarderAddresses.Count
        $Server.ForwarderProfile = if ($ForwarderAddresses.Count -eq 1) { 'Single internal sample' }
            elseif ($ForwarderAddresses[1] -eq '203.0.113.54') { 'Includes external sample' }
            elseif ($ForwarderAddresses[1] -eq $InternalForwarderCatalog[2]) { 'Alternate internal sample' }
            else { 'Standard internal sample' }
        if ($Server.ScavengingEnabled -eq 'Yes') { $Server.ScavengingIntervalDays = if ($ServerNumber % 6 -eq 0) { 14 } else { 7 } }
        $Server.ZoneCount = @($Zones | Where-Object {
            $_.IsADIntegrated -eq 'Yes' -and ($_.ReplicationScope -eq 'Forest' -or ($_.ReplicationScope -eq 'Domain' -and $_.Domain -eq $Server.Domain))
        }).Count
        $Server.HasResolverObservation = if ($Server.BelowResolverMinimum -eq 'Yes' -or $Server.HasPublicResolver -eq 'Yes' -or
            $Server.UnrecognizedResolverCount -gt 0 -or $Server.HasDuplicateResolvers -eq 'Yes') { 'Yes' } else { 'No' }
        $Server.ConfigurationState = if ($Server.HasResolverObservation -eq 'Yes' -or $Server.DNSServiceState -ne 'Running') { 'Review candidate' } else { 'Observed baseline' }
    }

    $ConditionalZones = @('partners.example.invalid','vendor.example.invalid','legacy.example.invalid','research.example.invalid','branch-links.example.invalid','archive.example.invalid')
    for ($ZoneIndex = 0; $ZoneIndex -lt $ConditionalZones.Count; $ZoneIndex++) {
        $MasterAddresses = @('198.51.100.220','198.51.100.221')
        if ($ZoneIndex -in @(1,4)) { $MasterAddresses = @('198.51.100.220','203.0.113.60') }
        foreach ($MasterAddress in $MasterAddresses) {
            $StoredInAD = if (($ZoneIndex + 1) % 3 -eq 0) { 'No' } else { 'Yes' }
            $ConditionalForwarders.Add([pscustomobject]@{
                ZoneName = $ConditionalZones[$ZoneIndex]
                MasterServer = $MasterAddress
                ReplicationScope = if ($StoredInAD -eq 'No') { 'Not applicable' } elseif ($ZoneIndex % 2 -eq 0) { 'Forest' } else { 'Domain' }
                StoredInAD = $StoredInAD
                MasterType = if ($MasterAddress -eq '203.0.113.60') { 'External sample' } else { 'Internal sample' }
                ForwarderState = if ($MasterAddress -eq '203.0.113.60') { 'Review candidate' } else { 'Configured' }
                TargetVerification = 'Not checked'
            })
        }
    }

    [pscustomobject]@{
        Source = 'Deterministic fictional AD DNS sample; no live directory or DNS connection.'
        AsOfDate = $AsOfDate
        Rules = $Policy
        DNSServerInventory = $Servers.ToArray()
        DNSClientResolvers = $Resolvers.ToArray()
        DNSZones = $Zones.ToArray()
        DNSForwarders = $Forwarders.ToArray()
        DNSConditionalForwarders = $ConditionalForwarders.ToArray()
        ExternalSampleResolverAddresses = $ExternalResolverCatalog
        InternalForwarderSampleAddresses = $InternalForwarderCatalog
    }
}

function Get-PSIADDNSDistribution {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]] $Data, [Parameter(Mandatory = $true)][string] $Property)
    @($Data | Group-Object -Property $Property | Sort-Object -Property Name | ForEach-Object {
        [pscustomobject]@{ Category = [string] $_.Name; Count = [int] $_.Count }
    })
}

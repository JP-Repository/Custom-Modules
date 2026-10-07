function ConvertTo-PSIADIPv4Number {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Address)

    $Parts = $Address.Split('.')
    if ($Parts.Count -ne 4) { throw "Invalid IPv4 address: $Address" }
    $Octets = @()
    foreach ($Part in $Parts) {
        if ($Part -notmatch '^(0|[1-9][0-9]{0,2})$') { throw "Invalid IPv4 address: $Address" }
        $Octet = [int] $Part
        if ($Octet -gt 255) { throw "Invalid IPv4 address: $Address" }
        $Octets += $Octet
    }
    return [uint64] ($Octets[0] * 16777216L + $Octets[1] * 65536L + $Octets[2] * 256L + $Octets[3])
}

function ConvertFrom-PSIADIPv4Number {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uint64] $Number)
    if ($Number -gt 4294967295) { throw 'IPv4 number exceeds 32 bits.' }
    return ('{0}.{1}.{2}.{3}' -f [int](($Number -shr 24) -band 255), [int](($Number -shr 16) -band 255), [int](($Number -shr 8) -band 255), [int]($Number -band 255))
}

function ConvertTo-PSIADSubnetDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $CIDR,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $SiteName,
        [Parameter()][string] $Description = ''
    )
    if ($CIDR -notmatch '^([^/]+)/([0-9]{1,2})$') { throw "Invalid IPv4 CIDR: $CIDR" }
    $Address = ConvertTo-PSIADIPv4Number -Address $Matches[1]
    $Prefix = [int] $Matches[2]
    if ($Prefix -gt 32) { throw "Invalid IPv4 CIDR prefix: $CIDR" }
    $HostCount = [uint64] [math]::Pow(2, (32 - $Prefix))
    $Mask = [uint64] (4294967296 - $HostCount)
    $Network = [uint64] ($Address -band $Mask)
    $Last = [uint64] ($Network + $HostCount - 1)
    [pscustomobject]@{
        SubnetCIDR = ('{0}/{1}' -f (ConvertFrom-PSIADIPv4Number -Number $Network), $Prefix)
        NetworkAddress = ConvertFrom-PSIADIPv4Number -Number $Network
        PrefixLength = $Prefix
        SiteName = $SiteName
        Description = $Description
        RangeStart = $Network
        RangeEnd = $Last
    }
}

function Find-PSIADBestSubnetMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $IPv4Address,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Subnets
    )
    $Number = ConvertTo-PSIADIPv4Number -Address $IPv4Address
    $Candidates = @($Subnets | Where-Object { $Number -ge $_.RangeStart -and $Number -le $_.RangeEnd } |
        Sort-Object @{ Expression = 'PrefixLength'; Descending = $true }, SubnetCIDR, SiteName)
    $Best = $null
    $Ambiguous = $false
    if ($Candidates.Count -gt 0) {
        $Best = $Candidates[0]
        $BestSites = @($Candidates | Where-Object PrefixLength -eq $Best.PrefixLength | Select-Object -ExpandProperty SiteName -Unique)
        $Ambiguous = $BestSites.Count -gt 1
    }
    [pscustomobject]@{ Best = $Best; MatchingCount = $Candidates.Count; IsAmbiguous = $Ambiguous; Candidates = $Candidates }
}

function Get-PSIADSubnetOverlaps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Subnets)
    for ($Left = 0; $Left -lt $Subnets.Count; $Left++) {
        for ($Right = $Left + 1; $Right -lt $Subnets.Count; $Right++) {
            $A = $Subnets[$Left]; $B = $Subnets[$Right]
            if ($A.RangeStart -le $B.RangeEnd -and $B.RangeStart -le $A.RangeEnd) {
                $CrossSite = $A.SiteName -ne $B.SiteName
                $Kind = if ($A.RangeStart -eq $B.RangeStart -and $A.RangeEnd -eq $B.RangeEnd) { 'Identical range' }
                    elseif ($CrossSite) { 'Cross-site containment' } else { 'Same-site containment' }
                [pscustomobject]@{
                    SubnetA = $A.SubnetCIDR; SubnetB = $B.SubnetCIDR
                    SiteA = $A.SiteName; SiteB = $B.SiteName
                    PrefixA = $A.PrefixLength; PrefixB = $B.PrefixLength
                    OverlapType = $Kind; CrossSite = if ($CrossSite) { 'Yes' } else { 'No' }
                }
            }
        }
    }
}

function Get-PSIADSitesSubnetsDistribution {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]] $Data, [Parameter(Mandatory)][string] $Property)
    @($Data | Group-Object -Property $Property | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Category = [string] $_.Name; Count = [int] $_.Count }
    })
}

function New-PSIADSitesSubnetsSampleData {
    [CmdletBinding()]
    param([Parameter()][hashtable] $Rules = @{})
    $Policy = @{ ExpectedMinimumDCsPerSite = 1; HighSiteLinkCostThreshold = 200; LongReplicationIntervalMinutes = 180 }
    foreach ($Key in $Rules.Keys) {
        if (-not $Policy.ContainsKey($Key)) { throw "Unknown Sites/Subnets rule: $Key" }
        if ($Rules[$Key] -isnot [int] -or $Rules[$Key] -lt 1) { throw "Rule $Key must be a positive integer." }
        $Policy[$Key] = $Rules[$Key]
    }
    $SiteDefinitions = @(
        [pscustomobject]@{Name='North';Code='NTH';Region='Americas';DCs=12},
        [pscustomobject]@{Name='South';Code='STH';Region='Americas';DCs=10},
        [pscustomobject]@{Name='East';Code='EST';Region='Europe';DCs=9},
        [pscustomobject]@{Name='West';Code='WST';Region='Europe';DCs=8},
        [pscustomobject]@{Name='Central';Code='CTR';Region='Asia Pacific';DCs=8},
        [pscustomobject]@{Name='Coastal';Code='CST';Region='Asia Pacific';DCs=8},
        [pscustomobject]@{Name='Highland';Code='HLD';Region='Americas';DCs=1},
        [pscustomobject]@{Name='Metro';Code='MTR';Region='Europe';DCs=0}
    )
    $Definitions = [System.Collections.Generic.List[object]]::new()
    for ($SiteIndex = 0; $SiteIndex -lt $SiteDefinitions.Count; $SiteIndex++) {
        for ($Slot = 0; $Slot -lt 7; $Slot++) {
            $CIDR = '10.77.{0}.{1}/28' -f $SiteIndex, ($Slot * 16)
            $Definitions.Add((ConvertTo-PSIADSubnetDefinition -CIDR $CIDR -SiteName $SiteDefinitions[$SiteIndex].Name -Description 'Fictional site subnet'))
        }
    }
    $Definitions.Add((ConvertTo-PSIADSubnetDefinition -CIDR '10.77.0.0/25' -SiteName 'South' -Description 'Broad cross-site example'))
    $Definitions.Add((ConvertTo-PSIADSubnetDefinition -CIDR '10.77.2.0/29' -SiteName 'West' -Description 'More-specific cross-site example'))
    $Definitions.Add((ConvertTo-PSIADSubnetDefinition -CIDR '10.77.4.0/25' -SiteName 'Central' -Description 'Broad same-site example'))
    $Definitions.Add((ConvertTo-PSIADSubnetDefinition -CIDR '10.77.3.32/27' -SiteName 'West' -Description 'Same-site example'))
    $Overlaps = @(Get-PSIADSubnetOverlaps -Subnets $Definitions.ToArray())
    $DCAddresses = [System.Collections.Generic.List[object]]::new()
    for ($SiteIndex = 0; $SiteIndex -lt $SiteDefinitions.Count; $SiteIndex++) {
        $Site = $SiteDefinitions[$SiteIndex]
        for ($Ordinal = 1; $Ordinal -le $Site.DCs; $Ordinal++) {
            $Slot = ($Ordinal - 1) % 7
            $HostNumber = 1 + [int][math]::Floor(($Ordinal - 1) / 7)
            $IP = '10.77.{0}.{1}' -f $SiteIndex, (($Slot * 16) + $HostNumber)
            if ($Site.Name -eq 'South' -and $Ordinal -eq 3) { $IP = '10.77.0.34' }
            if ($Site.Name -eq 'Coastal' -and $Ordinal -eq 8) { $IP = '10.77.200.10' }
            $DCAddresses.Add([pscustomobject]@{
                DCName = ('DC-{0}-{1:D2}.corp.example.invalid' -f $Site.Code, $Ordinal)
                IPv4Address = $IP; ConfiguredSite = $Site.Name
            })
        }
    }
    $Placement = @($DCAddresses | ForEach-Object {
        $DC = $_
        $Match = Find-PSIADBestSubnetMatch -IPv4Address $DC.IPv4Address -Subnets $Definitions.ToArray()
        $Best = $Match.Best
        $Assignment = if (-not $Best) { 'NoSubnetMatch' }
            elseif ($Match.IsAmbiguous) { 'AmbiguousMatch' }
            elseif ($Best.SiteName -ne $DC.ConfiguredSite) { 'SiteMismatch' }
            else { 'Matched' }
        [pscustomobject]@{
            DCName = $DC.DCName; IPv4Address = $DC.IPv4Address; ConfiguredSite = $DC.ConfiguredSite
            MatchedSubnet = if ($Best) { $Best.SubnetCIDR } else { $null }
            MatchedSubnetSite = if ($Best) { $Best.SiteName } else { $null }
            MatchPrefixLength = if ($Best) { $Best.PrefixLength } else { $null }
            SiteAssignmentState = $Assignment; MatchingSubnetCount = $Match.MatchingCount
        }
    })
    $SubnetInventory = @($Definitions | ForEach-Object {
        $Subnet = $_
        $Related = @($Overlaps | Where-Object { $_.SubnetA -eq $Subnet.SubnetCIDR -and $_.SiteA -eq $Subnet.SiteName -or $_.SubnetB -eq $Subnet.SubnetCIDR -and $_.SiteB -eq $Subnet.SiteName })
        $Observed = @($DCAddresses | Where-Object { $Number = ConvertTo-PSIADIPv4Number -Address $_.IPv4Address; $Number -ge $Subnet.RangeStart -and $Number -le $Subnet.RangeEnd }).Count
        [pscustomobject]@{
            SubnetCIDR = $Subnet.SubnetCIDR; NetworkAddress = $Subnet.NetworkAddress; PrefixLength = $Subnet.PrefixLength
            SiteName = $Subnet.SiteName; Description = $Subnet.Description; ObservedDCCount = $Observed
            OverlapState = if ($Related.Count -gt 0) { 'Overlap candidate' } else { 'None' }
            CrossSiteOverlap = if (@($Related | Where-Object CrossSite -eq 'Yes').Count -gt 0) { 'Yes' } else { 'No' }
            CoverageState = if ($Observed -gt 0) { 'DC address observed' } else { 'No DC address observed' }
        }
    })
    $LinkDefinitions = @(
        [pscustomobject]@{Name='LINK-AMER-EAST';Sites=@('North','South','East');Cost=100;Interval=60;Schedule='Always available'},
        [pscustomobject]@{Name='LINK-WEST-CENTRAL';Sites=@('West','Central','North');Cost=150;Interval=90;Schedule='Always available'},
        [pscustomobject]@{Name='LINK-COASTAL-CENTRAL';Sites=@('Coastal','Central','North');Cost=250;Interval=180;Schedule='Windowed sample'},
        [pscustomobject]@{Name='LINK-SOUTH-WEST';Sites=@('South','West','Central');Cost=300;Interval=240;Schedule='Windowed sample'},
        [pscustomobject]@{Name='LINK-EAST-COASTAL';Sites=@('East','Coastal','South');Cost=120;Interval=120;Schedule='Always available'},
        [pscustomobject]@{Name='LINK-REGIONAL-ALTERNATE';Sites=@('South','West','East');Cost=80;Interval=240;Schedule='Windowed sample'}
    )
    $Membership = @($LinkDefinitions | ForEach-Object {
        $Link = $_
        foreach ($SiteName in $Link.Sites) {
            $Region = ($SiteDefinitions | Where-Object Name -eq $SiteName | Select-Object -First 1).Region
            [pscustomobject]@{ SiteLinkName = $Link.Name; SiteName = $SiteName; Region = $Region }
        }
    })
    $Links = @($LinkDefinitions | ForEach-Object {
        $Link = $_
        [pscustomobject]@{
            SiteLinkName = $Link.Name; Transport = 'IP'; SiteCount = $Link.Sites.Count; Cost = $Link.Cost
            ReplicationIntervalMinutes = $Link.Interval; ScheduleState = $Link.Schedule; Options = 'Default sample options'
            CostBand = if ($Link.Cost -ge $Policy.HighSiteLinkCostThreshold) { 'At or above threshold' } else { 'Below threshold' }
            IntervalBand = if ($Link.Interval -ge $Policy.LongReplicationIntervalMinutes) { 'At or above threshold' } else { 'Below threshold' }
            TopologyState = if ($Link.Cost -ge $Policy.HighSiteLinkCostThreshold -or $Link.Interval -ge $Policy.LongReplicationIntervalMinutes) { 'Review candidate' } else { 'Configured' }
        }
    })
    $Sites = @($SiteDefinitions | ForEach-Object {
        $Site = $_
        $DCCount = @($Placement | Where-Object ConfiguredSite -eq $Site.Name).Count
        $LinkCount = @($Membership | Where-Object SiteName -eq $Site.Name).Count
        [pscustomobject]@{
            SiteName = $Site.Name; Description = ('Fictional {0} location' -f $Site.Region); Region = $Site.Region
            DomainControllerCount = $DCCount; SubnetCount = @($SubnetInventory | Where-Object SiteName -eq $Site.Name).Count
            SiteLinkCount = $LinkCount; HasDomainController = if ($DCCount -gt 0) { 'Yes' } else { 'No' }
            HasSiteLink = if ($LinkCount -gt 0) { 'Yes' } else { 'No' }
            TopologyState = if ($DCCount -lt $Policy.ExpectedMinimumDCsPerSite -or $LinkCount -eq 0) { 'Review candidate' } else { 'Configured' }
        }
    })
    [pscustomobject]@{
        Source = 'Fictional sample data only; no live directory connection.'
        Rules = $Policy
        SiteInventory = $Sites
        SubnetInventory = $SubnetInventory
        DomainControllerPlacement = $Placement
        SiteLinkInventory = $Links
        SubnetOverlapEvidence = $Overlaps
        SiteLinkMembership = $Membership
    }
}

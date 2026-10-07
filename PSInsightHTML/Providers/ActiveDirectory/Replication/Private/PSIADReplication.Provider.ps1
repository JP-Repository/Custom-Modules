function Resolve-PSIADReplicationThresholds {
    [CmdletBinding()]
    param([Parameter()][hashtable] $Thresholds = @{})

    $Resolved = [ordered]@{
        WarningReplicationAgeMinutes = 60
        CriticalReplicationAgeMinutes = 180
        ConsecutiveFailureThreshold = 3
        MultipleFailingPartnerThreshold = 2
    }
    foreach ($Name in $Thresholds.Keys) {
        if ($Name -notin @($Resolved.Keys)) { throw "Unsupported replication assessment threshold '$Name'." }
        $Parsed = 0
        if (-not [int]::TryParse([string] $Thresholds[$Name], [ref] $Parsed) -or $Parsed -lt 1) {
            throw "Replication assessment threshold '$Name' must be a positive whole number."
        }
        $Resolved[$Name] = $Parsed
    }
    if ($Resolved.CriticalReplicationAgeMinutes -le $Resolved.WarningReplicationAgeMinutes) {
        throw 'CriticalReplicationAgeMinutes must be greater than WarningReplicationAgeMinutes.'
    }
    if ($Resolved.MultipleFailingPartnerThreshold -lt 2) {
        throw 'MultipleFailingPartnerThreshold must be at least 2.'
    }
    return $Resolved
}

function Get-PSIADReplicationAgeBucket {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][Nullable[int]] $AgeMinutes)
    if ($null -eq $AgeMinutes) { return 'Never successful' }
    if ($AgeMinutes -le 15) { return '0-15 min' }
    if ($AgeMinutes -le 60) { return '16-60 min' }
    if ($AgeMinutes -le 180) { return '61-180 min' }
    if ($AgeMinutes -le 360) { return '181-360 min' }
    return '361+ min'
}

function Get-PSIADReplicationState {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][Nullable[int]] $AgeMinutes,
        [Parameter(Mandatory = $true)][int] $LastResultCode,
        [Parameter(Mandatory = $true)][int] $ConsecutiveFailures,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary] $Thresholds
    )
    if ($LastResultCode -ne 0 -and $ConsecutiveFailures -ge $Thresholds.ConsecutiveFailureThreshold) { return 'Critical' }
    if ($null -eq $AgeMinutes) { return 'Unknown' }
    if ($AgeMinutes -ge $Thresholds.CriticalReplicationAgeMinutes) { return 'Critical' }
    if ($LastResultCode -ne 0 -or $AgeMinutes -ge $Thresholds.WarningReplicationAgeMinutes) { return 'Warning' }
    return 'Healthy'
}

function New-PSIADReplicationSampleData {
    [CmdletBinding()]
    param(
        [Parameter()][ValidateRange(50, 60)][int] $DomainControllerCount = 56,
        [Parameter()][hashtable] $Thresholds = @{},
        [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27, 12, 0, 0)
    )

    $Rules = Resolve-PSIADReplicationThresholds -Thresholds $Thresholds
    $SiteNames = @('North', 'South', 'East', 'West', 'Central', 'Coastal', 'Highland', 'Metro')
    $SiteCodes = @('NTH', 'STH', 'EST', 'WST', 'CTR', 'CST', 'HLD', 'MTR')
    $NamingContexts = @(
        [pscustomobject]@{ Label='Domain'; Name='DC=corp,DC=example,DC=invalid' },
        [pscustomobject]@{ Label='Configuration'; Name='CN=Configuration,DC=corp,DC=example,DC=invalid' },
        [pscustomobject]@{ Label='Schema'; Name='CN=Schema,CN=Configuration,DC=corp,DC=example,DC=invalid' },
        [pscustomobject]@{ Label='Domain DNS zones'; Name='DC=DomainDnsZones,DC=corp,DC=example,DC=invalid' }
    )
    $Dcs = [System.Collections.Generic.List[object]]::new()
    $Relationships = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()

    for ($Index = 0; $Index -lt $DomainControllerCount; $Index++) {
        $SiteIndex = $Index % $SiteNames.Count
        $SiteOrdinal = [int] ([math]::Floor($Index / $SiteNames.Count) + 1)
        $Dcs.Add([pscustomobject]@{
            DCName = ('DC-{0}-{1:D2}.corp.example.invalid' -f $SiteCodes[$SiteIndex], $SiteOrdinal)
            Site = $SiteNames[$SiteIndex]
            Domain = 'corp.example.invalid'
            OperatingSystem = if ($Index % 3 -eq 0) { 'Windows Server 2022' } else { 'Windows Server 2019' }
            IPv4Address = '198.51.100.{0}' -f ($Index + 10)
            InboundPartnerCount = 0
            OutboundPartnerCount = 0
            FailingPartnerCount = 0
            WorstReplicationAgeMinutes = $null
            UnknownRelationshipCount = 0
            ReplicationState = 'Unknown'
            MultipleFailingPartners = 'No'
        })
    }

    for ($DestinationIndex = 0; $DestinationIndex -lt $DomainControllerCount; $DestinationIndex++) {
        $Destination = $Dcs[$DestinationIndex]
        $LocalPartnerIndex = if ($DestinationIndex + 8 -lt $DomainControllerCount) { $DestinationIndex + 8 } else { $DestinationIndex - 8 }
        $PartnerIndices = @($LocalPartnerIndex, (($DestinationIndex + 1) % $DomainControllerCount), (($DestinationIndex + 13) % $DomainControllerCount))
        for ($PartnerOrdinal = 0; $PartnerOrdinal -lt $PartnerIndices.Count; $PartnerOrdinal++) {
            $Source = $Dcs[$PartnerIndices[$PartnerOrdinal]]
            foreach ($Context in $NamingContexts) {
                $RecordIndex = $Relationships.Count + 1
                $Scenario = 'Healthy'
                if ($DestinationIndex -in @(5, 18, 42) -and $PartnerOrdinal -lt 2 -and $Context.Label -eq 'Domain') { $Scenario = 'RPC' }
                elseif ($RecordIndex % 101 -eq 0) { $Scenario = 'NeverSuccessful' }
                elseif ($RecordIndex % 71 -eq 0) { $Scenario = 'Recovered' }
                elseif ($RecordIndex % 83 -eq 0) { $Scenario = 'StaleSuccess' }
                elseif ($RecordIndex % 37 -eq 0) { $Scenario = 'RPC' }
                elseif ($RecordIndex % 47 -eq 0) { $Scenario = 'Access' }
                elseif ($RecordIndex % 53 -eq 0) { $Scenario = 'DNS' }
                elseif ($RecordIndex % 61 -eq 0) { $Scenario = 'PartnerUnavailable' }
                elseif ($RecordIndex % 29 -eq 0) { $Scenario = 'Delayed' }

                $Age = $null
                $ResultCode = 0
                $ResultMessage = 'The last replication attempt completed successfully.'
                $Failures = 0
                $PreviousFailures = 0
                $PartnerAvailability = 'Not assessed'
                $ErrorCategory = 'None'
                switch ($Scenario) {
                    'RPC' { $Age = 190 + ($RecordIndex % 120); $ResultCode = 1722; $ResultMessage = 'The RPC server is unavailable.'; $Failures = 3 + ($RecordIndex % 3); $ErrorCategory = 'RPC' }
                    'Access' { $Age = 70 + ($RecordIndex % 80); $ResultCode = 8453; $ResultMessage = 'Replication access was denied.'; $Failures = 1 + ($RecordIndex % 2); $ErrorCategory = 'Access' }
                    'DNS' { $Age = 140 + ($RecordIndex % 80); $ResultCode = 8524; $ResultMessage = 'The DSA operation cannot proceed because of a DNS lookup failure.'; $Failures = 3; $ErrorCategory = 'DNS' }
                    'PartnerUnavailable' { $Age = 190 + ($RecordIndex % 60); $ResultCode = 1722; $ResultMessage = 'The RPC server is unavailable.'; $Failures = 3; $PartnerAvailability = 'Unavailable in sample'; $ErrorCategory = 'RPC' }
                    'NeverSuccessful' { $ResultCode = 8524; $ResultMessage = 'The DSA operation cannot proceed because of a DNS lookup failure.'; $Failures = 1; $ErrorCategory = 'DNS' }
                    'Recovered' { $Age = 5 + ($RecordIndex % 10); $PreviousFailures = 2 + ($RecordIndex % 2); $ResultMessage = 'Successful after earlier fictional failures.' }
                    'StaleSuccess' { $Age = 200 + ($RecordIndex % 90) }
                    'Delayed' { $Age = 65 + ($RecordIndex % 90) }
                    default { $Age = 5 + ($RecordIndex % 35) }
                }
                $LastSuccessDate = if ($null -eq $Age) { $null } else { $AsOfDate.AddMinutes(-$Age) }
                $LastAttemptDate = if ($ResultCode -eq 0) { $LastSuccessDate } else { $AsOfDate.AddMinutes(-(2 + ($RecordIndex % 10))) }
                $State = Get-PSIADReplicationState -AgeMinutes $Age -LastResultCode $ResultCode -ConsecutiveFailures $Failures -Thresholds $Rules
                $LinkType = if ($Source.Site -eq $Destination.Site) { 'Intra-site' } else { 'Inter-site' }
                $Row = [pscustomobject]@{
                    SourceDC = $Source.DCName
                    DestinationDC = $Destination.DCName
                    SourceSite = $Source.Site
                    DestinationSite = $Destination.Site
                    NamingContext = $Context.Name
                    NamingContextLabel = $Context.Label
                    LastAttempt = if ($null -eq $LastAttemptDate) { $null } else { $LastAttemptDate.ToString('yyyy-MM-dd HH:mm') }
                    LastSuccess = if ($null -eq $LastSuccessDate) { $null } else { $LastSuccessDate.ToString('yyyy-MM-dd HH:mm') }
                    ReplicationAgeMinutes = $Age
                    ConsecutiveFailures = $Failures
                    PreviousFailureCount = $PreviousFailures
                    LastResultCode = $ResultCode
                    LastResultMessage = $ResultMessage
                    ReplicationState = $State
                    AgeBucket = Get-PSIADReplicationAgeBucket -AgeMinutes $Age
                    LinkType = $LinkType
                    Transport = 'RPC'
                    IsFailure = if ($ResultCode -eq 0) { 'No' } else { 'Yes' }
                    CriticalAge = if ($null -ne $Age -and $Age -ge $Rules.CriticalReplicationAgeMinutes) { 'Yes' } else { 'No' }
                    RecoveryState = if ($PreviousFailures -gt 0) { 'Recovered' } else { 'Not observed' }
                    PartnerAvailability = $PartnerAvailability
                    ErrorCategory = $ErrorCategory
                }
                $Relationships.Add($Row)
                if ($ResultCode -ne 0) {
                    $Errors.Add([pscustomobject]@{
                        SourceDC = $Row.SourceDC
                        DestinationDC = $Row.DestinationDC
                        SourceSite = $Row.SourceSite
                        DestinationSite = $Row.DestinationSite
                        NamingContext = $Row.NamingContext
                        ErrorCode = $Row.LastResultCode
                        ErrorMessage = $Row.LastResultMessage
                        ErrorCategory = $Row.ErrorCategory
                        ConsecutiveFailures = $Row.ConsecutiveFailures
                        LastAttempt = $Row.LastAttempt
                        LastSuccess = $Row.LastSuccess
                        PartnerAvailability = $Row.PartnerAvailability
                    })
                }
            }
        }
    }

    foreach ($Dc in $Dcs) {
        $Inbound = @($Relationships | Where-Object DestinationDC -eq $Dc.DCName)
        $Outbound = @($Relationships | Where-Object SourceDC -eq $Dc.DCName)
        $FailingInbound = @($Inbound | Where-Object IsFailure -eq 'Yes')
        $KnownAges = @($Inbound | Where-Object { $null -ne $_.ReplicationAgeMinutes } | Select-Object -ExpandProperty ReplicationAgeMinutes)
        $Dc.InboundPartnerCount = @($Inbound.SourceDC | Sort-Object -Unique).Count
        $Dc.OutboundPartnerCount = @($Outbound.DestinationDC | Sort-Object -Unique).Count
        $Dc.FailingPartnerCount = @($FailingInbound.SourceDC | Sort-Object -Unique).Count
        $Dc.UnknownRelationshipCount = @($Inbound | Where-Object ReplicationState -eq 'Unknown').Count
        if ($KnownAges.Count -gt 0) { $Dc.WorstReplicationAgeMinutes = [int] ($KnownAges | Measure-Object -Maximum).Maximum }
        $Dc.ReplicationState = if (@($Inbound | Where-Object ReplicationState -eq 'Critical').Count -gt 0) { 'Critical' }
            elseif (@($Inbound | Where-Object ReplicationState -eq 'Warning').Count -gt 0) { 'Warning' }
            elseif ($Dc.UnknownRelationshipCount -gt 0) { 'Unknown' }
            else { 'Healthy' }
        $Dc.MultipleFailingPartners = if ($Dc.FailingPartnerCount -ge $Rules.MultipleFailingPartnerThreshold) { 'Yes' } else { 'No' }
    }

    $SiteSummary = [System.Collections.Generic.List[object]]::new()
    foreach ($SiteName in $SiteNames) {
        $SiteDcs = @($Dcs | Where-Object Site -eq $SiteName)
        $SiteRows = @($Relationships | Where-Object DestinationSite -eq $SiteName)
        $KnownAges = @($SiteRows | Where-Object { $null -ne $_.ReplicationAgeMinutes } | Select-Object -ExpandProperty ReplicationAgeMinutes)
        $SiteSummary.Add([pscustomobject]@{
            SiteName = $SiteName
            DomainControllerCount = $SiteDcs.Count
            ReplicationRelationshipCount = $SiteRows.Count
            HealthyCount = @($SiteRows | Where-Object ReplicationState -eq 'Healthy').Count
            WarningCount = @($SiteRows | Where-Object ReplicationState -eq 'Warning').Count
            CriticalCount = @($SiteRows | Where-Object ReplicationState -eq 'Critical').Count
            UnknownCount = @($SiteRows | Where-Object ReplicationState -eq 'Unknown').Count
            FailureCount = @($SiteRows | Where-Object IsFailure -eq 'Yes').Count
            WorstReplicationAgeMinutes = if ($KnownAges.Count -gt 0) { [int] ($KnownAges | Measure-Object -Maximum).Maximum } else { $null }
        })
    }

    [pscustomobject]@{
        Source = 'Deterministic fictional AD replication sample; no live directory connection.'
        AsOfDate = $AsOfDate
        Thresholds = $Rules
        DomainControllerInventory = $Dcs.ToArray()
        ReplicationRelationships = $Relationships.ToArray()
        ReplicationErrors = $Errors.ToArray()
        SiteReplicationSummary = $SiteSummary.ToArray()
    }
}

function Get-PSIADReplicationDistribution {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]] $Data, [Parameter(Mandatory = $true)][string] $Property)
    @($Data | Group-Object -Property $Property | Sort-Object -Property Name | ForEach-Object {
        [pscustomobject]@{ Category = [string] $_.Name; Count = [int] $_.Count }
    })
}

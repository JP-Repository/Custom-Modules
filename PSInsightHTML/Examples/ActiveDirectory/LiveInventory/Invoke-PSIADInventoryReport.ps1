<#
.SYNOPSIS
    Build one read-only AD inventory report using a scoped live query, a supplied snapshot, or fictional sample data.
.DESCRIPTION
    These examples are observational inventories, not health assessments. Generic HTML rendering stays in PSInsightHTML.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Groups','GroupPolicy','Users','Computers','OUs','DNS','Replication','SitesSubnets')]
    [string] $ReportType,
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')]
    [string] $CollectionProfile,
    [ValidateRange(1,50000)][int] $MaxObjects = 2000,
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force -ErrorAction Stop -Verbose:$false
. (Join-Path $PSScriptRoot 'Get-PSIADInventoryAdapter.ps1')
. (Join-Path $PSScriptRoot 'New-PSIADInventoryFixture.ps1')
. (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')

$SnapshotType = $ReportType -in @('DNS','Replication','SitesSubnets')
if ($UseSampleData -and ($null -ne $Snapshot -or -not [string]::IsNullOrWhiteSpace($Domain))) { throw 'UseSampleData cannot be combined with Snapshot or Domain.' }
if ($null -ne $Snapshot -and -not $SnapshotType) { throw "Snapshot is supported only for DNS, Replication, and SitesSubnets reports." }
if ($null -ne $Snapshot -and -not [string]::IsNullOrWhiteSpace($Domain)) { throw 'Snapshot and Domain are mutually exclusive.' }
if (-not $UseSampleData -and $null -eq $Snapshot -and [string]::IsNullOrWhiteSpace($Domain)) { throw 'Specify -UseSampleData, a normalized -Snapshot, or an explicit -Domain.' }
if ([string]::IsNullOrWhiteSpace($CollectionProfile)) { $CollectionProfile = if ($ReportType -eq 'DNS') { 'Operational' } else { 'Core' } }

$Truncated = $false
$Raw = @()
if ($SnapshotType) {
    if ($null -eq $Snapshot) {
        Write-Verbose ("Collecting {0} snapshot for {1} inventory" -f $CollectionProfile,$ReportType)
        $RawSnapshot = Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile $CollectionProfile -CommandAdapter $CommandAdapter -Verbose:([bool]$PSBoundParameters['Verbose'])
        $Snapshot = ConvertTo-PSIADDCReadinessModel -InputObject $RawSnapshot
    }
    $Inventory = New-PSIADDCInventoryModel -Snapshot $Snapshot
    $DomainName = [string] $Inventory.Summary.Domain
    $Sample = $Snapshot.Source -eq 'Fictional sample'
}
else {
    if ($UseSampleData) {
        $DomainName = 'corp.example'
        $Raw = @(New-PSIADInventoryFixture -ReportType $ReportType)
        $Sample = $true
    }
    else {
        $Adapter = if ($null -ne $CommandAdapter) { $CommandAdapter } else { Get-PSIADInventoryAdapter }
        if (-not $Adapter.ContainsKey('Domain') -or -not $Adapter.ContainsKey($ReportType)) { throw "CommandAdapter requires Domain and $ReportType queries." }
        Write-Verbose ("Resolving domain {0} for {1} inventory" -f $Domain,$ReportType)
        $DomainResult = & $Adapter.Domain $Domain
        if ($null -eq $DomainResult -or [string] $DomainResult.DNSRoot -ne $Domain) { throw "Resolved domain does not match requested domain '$Domain'." }
        $DomainName = [string] $DomainResult.DNSRoot
        Write-Verbose ("Querying {0} in {1} (display limit {2})" -f $ReportType,$DomainName,$MaxObjects)
        $Raw = @(& $Adapter[$ReportType] $DomainName $MaxObjects)
        $Truncated = $Raw.Count -gt $MaxObjects
        if ($Truncated) { $Raw = @($Raw | Select-Object -First $MaxObjects) }
        Write-Verbose ("{0} inventory: {1} records displayed; truncated: {2}" -f $ReportType,$Raw.Count,$Truncated)
        $Sample = $false
    }
}

$Records = [System.Collections.Generic.List[object]]::new()
$Columns = @()
$CategoryLabel = 'Category'
$CategoryProperty = 'Category'
$Description = 'Observed directory objects. No health verdict is inferred from inventory values.'
switch ($ReportType) {
    'Groups' {
        $CategoryProperty = 'GroupScope'
        $Columns = @('Name','SamAccountName','GroupScope','GroupCategory','Description')
        $CategoryLabel = 'Group scope'
        foreach ($Item in $Raw) { $Records.Add([pscustomobject]@{ Name=[string]$Item.Name; SamAccountName=[string]$Item.SamAccountName; GroupScope=[string]$Item.GroupScope; GroupCategory=[string]$Item.GroupCategory; Description=[string]$Item.Description; Category=[string]$Item.GroupScope }) }
        $Description = 'Group metadata only. Membership, nesting, privileges and effective access are not inferred.'
    }
    'GroupPolicy' {
        $CategoryProperty = 'GpoStatus'
        $Columns = @('DisplayName','Id','GpoStatus','CreationTime','ModificationTime','Owner')
        $CategoryLabel = 'GPO configuration state'
        foreach ($Item in $Raw) { $Records.Add([pscustomobject]@{ DisplayName=[string]$Item.DisplayName; Id=[string]$Item.Id; GpoStatus=[string]$Item.GpoStatus; CreationTime=$Item.CreationTime; ModificationTime=$Item.ModificationTime; Owner=[string]$Item.Owner; Category=[string]$Item.GpoStatus }) }
        $Description = 'GPO object metadata only. Link scope, applied settings and effective policy are not established.'
    }
    'Users' {
        $CategoryProperty = 'AccountState'
        $Columns = @('Name','SamAccountName','AccountState','Department','EmployeeType','Country','LastLogonDate','PasswordLastSet','AccountExpirationDate','PasswordNeverExpires')
        $CategoryLabel = 'Account state'
        foreach ($Item in $Raw) { $State = if ($null -eq $Item.Enabled) { 'Unknown' } elseif ($Item.Enabled) { 'Enabled' } else { 'Disabled' }; $Records.Add([pscustomobject]@{ Name=[string]$Item.Name; SamAccountName=[string]$Item.SamAccountName; AccountState=$State; Department=[string]$Item.Department; EmployeeType=[string]$Item.EmployeeType; Country=[string]$Item.Country; LastLogonDate=$Item.LastLogonDate; PasswordLastSet=$Item.PasswordLastSet; AccountExpirationDate=$Item.AccountExpirationDate; PasswordNeverExpires=$Item.PasswordNeverExpires; Category=$State }) }
        $Description = 'LastLogonDate is an approximate replicated timestamp. Blank dates are unknown; no inactivity or password finding is inferred.'
    }
    'Computers' {
        $CategoryProperty = 'AccountState'
        $Columns = @('Name','DNSHostName','AccountState','OperatingSystem','OperatingSystemVersion','LastLogonDate','Location')
        $CategoryLabel = 'Account state'
        foreach ($Item in $Raw) { $State = if ($null -eq $Item.Enabled) { 'Unknown' } elseif ($Item.Enabled) { 'Enabled' } else { 'Disabled' }; $Records.Add([pscustomobject]@{ Name=[string]$Item.Name; DNSHostName=[string]$Item.DNSHostName; AccountState=$State; OperatingSystem=[string]$Item.OperatingSystem; OperatingSystemVersion=[string]$Item.OperatingSystemVersion; LastLogonDate=$Item.LastLogonDate; Location=[string]$Item.Location; Category=$State }) }
        $Description = 'Computer account attributes are directory observations; they do not prove host reachability or patch state.'
    }
    'OUs' {
        $CategoryProperty = 'Protected'
        $Columns = @('Name','DistinguishedName','Protected','LinkedGpoCount','BlockInheritance')
        $CategoryLabel = 'Accidental deletion protection'
        foreach ($Item in $Raw) {
            $Protected = if ($null -eq $Item.ProtectedFromAccidentalDeletion) { 'Unknown' } elseif ($Item.ProtectedFromAccidentalDeletion) { 'Yes' } else { 'No' }
            $LinkCount = [regex]::Matches([string]$Item.gPLink,'\[LDAP://',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
            $Block = if ($null -eq $Item.gPOptions) { $null } else { ([int]$Item.gPOptions -band 1) -eq 1 }
            $Records.Add([pscustomobject]@{ Name=[string]$Item.Name; DistinguishedName=[string]$Item.DistinguishedName; Protected=$Protected; LinkedGpoCount=$LinkCount; BlockInheritance=$Block; Category=$Protected })
        }
        $Description = 'Link count reflects direct gPLink metadata only; effective GPO inheritance is not evaluated.'
    }
    'DNS' {
        $CategoryProperty = 'RecordType'
        $Columns = @('RecordType','DomainController','Name','Detail','CollectionState')
        $CategoryLabel = 'DNS observation type'
        foreach ($DC in @($Snapshot.DomainControllers)) {
            $DnsResult = @($Snapshot.CollectionResults | Where-Object { $_.CollectorId -eq 'DNS' -and $_.Scope -eq $DC.Name } | Select-Object -First 1)
            $State = if ($Sample) { 'FictionalSample' } elseif ($DnsResult.Count) { [string]$DnsResult[0].Status } else { 'NotRequested' }
            foreach ($Zone in @($DC.DNSZones)) { $Records.Add([pscustomobject]@{ RecordType='Zone'; DomainController=[string]$DC.Name; Name=[string]$Zone.Name; Detail="AD integrated: $($Zone.IsDsIntegrated)"; CollectionState=$State; Category='Zone' }) }
            foreach ($Forwarder in @($DC.DNSForwarders | Where-Object { $_ })) { $Records.Add([pscustomobject]@{ RecordType='Forwarder'; DomainController=[string]$DC.Name; Name=[string]$Forwarder; Detail='Configured forwarder'; CollectionState=$State; Category='Forwarder' }) }
            foreach ($Conditional in @($DC.ConditionalForwarders | Where-Object { $_ })) { $Records.Add([pscustomobject]@{ RecordType='Conditional forwarder'; DomainController=[string]$DC.Name; Name=[string]$Conditional; Detail='Configured conditional forwarder'; CollectionState=$State; Category='Conditional forwarder' }) }
            if ($State -notin @('Collected','FictionalSample') -and @($DC.DNSZones).Count -eq 0 -and @($DC.DNSForwarders).Count -eq 0) { $Records.Add([pscustomobject]@{ RecordType='Query state'; DomainController=[string]$DC.Name; Name='DNS Server'; Detail='No DNS Server configuration was observed'; CollectionState=$State; Category='Query state' }) }
        }
        $Description = 'DNS Server observations require the Operational collection profile and DnsServer tooling. Unavailable queries are shown, not treated as empty configuration.'
    }
    'Replication' {
        $CategoryProperty = 'ObservationState'
        $Columns = @('Source','Destination','NamingContext','LastSuccess','CurrentFailures','LastResult','ObservationState')
        $CategoryLabel = 'Observed failures'
        foreach ($Item in @($Inventory.Replication)) { $State = if ($null -eq $Item.CurrentFailures) { 'Unknown' } elseif ($Item.CurrentFailures -gt 0) { 'Failures observed' } else { 'No current failures reported' }; $Records.Add([pscustomobject]@{ Source=[string]$Item.Source; Destination=[string]$Item.Destination; NamingContext=[string]$Item.NamingContext; LastSuccess=$Item.LastSuccess; CurrentFailures=$Item.CurrentFailures; LastResult=$Item.LastResult; ObservationState=$State; Category=$State }) }
        $Description = 'Partner metadata is an observation at collection time; zero returned links is not proof of healthy replication. External sources remain evidence-only.'
    }
    'SitesSubnets' {
        $CategoryProperty = 'RecordType'
        $Columns = @('RecordType','Name','Site','Detail','CollectionState')
        $CategoryLabel = 'Topology object type'
        foreach ($Site in @($Inventory.Sites)) { $Records.Add([pscustomobject]@{ RecordType='Site'; Name=[string]$Site.Name; Site=[string]$Site.Name; Detail='Observed DC site'; CollectionState=if ($Sample) { 'FictionalSample' } else { 'Collected' }; Category='Site' }) }
        foreach ($Subnet in @($Inventory.Subnets)) { $Records.Add([pscustomobject]@{ RecordType='Subnet'; Name=[string]$Subnet.Name; Site=[string]$Subnet.Site; Detail='Mapped subnet'; CollectionState=if ($Sample) { 'FictionalSample' } else { 'Collected' }; Category='Subnet' }) }
        foreach ($Link in @($Inventory.SiteLinks)) { $Records.Add([pscustomobject]@{ RecordType='Site link'; Name=[string]$Link.Name; Site=''; Detail=(@($Link.Sites) -join ', '); CollectionState=[string]$Inventory.SiteLinkCollectionState; Category='Site link' }) }
        $Description = 'Sites, mapped subnets and site links are directory topology observations; this is not a connectivity or topology health verdict.'
    }
}
$Rows = $Records.ToArray()
$Distribution = @($Rows | Group-Object -Property $CategoryProperty | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Category=if ($_.Name) { $_.Name } else { 'Not supplied' }; Count=$_.Count } })
$Filters = @()
$FilterValues = @($Rows | ForEach-Object { $_.$CategoryProperty } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
if ($FilterValues.Count) { $Filters = @(Add-PSIFilter -Property $CategoryProperty -Values $FilterValues -Label $CategoryLabel) }
$SourceLabel = if ($Sample) { 'Fictional sample - no directory query' } elseif ($null -ne $Snapshot -and -not $Domain) { 'Supplied normalized snapshot' } else { 'Read-only domain-scoped collection' }
$Report = New-PSIReport -Title "AD $ReportType Inventory | $DomainName" -Subtitle $SourceLabel -Theme $Theme -Layout Application
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue @{ ReportIdentity=@{ Kicker="PSInsightHTML / AD $ReportType inventory" }; Scope=$DomainName; Profile=if ($SnapshotType) { $Snapshot.CollectionProfile } else { 'Directory' }; Tables=@('ad-inventory','ad-collection') }
$CountLabel = if ($Truncated) { 'Displayed records (limit reached)' } else { 'Observed records' }
$null = $Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Scope and observed distribution' -Icon NavigationHome -Initial |
    Add-PSISection -Title "$ReportType at a glance" |
    Add-PSIRow |
    Add-PSIStatus -Status Informational -Label $SourceLabel -Message $Description |
    Add-PSIRow |
    Add-PSIKPI -Title $CountLabel -Value $Rows.Count -Subtitle $DomainName -Status Informational -Icon Document |
    Add-PSIKPI -Title 'Categories' -Value $Distribution.Count -Subtitle $CategoryLabel -Status Informational -Icon Relationship |
    Add-PSIRow |
    Add-PSIChart -Title "Observed $CategoryLabel distribution" -ChartType Bar -Data $Distribution -CategoryProperty Category -ValueProperty Count -FilterMetadata @{ Table='ad-inventory'; Property=$CategoryProperty; ValueProperty='Category' }
$null = $Report |
    Add-PSIView -Id inventory -Title 'Inventory' -Subtitle 'Search, filter and sort observed records' -Icon Document -Badge $Rows.Count |
    Add-PSISection -Title "$ReportType register" |
    Add-PSIRow |
    Add-PSITable -Id ad-inventory -Title "$ReportType observations" -Data $Rows -Columns $Columns -Filters $Filters -PageSize 25 -EmptyMessage 'No records were returned for this scope or filter.'
$Coverage = if ($SnapshotType) { @($Snapshot.CollectionCoverage.Collectors | ForEach-Object { [pscustomobject]@{ Collector=$_.Collector; CollectionState=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent } }) }
else { @([pscustomobject]@{ Collector=$ReportType; CollectionState=if ($Sample) { 'FictionalSample' } else { 'Collected' }; Expected=if ($Truncated) { 'More than displayed' } else { $Rows.Count }; Collected=$Rows.Count; CoveragePercent=if ($Truncated) { $null } else { 100 } }) }
$CoverageMessage = if ($Truncated) { "The query reached MaxObjects=$MaxObjects. Counts and charts describe displayed records only; total directory count is unknown." } elseif ($SnapshotType) { 'Collection coverage is completeness, not health. NotRequested, Failed and NotSupported are not healthy results.' } else { 'The requested directory query completed. Counts describe returned records only.' }
$null = $Report |
    Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Collection status and scope limits' -Icon Document |
    Add-PSISection -Title 'Evidence and limits' |
    Add-PSIRow |
    Add-PSIText -Text $CoverageMessage -Size Small |
    Add-PSIRow |
    Add-PSITable -Id ad-collection -Title 'Collection outcomes' -Data $Coverage -Columns @('Collector','CollectionState','Expected','Collected','CoveragePercent')

if (-not $OutputPath) { $OutputPath = Join-Path $ModuleRoot 'Reports/ADLiveInventory' }
if (-not $Sample) { $OutputPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd-HHmmss') }
$null = New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath = Join-Path $OutputPath "AD-$ReportType.html"
$null = Export-PSIReport -Report $Report -Path $HtmlPath -Renderer Fluent
if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath }
        elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath }
    } catch { Write-Warning "Report generated, but browser opening failed: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ ReportType=$ReportType; Domain=$DomainName; Snapshot=$Snapshot; Records=$Rows; Truncated=$Truncated; Report=$Report; HtmlPath=$HtmlPath } }
else { $HtmlPath }

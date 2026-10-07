[CmdletBinding()]
param(
    [Parameter()]
    [switch] $NoBrowser,

    [Parameter()]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force -ErrorAction Stop

$Report = New-PSIReport `
    -Title 'Active Directory Infrastructure Assessment' `
    -Subtitle 'Enterprise Directory Services - Sample Environment' `
    -Theme Auto

$SampleSites = @('North', 'Coastal', 'Central', 'South')
$ControllerInventory = @(
    for ($Index = 1; $Index -le 57; $Index++) {
        $Site = $SampleSites[($Index - 1) % $SampleSites.Count]
        $ControllerStatus = if ($Index -le 49) { 'Healthy' } elseif ($Index -le 54) { 'Warning' } else { 'Unknown' }
        [pscustomobject]@{
            Name       = 'DC-{0}-{1:D2}' -f $Site.ToUpperInvariant(), [int] [math]::Ceiling($Index / $SampleSites.Count)
            Site       = $Site
            IPv4       = '198.51.100.{0}' -f $Index
            Status     = $ControllerStatus
            NtpSource  = if ($Index % 2 -eq 0) { 'time-a.corp.example' } else { 'time-b.corp.example' }
            LastCheck  = '{0} min ago' -f (1 + ($Index % 12))
        }
    }
)
$HealthyControllers = @($ControllerInventory | Where-Object { $_.Status -eq 'Healthy' })
$WarningControllerCount = @($ControllerInventory | Where-Object { $_.Status -eq 'Warning' }).Count
$UnknownControllerCount = @($ControllerInventory | Where-Object { $_.Status -eq 'Unknown' }).Count
$HealthyControllerCount = $HealthyControllers.Count
$ControllerStatusDistribution = @(
    [pscustomobject]@{ Health = 'Healthy'; Count = $HealthyControllerCount }
    [pscustomobject]@{ Health = 'Warning'; Count = $WarningControllerCount }
    [pscustomobject]@{ Health = 'Unknown'; Count = $UnknownControllerCount }
)
$ControllerSiteDistribution = @(
    $ControllerInventory | Group-Object -Property Site | ForEach-Object {
        [pscustomobject]@{ Site = $_.Name; Count = $_.Count }
    }
)
$ControllerStatusFilter = Add-PSIFilter -Property 'Status' -Label 'Status' -Values @($ControllerInventory | Select-Object -ExpandProperty Status -Unique)
$ControllerSiteFilter = Add-PSIFilter -Property 'Site' -Label 'Site' -Values @($ControllerInventory | Select-Object -ExpandProperty Site -Unique)
$ReplicationErrorRecords = @(
    [pscustomobject]@{ Source = 'DC-NORTH-01'; Destination = 'DC-CENTRAL-02'; Site = 'North → Central'; ErrorCode = 1722; Status = 'Critical'; LastAttempt = '4 min ago'; Details = 'Sample RPC endpoint unavailable during the last attempt.' }
    [pscustomobject]@{ Source = 'DC-COASTAL-03'; Destination = 'DC-SOUTH-01'; Site = 'Coastal → South'; ErrorCode = 58; Status = 'Critical'; LastAttempt = '7 min ago'; Details = 'Sample directory service rejected the request.' }
    [pscustomobject]@{ Source = 'DC-CENTRAL-02'; Destination = 'DC-NORTH-04'; Site = 'Central → North'; ErrorCode = 1722; Status = 'Critical'; LastAttempt = '9 min ago'; Details = 'Sample RPC endpoint unavailable during the last attempt.' }
    [pscustomobject]@{ Source = 'DC-SOUTH-01'; Destination = 'DC-COASTAL-02'; Site = 'South → Coastal'; ErrorCode = 58; Status = 'Critical'; LastAttempt = '12 min ago'; Details = 'Sample directory service rejected the request.' }
    [pscustomobject]@{ Source = 'DC-NORTH-05'; Destination = 'DC-CENTRAL-01'; Site = 'North → Central'; ErrorCode = 1722; Status = 'Critical'; LastAttempt = '15 min ago'; Details = 'Sample RPC endpoint unavailable during the last attempt.' }
)
$DnsIssueRecords = @(
    [pscustomobject]@{ Resource = 'app.corp.example'; Site = 'North'; Issue = 'Lookup response exceeded sample latency threshold'; Status = 'Warning'; Resolver = '198.51.100.12' }
    [pscustomobject]@{ Resource = 'files.corp.example'; Site = 'Coastal'; Issue = 'One sample resolver returned a stale record'; Status = 'Warning'; Resolver = '198.51.100.24' }
    [pscustomobject]@{ Resource = 'api.corp.example'; Site = 'Central'; Issue = 'Forward lookup check did not return an answer'; Status = 'Warning'; Resolver = '198.51.100.36' }
)

# Visual benchmark: fictional assessment data, with no directory or network access.
$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Total Users' -Value '21,703' -Status Informational -Span 3 -Icon 'users' -Subtitle 'Synthetic account inventory' |
    Add-PSIKPI -Title 'Enabled Users' -Value '5,787' -Status Informational -Span 3 -Icon 'healthy' -Subtitle '26.7% of sample accounts' |
    Add-PSIKPI -Title 'Disabled Users' -Value '15,916' -Status Neutral -Span 3 -Icon 'users' -Subtitle '73.3% of sample accounts' |
    Add-PSIKPI -Title 'Locked Users' -Value '4,008' -Status Warning -Span 3 -Icon 'warning' -Subtitle 'Illustrative snapshot; review context' |
    Add-PSIKPI -Title 'Password Never Expires' -Value '1,511' -Status Warning -Span 3 -Icon 'security' -Subtitle 'Sample configuration count' |
    Add-PSIKPI -Title 'Total Groups' -Value '7,546' -Status Informational -Span 3 -Icon 'domain' -Subtitle 'Including built-in groups' -Action @{ Type = 'ScrollTo'; Target = 'psi-section-3' } |
    Add-PSIKPI -Title 'Domain Admins' -Value 7 -Status Informational -Span 3 -Icon 'security' -Subtitle 'Synthetic direct members' |
    Add-PSIKPI -Title 'Security Findings' -Value 7 -Status Critical -Span 3 -Icon 'critical' -Subtitle 'Illustrative findings, not live results'

$null = $Report |
    Add-PSISection -Title 'Environment Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIKeyValue -Title 'Directory identity' -Span 6 -Data ([ordered]@{
        Domain = 'corp.example.com'
        Forest = 'example.com'
        'Domain Functional Level' = 'Windows2016Domain'
        'Forest Functional Level' = 'Windows2016Forest'
    }) |
    Add-PSIKeyValue -Title 'Topology footprint' -Span 6 -Data ([ordered]@{
        Sites = 53
        'Domain Controllers' = 57
        'Global Catalog Servers' = 57
        'FSMO Role Holders' = 3
    })

$null = $Report |
    Add-PSISection -Title 'Domain Statistics' |
    Add-PSIRow -Columns 12 |
    Add-PSIKeyValue -Title 'User Account Statistics' -Span 6 -Data ([ordered]@{
        'Total User Accounts' = '21,703'
        Enabled = '5,787'
        Disabled = '15,916'
        Locked = '4,008'
        'Password Does Not Expire' = '1,511'
        'Password Must Change' = 9
    }) |
    Add-PSIKeyValue -Title 'User Security Statistics' -Span 6 -Data ([ordered]@{
        'Password Not Required' = 0
        'Dial-in Enabled' = 339
        'Control Access With NPS' = '21,287'
        'Unconstrained Delegation' = 10
        'Not Trusted For Delegation' = 10
        'No Pre-Auth Required' = 0
    })

$null = $Report |
    Add-PSISection -Title 'Group Statistics' |
    Add-PSIRow -Columns 12 |
    Add-PSIKeyValue -Title 'Group Inventory' -Span 6 -Data ([ordered]@{
        'Total Groups' = '7,546'
        'Built-in' = 27
        'Universal Security' = '3,272'
        'Universal Distribution' = 246
        'Global Security' = '3,936'
    }) |
    Add-PSIKeyValue -Title 'Group Scope and Distribution' -Span 6 -Data ([ordered]@{
        'Global Distribution' = 1
        'Domain Local Security' = 63
        'Domain Local Distribution' = 0
        'Other / Unclassified' = 1
    })

$PrivilegedGroups = @(
    [pscustomobject]@{ DefaultName = 'Account Operators'; CurrentName = 'Account Operators'; MemberCount = 5; Status = 'Informational' }
    [pscustomobject]@{ DefaultName = 'Backup Operators'; CurrentName = 'Backup Operators'; MemberCount = 7; Status = 'Informational' }
    [pscustomobject]@{ DefaultName = 'Print Operators'; CurrentName = 'Print Operators'; MemberCount = 0; Status = 'Neutral' }
    [pscustomobject]@{ DefaultName = 'Server Operators'; CurrentName = 'Server Operators'; MemberCount = 1; Status = 'Informational' }
    [pscustomobject]@{ DefaultName = 'Domain Admins'; CurrentName = 'Domain Admins'; MemberCount = 7; Status = 'Informational' }
    [pscustomobject]@{ DefaultName = 'Cert Publishers'; CurrentName = 'Cert Publishers'; MemberCount = 0; Status = 'Neutral' }
    [pscustomobject]@{ DefaultName = 'Administrators'; CurrentName = 'Administrators'; MemberCount = 7; Status = 'Informational' }
)
$null = $Report |
    Add-PSISection -Title 'Privileged Group Statistics' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Title 'Privileged Group Membership Summary' -Data $PrivilegedGroups -Span 12 `
        -Columns @('DefaultName', 'CurrentName', 'MemberCount', 'Status') `
        -ColumnLabels @{ DefaultName = 'Default Name'; CurrentName = 'Current Name'; MemberCount = 'Member Count' } `
        -EnableSearch $false -EnableSorting $true -EnablePagination $false -EnableExport $false

$DomainAdministrators = @(
    [pscustomobject]@{ LogonID = 'admin.user01'; Name = 'Sample Administrator 01'; PasswordAgeDays = 202; LastLoggedIn = '2026-10-03 09:20'; PasswordNeverExpires = $false; PasswordReversible = $false; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user02'; Name = 'Sample Administrator 02'; PasswordAgeDays = 201; LastLoggedIn = '2026-09-29 16:45'; PasswordNeverExpires = $false; PasswordReversible = $false; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user03'; Name = 'Sample Administrator 03'; PasswordAgeDays = 152; LastLoggedIn = '2026-10-02 11:10'; PasswordNeverExpires = $false; PasswordReversible = $false; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user04'; Name = 'Sample Administrator 04'; PasswordAgeDays = 80; LastLoggedIn = '2026-10-05 08:35'; PasswordNeverExpires = $false; PasswordReversible = $false; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user05'; Name = 'Sample Administrator 05'; PasswordAgeDays = 77; LastLoggedIn = '2026-10-01 13:55'; PasswordNeverExpires = $true; PasswordReversible = $false; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user06'; Name = 'Sample Administrator 06'; PasswordAgeDays = 63; LastLoggedIn = '2026-10-06 10:15'; PasswordNeverExpires = $false; PasswordReversible = $true; PasswordNotRequired = $false }
    [pscustomobject]@{ LogonID = 'admin.user07'; Name = 'Sample Administrator 07'; PasswordAgeDays = 40; LastLoggedIn = '2026-10-07 07:40'; PasswordNeverExpires = $false; PasswordReversible = $false; PasswordNotRequired = $true }
)
$AdministratorConditions = @(
    New-PSICondition -Property PasswordAgeDays -Operator GreaterThan -Value 180 -Status Critical
    New-PSICondition -Property PasswordAgeDays -Operator GreaterThan -Value 60 -Status Warning
    New-PSICondition -Property PasswordNeverExpires -Operator Equals -Value $true -Status Warning
    New-PSICondition -Property PasswordReversible -Operator Equals -Value $true -Status Critical
    New-PSICondition -Property PasswordNotRequired -Operator Equals -Value $true -Status Critical
)
$null = $Report |
    Add-PSISection -Title 'Domain Administrators' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Synthetic accounts. Illustrative presentation rules highlight password age above 180 and 60 days, and selected boolean configuration values. These are not organization policy findings.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'privileged-accounts' -Title 'Fictional Domain Administrator Accounts' -Data $DomainAdministrators -Span 12 `
        -Columns @('LogonID', 'Name', 'PasswordAgeDays', 'LastLoggedIn', 'PasswordNeverExpires', 'PasswordReversible', 'PasswordNotRequired') `
        -ColumnLabels @{ LogonID = 'Logon ID'; PasswordAgeDays = 'Pwd Age (Days)'; LastLoggedIn = 'Last Logged In'; PasswordNeverExpires = 'No Pwd Expiry'; PasswordReversible = 'Pwd Reversible'; PasswordNotRequired = 'Pwd Not Required' } `
        -Conditions $AdministratorConditions `
        -EnableSearch $false -EnableSorting $true -EnablePagination $false -EnableExport $false

$SampleFindings = @(
    New-PSIFinding -Id 'sample-password-age' -Title 'Privileged password age' -Status Critical -Category 'Credential hygiene' `
        -Description 'Two fictional privileged accounts have password ages above the illustrative 180-day threshold.' `
        -AffectedObject 'Privileged accounts' -Impact 'Long-lived credentials can increase exposure if a credential is compromised.' `
        -Recommendation 'Review the sample accounts and rotate credentials according to the report policy.' `
        -RuleId 'SAMPLE-PRIV-001' -Source 'Fictional assessment rule' -EvidenceTableId 'privileged-accounts' `
        -EvidenceFilter @{ Property = 'PasswordAgeDays'; Operator = 'GreaterThanOrEqual'; Value = 180 } `
        -EvidenceColumns @('LogonID', 'Name', 'PasswordAgeDays', 'LastLoggedIn')
    New-PSIFinding -Id 'sample-non-expiring' -Title 'Privileged account configured with password never expires' -Status Warning -Category 'Account configuration' `
        -Description 'One fictional account has the password-never-expires setting enabled.' `
        -AffectedObject 'Sample Administrator 05' -Recommendation 'Confirm that the setting follows the approved exception process.' `
        -RuleId 'SAMPLE-PRIV-002' -Source 'Fictional account snapshot' -EvidenceTableId 'privileged-accounts' `
        -EvidenceFilter @{ Property = 'PasswordNeverExpires'; Value = $true } `
        -EvidenceColumns @('LogonID', 'Name', 'PasswordNeverExpires', 'PasswordAgeDays')
    New-PSIFinding -Id 'sample-replication' -Title 'Replication issue detected' -Status Warning -Category 'Directory operations' `
        -Description 'The synthetic snapshot includes replication attempts requiring review.' `
        -AffectedObject 'Sample directory links' -Impact 'Delayed replication can leave directory changes temporarily inconsistent.' `
        -Recommendation 'Inspect the affected fictional links and retry history.' -RuleId 'SAMPLE-REPL-001' -Source 'Fictional health check'
    New-PSIFinding -Id 'sample-inventory-change' -Title 'Directory inventory changed since previous assessment' -Status Informational -Category 'Inventory' `
        -Description 'This illustrative finding represents a change between two fictional inventory snapshots.' `
        -AffectedObject 'Sample directory inventory' -Source 'Fictional comparison example'
)
$null = $Report |
    Add-PSISection -Title 'Assessment Findings' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'The findings below are fictional examples of the structured assessment model. Evidence buttons reference the existing privileged-account table.' |
    Add-PSIRow -Columns 12 |
    Add-PSIFinding -Finding $SampleFindings[0] |
    Add-PSIFinding -Finding $SampleFindings[1] |
    Add-PSIFinding -Finding $SampleFindings[2] |
    Add-PSIFinding -Finding $SampleFindings[3]

$OtherPrivilegedGroups = @(
    [pscustomobject]@{ Group = 'Administrators'; Prefix = 'admin.user'; DisplayName = 'Sample Administrator'; MemberCount = 7 }
    [pscustomobject]@{ Group = 'Server Operators'; Prefix = 'ops.server'; DisplayName = 'Sample Server Operator'; MemberCount = 1 }
    [pscustomobject]@{ Group = 'Backup Operators'; Prefix = 'ops.backup'; DisplayName = 'Sample Backup Operator'; MemberCount = 7 }
    [pscustomobject]@{ Group = 'Account Operators'; Prefix = 'ops.account'; DisplayName = 'Sample Account Operator'; MemberCount = 5 }
)
$null = $Report |
    Add-PSISection -Title 'Other Privileged Groups' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'The membership lists below are synthetic. Informational badges indicate membership only; they do not assert a security finding.'

foreach ($GroupDefinition in $OtherPrivilegedGroups) {
    $Members = @(
        for ($Index = 1; $Index -le $GroupDefinition.MemberCount; $Index++) {
            [pscustomobject]@{
                LogonID = '{0}{1:D2}' -f $GroupDefinition.Prefix, $Index
                Name = '{0} {1:D2}' -f $GroupDefinition.DisplayName, $Index
                Membership = 'Direct'
                Status = 'Informational'
            }
        }
    )
    $null = $Report |
        Add-PSIRow -Columns 12 |
        Add-PSITable -Title $GroupDefinition.Group -Data $Members -Span 12 `
            -Columns @('LogonID', 'Name', 'Membership', 'Status') `
            -ColumnLabels @{ LogonID = 'Logon ID'; Name = 'Display Name'; Membership = 'Membership Type' } `
            -PageSize 5 -EnableSearch $false -EnableSorting $true -EnablePagination $true -EnableExport $false
}

$null = $Report |
    Add-PSISection -Title 'Security Observations' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text 'These fictional counts show how a reader can scan assessment signals before opening supporting tables. They are layout examples, not conclusions about a real directory.' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Non-expiring Passwords' -Value '1,511' -Status Warning -Span 3 -Icon 'security' -Subtitle 'Sample account configuration' |
    Add-PSIKPI -Title 'Unconstrained Delegation' -Value 10 -Status Warning -Span 3 -Icon 'network' -Subtitle 'Synthetic configuration examples' |
    Add-PSIKPI -Title 'Locked User Accounts' -Value '4,008' -Status Warning -Span 3 -Icon 'warning' -Subtitle 'Illustrative snapshot' |
    Add-PSIKPI -Title 'No Pre-Auth Required' -Value 0 -Status Healthy -Span 3 -Icon 'healthy' -Subtitle 'Sample account configuration' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ('The sample also includes {0} replication issue records. No Active Directory or other external system was queried.' -f $ReplicationErrorRecords.Count)

$null = $Report |
    Add-PSISection -Title 'Report Context' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text 'Environment: Fictional production · Reporting window: rolling 24 hours · Scope: 42 application and platform services across three illustrative regions. This report uses synthetic sample records and does not query live infrastructure.'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text "Prepared by the fictional Platform Operations team. Theme is set to Auto and follows the viewer's operating-system appearance preference; reports can also be generated in Light or Dark mode."

$null = $Report |
    Add-PSISection -Title 'Service Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Services monitored' -Value 42 -Subtitle 'Across three sample environments' -Status Healthy -Icon 'dashboard' -Trend '+2 added this month' -Action @{ Type = 'Filter'; Target = 'services' } |
    Add-PSIKPI -Title 'Service availability' -Value '99.94%' -Subtitle 'Rolling 30-day sample' -Status Healthy -Icon 'healthy' -Trend '+0.08 percentage points' |
    Add-PSIKPI -Title 'Open incidents' -Value 3 -Subtitle 'Two assigned, one investigating' -Status Warning -Icon 'warning' |
    Add-PSIKPI -Title 'Data freshness' -Value '18 min' -Subtitle 'Since the latest sample refresh' -Status Info -Icon 'info'

$null = $Report |
    Add-PSISection -Title 'Controller Health Drill-down Example' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Domain Controllers' -Value $ControllerInventory.Count -Subtitle 'Fictional inventory across four sample sites' -Status Healthy -Icon 'server' -DrillDown $ControllerInventory |
    Add-PSIKPI -Title 'Healthy Controllers' -Value $HealthyControllerCount -Subtitle 'All sample health checks passing' -Status Healthy -Icon 'healthy' -DrillDown $HealthyControllers -Filter @{ Table = 'controller-inventory'; Property = 'Status'; Value = 'Healthy' } |
    Add-PSIKPI -Title 'Replication Errors' -Value $ReplicationErrorRecords.Count -Subtitle 'Sample links requiring attention' -Status Critical -Icon 'replication' -DrillDown $ReplicationErrorRecords |
    Add-PSIKPI -Title 'DNS Issues' -Value $DnsIssueRecords.Count -Subtitle 'Fictional lookup checks to review' -Status Warning -Icon 'network' -DrillDown $DnsIssueRecords

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text "The sample inventory has $($ControllerInventory.Count) records: $HealthyControllerCount Healthy, $WarningControllerCount Warning, and $UnknownControllerCount Unknown. Use the charts or table controls to filter Status and Site together, search by controller name or IP, remove individual chips, or clear all. Selecting Healthy Controllers also applies that table filter; its drill-down remains available. This report does not connect to a directory or collect live infrastructure data."

$null = $Report |
    Add-PSISection -Title 'Controller Inventory Filtering' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'controller-inventory' -Title 'Fictional Controller Inventory' -Data $ControllerInventory `
        -Columns @('Name', 'Site', 'IPv4', 'Status', 'NtpSource', 'LastCheck') `
        -ColumnLabels @{ IPv4 = 'Primary IPv4'; NtpSource = 'Time Source'; LastCheck = 'Last Check' } `
        -Filters @($ControllerStatusFilter, $ControllerSiteFilter) -PageSize 10 `
        -EnableSearch $true -EnableSorting $true -EnablePagination $true `
        -EmptyMessage 'No fictional controllers match the selected filters.'

$null = $Report |
    Add-PSISection -Title 'Service Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Title 'Fictional Application Services' -Data @(
        [pscustomobject]@{ Name = 'Customer Portal'; Type = 'Web application'; Status = 'Healthy'; LastCheck = '2 min ago'; Owner = 'Customer Experience'; Notes = 'Normal request volume and response times.' }
        [pscustomobject]@{ Name = 'Billing Gateway'; Type = 'API'; Status = 'Critical'; LastCheck = '1 min ago'; Owner = 'Commerce Platform'; Notes = 'Error rate remains above the sample critical threshold after a recent deployment.' }
        [pscustomobject]@{ Name = 'Order Processor'; Type = 'Worker service'; Status = 'Warning'; LastCheck = '3 min ago'; Owner = 'Commerce Platform'; Notes = 'Queue depth is elevated but still draining.' }
        [pscustomobject]@{ Name = 'Identity Broker'; Type = 'Authentication'; Status = 'Healthy'; LastCheck = '2 min ago'; Owner = 'Core Services'; Notes = 'Token issuance and renewal checks passed.' }
        [pscustomobject]@{ Name = 'Analytics Store'; Type = 'Database service'; Status = 'Healthy'; LastCheck = '5 min ago'; Owner = $null; Notes = 'Owner is not recorded in the fictional inventory.' }
        [pscustomobject]@{ Name = 'Notification Relay'; Type = 'Messaging'; Status = 'Info'; LastCheck = $null; Owner = 'Communications'; Notes = 'The last scheduled check has no timestamp.' }
        [pscustomobject]@{ Name = 'Document Converter'; Type = 'Worker service'; Status = 'Unknown'; LastCheck = '11 min ago'; Owner = 'Content Systems'; Notes = 'No recent health response was received in the sample window.' }
        [pscustomobject]@{ Name = 'Search Cluster'; Type = 'Search service'; Status = 'Healthy'; LastCheck = '1 min ago'; Owner = 'Customer Experience'; Notes = 'Query latency remains within the fictional operating target.' }
        [pscustomobject]@{ Name = 'Usage Collector'; Type = 'Background job'; Status = 'NotChecked'; LastCheck = 'Not scheduled'; Owner = 'Data Platform'; Notes = 'This sample job is outside its configured monitoring window.' }
        [pscustomobject]@{ Name = 'Partner Adapter'; Type = 'Integration'; Status = 'Warning'; LastCheck = '4 min ago'; Owner = 'Integrations'; Notes = 'A partner endpoint is responding slowly; retries are succeeding.' }
        [pscustomobject]@{ Name = 'Archive Export'; Type = 'Scheduled task'; Status = 'Healthy'; LastCheck = '18 min ago'; Owner = 'Data Platform'; Notes = 'The previous fictional export completed successfully.' }
        [pscustomobject]@{ Name = 'Audit Stream'; Type = 'Event pipeline'; Status = 'Critical'; LastCheck = '2 min ago'; Owner = 'Security Operations'; Notes = 'Long sample note: the downstream consumer has lagged for multiple intervals, the backlog is increasing, and the on-call team is reviewing throughput and retry behavior.' }
    ) -Columns @('Name', 'Type', 'Status', 'LastCheck', 'Owner', 'Notes') `
        -ColumnLabels @{ LastCheck = 'Last Checked'; Owner = 'Service Owner'; Notes = 'Operational Notes' } `
        -Conditions @((New-PSICondition -Property Status -Operator Equals -Value Critical -Status Critical -Scope Row)) `
        -PageSize 5 -EnableSearch $true -EnableSorting $true -EnablePagination $true `
        -EmptyMessage 'No fictional services match the current search.' -NullValueText 'Not supplied'

$null = $Report |
    Add-PSISection -Title 'Sample Charts' |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Controller Status Distribution' -ChartType Bar `
        -Data $ControllerStatusDistribution -CategoryProperty 'Health' -ValueProperty 'Count' -StatusProperty 'Health' `
        -FilterMetadata @{ Table = 'controller-inventory'; Property = 'Status'; ValueProperty = 'Health' } `
        -Width 900 -Height 320 -ShowLegend $false -ShowLabels $true

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Controllers by Site' -ChartType Doughnut `
        -Data $ControllerSiteDistribution -CategoryProperty 'Site' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'controller-inventory'; Property = 'Site'; ValueProperty = 'Site' } `
        -Width 720 -Height 320 -ShowLegend $true -ShowLabels $true

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Service Health Distribution' -ChartType Bar `
        -Data @(
            [pscustomobject]@{ Health = 'Healthy'; Count = 5 }
            [pscustomobject]@{ Health = 'Warning'; Count = 2 }
            [pscustomobject]@{ Health = 'Critical'; Count = 2 }
            [pscustomobject]@{ Health = 'Info'; Count = 1 }
            [pscustomobject]@{ Health = 'Unknown'; Count = 1 }
            [pscustomobject]@{ Health = 'NotChecked'; Count = 1 }
        ) -CategoryProperty 'Health' -ValueProperty 'Count' -StatusProperty 'Health' `
        -Width 900 -Height 340 -ShowLegend $false -ShowLabels $true

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Fictional Request and Completion Trend' -ChartType Line `
        -Data @(
            [pscustomobject]@{ Window = '09:00'; Metric = 'Requests'; Value = 112; Status = 'Healthy' }
            [pscustomobject]@{ Window = '09:15'; Metric = 'Requests'; Value = 128; Status = 'Healthy' }
            [pscustomobject]@{ Window = '09:30'; Metric = 'Requests'; Value = 141; Status = 'Warning' }
            [pscustomobject]@{ Window = '09:45'; Metric = 'Requests'; Value = 135; Status = 'Healthy' }
            [pscustomobject]@{ Window = '10:00'; Metric = 'Requests'; Value = 154; Status = 'Healthy' }
            [pscustomobject]@{ Window = '10:15'; Metric = 'Requests'; Value = 166; Status = 'Healthy' }
            [pscustomobject]@{ Window = '09:00'; Metric = 'Completed'; Value = 108; Status = 'Healthy' }
            [pscustomobject]@{ Window = '09:15'; Metric = 'Completed'; Value = 119; Status = 'Healthy' }
            [pscustomobject]@{ Window = '09:30'; Metric = 'Completed'; Value = $null; Status = 'Unknown' }
            [pscustomobject]@{ Window = '09:45'; Metric = 'Completed'; Value = 129; Status = 'Healthy' }
            [pscustomobject]@{ Window = '10:00'; Metric = 'Completed'; Value = 147; Status = 'Healthy' }
            [pscustomobject]@{ Window = '10:15'; Metric = 'Completed'; Value = 159; Status = 'Healthy' }
        ) -CategoryProperty 'Window' -ValueProperty 'Value' -SeriesProperty 'Metric' -StatusProperty 'Status' `
        -Width 900 -Height 340 -ShowLegend $true -ShowLabels $false

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Fictional Service Category Mix' -ChartType Doughnut `
        -Data @(
            [pscustomobject]@{ Category = 'Web'; Count = 38 }
            [pscustomobject]@{ Category = 'Background jobs'; Count = 24 }
            [pscustomobject]@{ Category = 'Integrations'; Count = 18 }
            [pscustomobject]@{ Category = 'Data services'; Count = 12 }
        ) -CategoryProperty 'Category' -ValueProperty 'Count' `
        -Width 720 -Height 320 -ShowLegend $true -ShowLabels $true

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Fictional Service Category Mix (Pie)' -ChartType Pie `
        -Data @(
            [pscustomobject]@{ Category = 'Web'; Count = 38 }
            [pscustomobject]@{ Category = 'Background jobs'; Count = 24 }
            [pscustomobject]@{ Category = 'Integrations'; Count = 18 }
            [pscustomobject]@{ Category = 'Data services'; Count = 12 }
        ) -CategoryProperty 'Category' -ValueProperty 'Count' `
        -Width 720 -Height 320 -ShowLegend $true -ShowLabels $true

$null = $Report |
    Add-PSISection -Title 'Operational Signals' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Warning -Label 'Background processing' -Message 'The fictional order-processing queue is above its normal operating range.'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIAlert -Status Critical -Title 'Billing API error rate elevated' -Message 'The sample billing API recorded a 4.8% error rate during the last 15 minutes.' -Timestamp (Get-Date).AddMinutes(-12) -Details @{ Environment = 'Sample production'; Region = 'West'; AffectedRequests = 184 } -Action 'Review the latest deployment and retry queue health checks.'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Warning -Title 'Reduce recurring queue saturation' -Description 'Queue depth has crossed the sample warning threshold in four of the last six observation windows.' -ActionText 'Review worker capacity and verify that retry backoff is enabled.'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Fictional sample data only. No external systems or collectors were queried.'

$null = $Report |
    Add-PSISection -Title 'Data Availability' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Title 'Optional Maintenance Windows' -Data @() -Columns @('Service', 'Window', 'Status') `
        -ColumnLabels @{ Window = 'Scheduled Window' } -EnableSearch $true -EnableSorting $true `
        -EnablePagination $true -PageSize 5 `
        -EmptyMessage 'No maintenance windows were recorded in this fictional reporting period.'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputDirectory = Join-Path -Path $ModuleRoot -ChildPath 'Reports'
    $OutputPath = Join-Path -Path $OutputDirectory -ChildPath 'PSInsightHTML-AD-Assessment-Demo.html'
}
$OutputFile = Export-PSIReport -Report $Report -Path $OutputPath

Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Report size: {0:N0} bytes" -f $OutputFile.Length)
if (-not (Test-Path -LiteralPath $OutputFile.FullName -PathType Leaf)) {
    throw "The report file was not created: $($OutputFile.FullName)"
}
Write-Host 'Verified: report file exists.'

$IsWindowsHost = $env:OS -eq 'Windows_NT'
$IsMacHost = $false
$IsLinuxHost = $false
if (-not $IsWindowsHost -and $PSVersionTable.PSEdition -eq 'Core') {
    $IsMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
    $IsLinuxHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
}

$OpenCommand = if ($IsWindowsHost) {
    'Start-Process'
}
elseif ($IsMacHost) {
    'open'
}
elseif ($IsLinuxHost) {
    'xdg-open'
}
else {
    $null
}

if ($NoBrowser) {
    Write-Host 'Browser open skipped by -NoBrowser.'
}
elseif ($OpenCommand) {
    try {
        if ($OpenCommand -eq 'Start-Process') {
            Start-Process -FilePath $OutputFile.FullName -ErrorAction Stop
        }
        elseif ($IsMacHost) {
            & /usr/bin/open $OutputFile.FullName
            if ($LASTEXITCODE -ne 0) { throw "macOS open exited with code $LASTEXITCODE." }
        }
        else {
            $OpenProcess = Start-Process -FilePath $OpenCommand -ArgumentList @($OutputFile.FullName) -PassThru -ErrorAction Stop
            if ($OpenProcess.WaitForExit(5000) -and $OpenProcess.ExitCode -ne 0) {
                throw "'$OpenCommand' exited with code $($OpenProcess.ExitCode)."
            }
        }

        Write-Host "Browser open requested with $OpenCommand."
    }
    catch {
        Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)"
    }
}
else {
    Write-Warning 'Could not detect a supported operating system for opening the report.'
}

$OutputFile

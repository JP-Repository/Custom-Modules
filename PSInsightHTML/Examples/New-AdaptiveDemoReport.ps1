[CmdletBinding()]
param(
    [Parameter()][switch] $NoBrowser,
    [Parameter()][string] $OutputPath,
    [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto'
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ModuleRoot 'Reports/PSInsightHTML-Adaptive-Demo.html'
}

# All names, status values and measurements are fictional demonstration data.
$Services = @(
    [pscustomobject]@{ Service='Gateway North'; Platform='Edge'; Region='North'; Status='Healthy'; Availability='99.98%'; Owner='Operations'; LastCheck='3 minutes ago' }
    [pscustomobject]@{ Service='Gateway South'; Platform='Edge'; Region='South'; Status='Healthy'; Availability='99.95%'; Owner='Operations'; LastCheck='4 minutes ago' }
    [pscustomobject]@{ Service='Compute Atlas'; Platform='Compute'; Region='North'; Status='Healthy'; Availability='99.99%'; Owner='Platform'; LastCheck='2 minutes ago' }
    [pscustomobject]@{ Service='Compute Vega'; Platform='Compute'; Region='West'; Status='Warning'; Availability='98.72%'; Owner='Platform'; LastCheck='6 minutes ago' }
    [pscustomobject]@{ Service='Archive Store'; Platform='Storage'; Region='Central'; Status='Healthy'; Availability='99.92%'; Owner='Storage'; LastCheck='5 minutes ago' }
    [pscustomobject]@{ Service='Event Stream'; Platform='Messaging'; Region='East'; Status='Critical'; Availability='96.40%'; Owner='Integration'; LastCheck='1 minute ago' }
    [pscustomobject]@{ Service='Identity Hub'; Platform='Application'; Region='Central'; Status='Healthy'; Availability='99.96%'; Owner='Applications'; LastCheck='4 minutes ago' }
    [pscustomobject]@{ Service='API Relay'; Platform='Application'; Region='West'; Status='Warning'; Availability='98.90%'; Owner='Applications'; LastCheck='8 minutes ago' }
    [pscustomobject]@{ Service='Metrics Lake'; Platform='Storage'; Region='East'; Status='Healthy'; Availability='99.91%'; Owner='Analytics'; LastCheck='7 minutes ago' }
    [pscustomobject]@{ Service='Job Orchestrator'; Platform='Compute'; Region='South'; Status='Healthy'; Availability='99.87%'; Owner='Automation'; LastCheck='6 minutes ago' }
    [pscustomobject]@{ Service='Audit Pipeline'; Platform='Messaging'; Region='Central'; Status='Warning'; Availability='98.61%'; Owner='Security'; LastCheck='9 minutes ago' }
    [pscustomobject]@{ Service='Portal Frontend'; Platform='Application'; Region='North'; Status='Healthy'; Availability='99.94%'; Owner='Applications'; LastCheck='3 minutes ago' }
)
$Report = New-PSIReport -Title 'Fictional Operations Console' `
    -Subtitle 'A standalone, technology-neutral infrastructure snapshot' -Theme $Theme -Layout Application

$Resources = @(
    for ($I = 0; $I -lt $Services.Count; $I++) {
        $Service = $Services[$I]
        New-PSIResource -Definition @{
            Id=('resource-{0:d2}' -f ($I + 1)); Name=$Service.Service; Type=$Service.Platform
            Status=$Service.Status; Description="Fictional $($Service.Platform.ToLowerInvariant()) resource in the $($Service.Region) region."
            Properties=@{ Region=$Service.Region; Availability=$Service.Availability; Owner=$Service.Owner; LastCheck=$Service.LastCheck }
        }
    }
)
$FindingExamples = @(
    @{ Title='Event processor queue backlog'; Severity='Critical'; Category='Processing'; Resources=@(6,8); Impact='Delayed event delivery'; Action='Review processor capacity and queue drain'; Expected='Queue within sample target' }
    @{ Title='West region response time'; Severity='Warning'; Category='Performance'; Resources=@(4,8); Impact='Slower regional response'; Action='Inspect regional latency and capacity'; Expected='Response within sample target' }
    @{ Title='Audit delivery lag'; Severity='Warning'; Category='Processing'; Resources=@(6,11); Impact='Audit events may arrive late'; Action='Inspect the delivery checkpoint'; Expected='Delivery within sample interval' }
    @{ Title='Recovery dependency review'; Severity='Warning'; Category='Resilience'; Resources=@(6,12); Impact='Recovery path needs review'; Action='Confirm a documented recovery path'; Expected='Reviewed recovery dependency' }
    @{ Title='Service owner inventory'; Severity='Info'; Category='Ownership'; Resources=@(7,12); Impact='Owner mapping needs confirmation'; Action='Confirm the listed owner'; Expected='Current owner recorded' }
    @{ Title='Regional probe coverage'; Severity='Warning'; Category='Monitoring'; Resources=@(4,2); Impact='Monitoring coverage needs review'; Action='Review regional probes'; Expected='All sample probes reporting' }
    @{ Title='Archive retention check'; Severity='Healthy'; Category='Configuration'; Resources=@(5); Impact='No current issue'; Action='Continue scheduled review'; Expected='Retention remains aligned' }
    @{ Title='Compute capacity observation'; Severity='Info'; Category='Capacity'; Resources=@(3,4); Impact='Trend is informational'; Action='Observe the next trend window'; Expected='Capacity remains stable' }
    @{ Title='Metrics freshness'; Severity='Warning'; Category='Data quality'; Resources=@(9,6); Impact='Some sample metrics lag'; Action='Check ingestion timestamps'; Expected='Metrics arrive within sample window' }
    @{ Title='Gateway availability check'; Severity='Healthy'; Category='Availability'; Resources=@(1,2); Impact='No current issue'; Action='Continue routine checks'; Expected='Availability remains healthy' }
)
$Findings = @()
$EvidenceRecords = @()
for ($I = 0; $I -lt $FindingExamples.Count; $I++) {
    $Example = $FindingExamples[$I]
    $FindingId = 'finding-{0:d2}' -f ($I + 1)
    $EvidenceId = 'evidence-{0:d2}' -f ($I + 1)
    $ResourceIds = @($Example.Resources | ForEach-Object { 'resource-{0:d2}' -f $_ })
    $Findings += New-PSIApplicationFinding -Definition @{
        Id=$FindingId; Title=$Example.Title; Summary="Fictional observation for $($Example.Category.ToLowerInvariant()) review."
        Severity=$Example.Severity; Status=if ($I -eq 6) { 'Resolved' } else { 'Open' }
        Category=$Example.Category; ReadinessImpact=$Example.Impact; AffectedResourceIds=$ResourceIds
        EvidenceIds=@($EvidenceId); Owner='Sample operations'; RemediationState='Review queued'
        Recommendation=@{ Summary=$Example.Action; Rationale='Fictional source data only'; Priority=$Example.Severity; Action=$Example.Action; ExpectedState=$Example.Expected; RequiresRestart=$false; RequiresReboot=$false; AutomationHint='Descriptive only; no action is executed' }
        Validation=@{ Method='Review the next sample observation'; ExpectedResult=$Example.Expected; EvidenceRequired=$true; Status='NotTested' }
    }
    $EvidenceRecords += New-PSIEvidenceRecord -Definition @{
        Id=$EvidenceId; Title="Observation $($I + 1): $($Example.Title)"; Type='Sample observation'; Source='Fictional monitor'
        CollectedAt=[datetime] '2026-10-16T16:00:00'; Summary=$Example.Impact
        Data=@{ Category=$Example.Category; Observed=$Example.Impact; Note='Sample data; no live source queried.' }
        Metadata=@{ CollectionStateApplicability='NotApplicable' }
        FindingIds=@($FindingId); ResourceIds=$ResourceIds
    }
    foreach ($Resource in $Resources) {
        if ($Resource.Id -in $ResourceIds) {
            $Resource.FindingIds = @($Resource.FindingIds) + @($FindingId)
            $Resource.EvidenceIds = @($Resource.EvidenceIds) + @($EvidenceId)
        }
    }
}
$Relationships = @(
    New-PSIRelationship -Definition @{ Id='relationship-01'; SourceResourceId='resource-12'; TargetResourceId='resource-08'; Type='depends-on'; Status='Warning'; Impact='Portal responses'; FindingIds=@('finding-04') }
    New-PSIRelationship -Definition @{ Id='relationship-02'; SourceResourceId='resource-08'; TargetResourceId='resource-06'; Type='depends-on'; Status='Critical'; Impact='Event updates'; FindingIds=@('finding-01') }
    New-PSIRelationship -Definition @{ Id='relationship-03'; SourceResourceId='resource-09'; TargetResourceId='resource-05'; Type='depends-on'; Status='Healthy'; Impact='Metrics archive' }
    New-PSIRelationship -Definition @{ Id='relationship-04'; SourceResourceId='resource-11'; TargetResourceId='resource-06'; Type='depends-on'; Status='Warning'; Impact='Audit delivery'; FindingIds=@('finding-03') }
)
foreach ($Relationship in $Relationships) {
    foreach ($Resource in $Resources) {
        if ($Resource.Id -in @($Relationship.SourceResourceId,$Relationship.TargetResourceId)) {
            $Resource.RelationshipIds = @($Resource.RelationshipIds) + @($Relationship.Id)
        }
    }
}
$Findings[0].Relationships = @('relationship-02')
$Model = New-PSIApplicationModel -Findings $Findings -Resources $Resources -Evidence $EvidenceRecords -Relationships $Relationships
$HierarchyParents = @{ 'resource-02'='resource-01'; 'resource-03'='resource-01'; 'resource-04'='resource-03'; 'resource-05'='resource-03'; 'resource-06'='resource-08'; 'resource-07'='resource-12'; 'resource-08'='resource-12'; 'resource-09'='resource-05'; 'resource-10'='resource-03'; 'resource-11'='resource-06' }
$HierarchyNodes = @(
    foreach ($Resource in $Model.Resources) {
        @{ NodeId=$Resource.Id; ResourceId=$Resource.Id; ParentId=[string] $HierarchyParents[$Resource.Id]; Icon='ResourceServer' }
    }
    @{ NodeId='external-assurance'; Label='External assurance'; NodeType='External service'; Status='NotChecked'; Icon='Relationship'; ParentId='resource-06'; IsExternal=$true; EvidenceOnly=$true; Description='Fictional observation source outside the assessed resource scope.' }
)
$PresentationRelationships = @($Model.Relationships) + @(
    [pscustomobject]@{ Id='relationship-external-assurance'; SourceId='external-assurance'; TargetId='resource-06'; Type='observes'; Label='Provides observation'; Direction='Directed'; Status='NotChecked'; Category='Monitoring'; Description='Evidence-only external monitoring connection.'; IsExternal=$true; EvidenceOnly=$true; EvidenceIds=@('evidence-06') }
)
$null = $Report | Set-PSIApplicationModel -Model $Model

# Provider-neutral fictional assessment. These outcomes and actions are sample inputs.
$CategoryDefinitions = @(
    @{ Id='platform'; Name='Platform'; Icon='ResourceServer'; Weight=1.3 }
    @{ Id='health'; Name='Health'; Icon='SeveritySuccess'; Weight=1.4 }
    @{ Id='security'; Name='Security'; Icon='SecurityShield'; Weight=1.5 }
    @{ Id='dependencies'; Name='Dependencies'; Icon='Relationship'; Weight=1.2 }
    @{ Id='configuration'; Name='Configuration'; Icon='Rules'; Weight=1.0 }
    @{ Id='operations'; Name='Operational readiness'; Icon='NavigationHome'; Weight=1.1 }
    @{ Id='validation'; Name='Validation'; Icon='Document'; Weight=1.0 }
)
$Checks = @(
    for ($I = 1; $I -le 49; $I++) {
        $CategoryIndex = [math]::Floor(($I - 1) / 7)
        $Category = $CategoryDefinitions[$CategoryIndex]
        $Status = if ($I -in @(5,19)) { 'Blocked' }
            elseif ($I -in @(7,14,22,31,40)) { 'Review' }
            elseif ($I -in @(12,35)) { 'NotTested' }
            elseif ($I -in @(28,49)) { 'NotApplicable' }
            elseif ($I -eq 44) { 'Unknown' }
            else { 'Ready' }
        $FindingId = if ($I -in @(5,19)) { 'finding-01' }
            elseif ($I -eq 7) { 'finding-02' }
            elseif ($I -eq 14) { 'finding-03' }
            elseif ($I -eq 22) { 'finding-04' }
            elseif ($I -eq 31) { 'finding-05' }
            elseif ($I -eq 40) { 'finding-06' }
            else { '' }
        $LinkedFinding = if ($FindingId) { @($Model.Findings | Where-Object { $_.Id -eq $FindingId })[0] } else { $null }
        $ResourceIds = if ($LinkedFinding) { @($LinkedFinding.AffectedResourceIds) } else { @($Resources[($I - 1) % $Resources.Count].Id) }
        $EvidenceIds = if ($LinkedFinding) { @($LinkedFinding.EvidenceIds) } else { @() }
        $Action = if ($LinkedFinding) { [string] $LinkedFinding.Recommendation.Action }
            elseif ($Status -eq 'NotTested') { 'Provide a fictional observation before making a readiness decision.' }
            else { 'Continue the scheduled sample review.' }
        New-PSIAssessmentCheck -Definition @{
            Id=('check-{0:d2}' -f $I); Name=('{0} check {1:d2}' -f $Category.Name, (($I - 1) % 7 + 1))
            Description="Fictional $($Category.Name.ToLowerInvariant()) check supplied by the sample assessment."
            CategoryId=$Category.Id; Status=$Status; Severity=if ($Status -eq 'Blocked') { 'Critical' } elseif ($Status -eq 'Review') { 'Warning' } else { 'Info' }
            Weight=if ($I -in @(5,19)) { 1.2 } else { 1.0 }; IsBlocking=($I -in @(5,19))
            ObservedState=if ($Status -eq 'NotTested') { 'No sample observation' } else { "$Status in fictional snapshot" }
            ExpectedState='Ready in the fictional assessment profile'
            FindingIds=if ($FindingId) { @($FindingId) } else { @() }; ResourceIds=$ResourceIds; EvidenceIds=$EvidenceIds
            Recommendation=@{ Action=$Action; ExpectedState='Ready in the fictional assessment profile'; AutomationHint='Description only' }
            Validation=@{ Method='Compare the next sample snapshot'; ExpectedResult='Ready'; EvidenceRequired=$true; Status='NotTested' }
            Frameworks=@('Fictional internal profile'); Tags=@('sample')
        }
    }
)
$Categories = @(
    foreach ($Definition in $CategoryDefinitions) {
        $Ids = @($Checks | Where-Object { $_.CategoryId -eq $Definition.Id } | ForEach-Object { $_.Id })
        New-PSIAssessmentCategory -Definition @{
            Id=$Definition.Id; Name=$Definition.Name; Description="Seven fictional $($Definition.Name.ToLowerInvariant()) checks."
            Icon=$Definition.Icon; Weight=$Definition.Weight; CheckIds=$Ids
            FindingIds=@($Checks | Where-Object { $_.CategoryId -eq $Definition.Id } | ForEach-Object { $_.FindingIds } | Where-Object { $_ } | Sort-Object -Unique)
            ResourceIds=@($Checks | Where-Object { $_.CategoryId -eq $Definition.Id } | ForEach-Object { $_.ResourceIds } | Where-Object { $_ } | Sort-Object -Unique)
        }
    }
)
$SampleAssessmentDate = Get-Date
$Assessment = New-PSIApplicationAssessment -Definition @{
    Id='sample-assessment'; Name='Operational readiness assessment'; Description='A fictional, provider-neutral assessment of a sample operations environment.'
    AssessmentType='Readiness'; Target='Sample operations environment'; Profile='Fictional Operational Readiness 2026'
    Scope='12 fictional services across seven assessment categories; no live systems were queried.'
    GeneratedAt=$SampleAssessmentDate; Categories=$Categories; Checks=$Checks
    FindingIds=@($Model.Findings | ForEach-Object { $_.Id }); ResourceIds=@($Model.Resources | ForEach-Object { $_.Id })
    EvidenceIds=@($Model.Evidence | ForEach-Object { $_.Id })
    Metadata=@{ PrintDisplay=@{
        ReportIdentity=@{ Kicker='PSInsightHTML / Fictional operations assessment' }
        Resources=@{ Columns=@(
            @{ Property='Name'; Label='Service' }, @{ Property='Type'; Label='Platform' },
            @{ Property='Region'; Label='Region' }, @{ Property='Owner'; Label='Owner' },
            @{ Property='Status'; Label='Status'; Format='Status' }
        ) }
        Evidence=@{ Fields=@(
            @{ Property='Id'; Label='Reference' }, @{ Property='Source'; Label='Observation source' },
            @{ Property='CollectionState'; Label='Collection state' },
            @{ Property='Scope'; Label='Linked services'; Format='List' },
            @{ Property='CollectedAt'; Label='Recorded'; Format='DateTime' },
            @{ Property='Summary'; Label='Summary' }, @{ Property='FindingIds'; Label='Linked findings'; Format='List' }
        ) }
    } }
    Recommendations=@('Review the two fictional blocking checks and their linked evidence.','Collect observations for checks marked Not Tested before revisiting the decision.')
    Exceptions=@(
        @{ Id='exception-approved'; Title='Planned review window'; Description='Fictional approved review window.'; CheckId='check-07'; FindingId='finding-02'; ResourceIds=@('resource-04'); Reason='Sample maintenance review'; Owner='Sample operations'; ApprovedBy='Fictional review board'; ApprovedAt=$SampleAssessmentDate.Date.AddDays(-6); ExpiresAt=$SampleAssessmentDate.Date.AddDays(24); Status='Approved' }
        @{ Id='exception-expiring'; Title='Expiring observation exception'; Description='Fictional exception nearing expiry.'; CheckId='check-14'; FindingId='finding-03'; ResourceIds=@('resource-06'); Reason='Sample observation follow-up'; Owner='Sample assurance'; ApprovedBy='Fictional review board'; ApprovedAt=$SampleAssessmentDate.Date.AddDays(-4); ExpiresAt=$SampleAssessmentDate.Date.AddDays(4); Status='Approved' }
    )
    ReadyScoreMinimum=90; ReviewScoreMinimum=75
}
$null = $Report | Set-PSIApplicationAssessment -Assessment $Assessment

$null = $Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Readiness, priorities, and recent signals' -Icon NavigationHome -Initial `
        -Commands @(@{ Label='Review findings'; Icon='SeverityWarning'; TargetView='findings' }) |
    Add-PSISection -Title 'Operational readiness' |
    Add-PSIRow -Columns 12 |
    Add-PSIAssessmentOverview |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Sample environment: 12 monitored services across five fictional regions. Ten linked findings illustrate investigation and remediation workflows; four service states need review.' -Size Large |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Warning -Label 'Readiness: Review required' -Message 'One critical and three warning service states appear in this sample. Open Findings to inspect the linked observations.' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Monitored services' -Value 12 -Subtitle 'Across all sample regions' -Status Informational -Icon ResourceServer -Span 3 |
    Add-PSIKPI -Title 'Healthy' -Value 8 -Subtitle 'Latest fictional checks' -Status Healthy -Icon SeveritySuccess -Span 3 -Filter @{ Table='adaptive-services'; Property='Status'; Value='Healthy' } |
    Add-PSIKPI -Title 'Needs review' -Value 3 -Subtitle 'Warning state' -Status Warning -Icon SeverityWarning -Span 3 -Filter @{ Table='adaptive-services'; Property='Status'; Value='Warning' } |
    Add-PSIKPI -Title 'Critical' -Value 1 -Subtitle 'Event Stream in this sample' -Status Critical -Icon SeverityError -Span 3 -Filter @{ Table='adaptive-services'; Property='Status'; Value='Critical' }

$Distribution = @(
    [pscustomobject]@{ State='Healthy'; Count=8; Status='Healthy' }
    [pscustomobject]@{ State='Warning'; Count=3; Status='Warning' }
    [pscustomobject]@{ State='Critical'; Count=1; Status='Critical' }
)
$Trend = @(
    [pscustomobject]@{ Window='06:00'; Availability=99.6 }
    [pscustomobject]@{ Window='08:00'; Availability=99.7 }
    [pscustomobject]@{ Window='10:00'; Availability=99.3 }
    [pscustomobject]@{ Window='12:00'; Availability=99.8 }
    [pscustomobject]@{ Window='14:00'; Availability=99.5 }
    [pscustomobject]@{ Window='16:00'; Availability=99.7 }
)
$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Service health distribution' -ChartType Bar -Data $Distribution `
        -CategoryProperty State -ValueProperty Count -StatusProperty Status `
        -FilterMetadata @{ Table='adaptive-services'; Property='Status' } |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Illustrative aggregate availability' -ChartType Line -Data $Trend `
        -CategoryProperty Window -ValueProperty Availability

$null = $Report |
    Add-PSIView -Id checks -Title 'Checks' -Subtitle 'Category, status, blocker, and evidence investigation' -Icon Rules -Badge $Assessment.Checks.Count |
    Add-PSISection -Title 'Assessment checks' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Filter the fictional checks by category and status. Select a check to inspect observed and expected states, linked records, recommendation, and validation.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'adaptive-checks' -Title 'Assessment controls' -Data $Assessment.Checks `
        -TitleProperty Name -SubtitleProperty CategoryId -StatusProperty Status -EntityType Check `
        -FilterProperties @('CategoryId','Status') |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'adaptive-categories' -Title 'Category posture' -Data $Assessment.Categories `
        -TitleProperty Name -SubtitleProperty Description -StatusProperty Status -EntityType Category

$null = $Report |
    Add-PSIView -Id findings -Title 'Findings' -Subtitle 'Select an observation to inspect evidence and next steps' -Icon SeverityWarning -Badge $Model.Findings.Count `
        -Commands @(@{ Label='View resources'; Icon='ResourceServer'; TargetView='resources' }) |
    Add-PSISection -Title 'Finding queue' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Choose a fictional finding to inspect linked resources, typed evidence, remediation guidance, and validation. Linked records open in their own workspace.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'adaptive-findings' -Title 'Assessment observations' -Data $Model.Findings `
        -TitleProperty Title -SubtitleProperty Category -StatusProperty Severity -EntityType Finding |
    Add-PSIRow -Columns 12 |
    Add-PSIInsight -Title 'Critical evidence' -Value 1 -Description 'Open the current critical service record.' `
        -Status Critical -Icon SeverityError -Filter @{ Table='adaptive-services'; Conditions=@(@{ Property='Status'; Operator='Equals'; Value='Critical' }) }

$StatusFilter = Add-PSIFilter -Property Status -Label Status -Values @('Healthy', 'Warning', 'Critical')
$RegionFilter = Add-PSIFilter -Property Region -Label Region -Values @('North', 'South', 'Central', 'East', 'West')
$null = $Report |
    Add-PSIView -Id resources -Title 'Resources' -Subtitle 'Inventory, ownership, and related observations' -Icon ResourceServer -Badge $Model.Resources.Count `
        -Commands @(@{ Label='View evidence'; Icon='Document'; TargetView='evidence' }) |
    Add-PSISection -Title 'Resource workspace' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'adaptive-resources' -Title 'Monitored resources' -Data $Model.Resources `
        -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -EntityType Resource |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-services' -Title 'Monitored service inventory' -Data $Services -Span 12 `
        -Columns @('Service', 'Platform', 'Region', 'Status', 'Availability', 'Owner', 'LastCheck') `
        -ColumnLabels @{ LastCheck='Last check' } -Filters @($StatusFilter, $RegionFilter) -PageSize 6

$null = $Report |
    Add-PSIView -Id exceptions -Title 'Exceptions' -Subtitle 'Documented sample exceptions and expiry' -Icon SeverityInfo -Group Investigation -Badge $Assessment.Exceptions.Count |
    Add-PSISection -Title 'Assessment exceptions' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Exceptions are represented as data only. Approval, expiry, and ownership do not automatically suppress a blocker or change the posture decision.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'adaptive-exceptions' -Title 'Exception records' -Data $Assessment.Exceptions `
        -TitleProperty Title -SubtitleProperty Reason -StatusProperty Status -EntityType Exception |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-exception-table' -Title 'Exception register' -Data $Assessment.Exceptions `
        -Columns @('Title','CheckId','Reason','Owner','ApprovedBy','ExpiresAt','Status') -PageSize 5
$null = $Report |
    Add-PSIView -Id security -Title 'Security' -Subtitle 'Illustrative control posture and exceptions' -Icon SecurityShield |
    Add-PSISection -Title 'Control posture' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status NotChecked -Label 'Illustrative assessment' -Message 'These are fictional control outcomes. No live environment was assessed.' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Passed' -Value 3 -Status Healthy -Icon SeveritySuccess -Span 3 |
    Add-PSIKPI -Title 'Review' -Value 2 -Status Warning -Icon SeverityWarning -Span 3 |
    Add-PSIKPI -Title 'Failed' -Value 1 -Status Critical -Icon SeverityError -Span 3 |
    Add-PSIKPI -Title 'Not tested' -Value 1 -Status NotChecked -Icon SeverityInfo -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-controls' -Title 'Fictional control groups' -Data @(
        [pscustomobject]@{ Control='Access review'; Group='Identity'; Result='Passed'; Status='Healthy'; Exception='None' }
        [pscustomobject]@{ Control='Audit routing'; Group='Monitoring'; Result='Review'; Status='Warning'; Exception='Delayed sample check' }
        [pscustomobject]@{ Control='Service owner assignment'; Group='Operations'; Result='Passed'; Status='Healthy'; Exception='None' }
        [pscustomobject]@{ Control='Queue recovery'; Group='Resilience'; Result='Failed'; Status='Critical'; Exception='Event Stream backlog' }
        [pscustomobject]@{ Control='Change notification'; Group='Operations'; Result='Passed'; Status='Healthy'; Exception='None' }
        [pscustomobject]@{ Control='Regional latency review'; Group='Performance'; Result='Review'; Status='Warning'; Exception='West region' }
        [pscustomobject]@{ Control='External assurance'; Group='Governance'; Result='Not Tested'; Status='NotChecked'; Exception='No source supplied' }
    ) -Columns @('Control','Group','Result','Status','Exception') -PageSize 5
$null = $Report |
    Add-PSIView -Id policies -Title 'Policies' -Subtitle 'Current and expected configuration snapshots' -Icon Rules -Group Investigation |
    Add-PSISection -Title 'Policy comparison' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Fictional current/expected values illustrate a generic configuration comparison. These are not evaluated compliance rules.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-policies' -Title 'Configuration examples' -Data @(
        [pscustomobject]@{ Setting='Retention period'; Current='30 days'; Expected='30 days'; Source='Sample inventory'; Scope='Messaging'; Status='Healthy' }
        [pscustomobject]@{ Setting='Checkpoint interval'; Current='15 minutes'; Expected='10 minutes'; Source='Sample policy'; Scope='Audit Pipeline'; Status='Warning' }
        [pscustomobject]@{ Setting='Recovery owner'; Current='Operations'; Expected='Operations'; Source='Sample owner map'; Scope='Compute'; Status='Healthy' }
        [pscustomobject]@{ Setting='Regional probe'; Current='Pending'; Expected='Enabled'; Source='Sample configuration'; Scope='West'; Status='NotChecked' }
    ) -Columns @('Setting','Current','Expected','Source','Scope','Status') -PageSize 4 |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Title 'Define review criteria' -Description 'Confirm source and scope before translating sample differences into operational findings.' -Status Informational
$null = $Report |
    Add-PSIView -Id dependencies -Title 'Dependencies' -Subtitle 'Direct relationships and possible impact' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Relationship inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'These direct relationships are fictional examples. This view does not calculate topology or transitive impact.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-dependencies' -Title 'Sample dependencies' -Data @(
        [pscustomobject]@{ Resource='Portal Frontend'; DependsOn='API Relay'; Status='Warning'; Impact='User requests may slow down' }
        [pscustomobject]@{ Resource='API Relay'; DependsOn='Event Stream'; Status='Critical'; Impact='Asynchronous updates may lag' }
        [pscustomobject]@{ Resource='Metrics Lake'; DependsOn='Archive Store'; Status='Healthy'; Impact='No current sample impact' }
        [pscustomobject]@{ Resource='Audit Pipeline'; DependsOn='Event Stream'; Status='Warning'; Impact='Audit events may arrive late' }
    ) -Columns @('Resource','DependsOn','Status','Impact') -ColumnLabels @{ DependsOn='Depends on' } -PageSize 4
$null = $Report |
    Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Searchable observations and source context' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Evidence workspace' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Select typed evidence to inspect its source and observed data, or use the existing searchable observation table and shared service evidence viewer below.' -Size Small |
    Add-PSIExplorer -Id 'adaptive-evidence-records' -Title 'Linked evidence' -Data $Model.Evidence `
        -TitleProperty Title -SubtitleProperty Source -EntityType Evidence |
    Add-PSIRow -Columns 12 |
    Add-PSIInsight -Title 'Service records' -Value $Services.Count -Description 'Open all fictional service records in the reusable evidence viewer.' `
        -Status Informational -Icon Document -Filter @{ Table='adaptive-services'; Conditions=@() } |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'adaptive-evidence' -Title 'Observation log' -Data @(
        [pscustomobject]@{ Observation='Queue depth increased'; Resource='Event Stream'; Category='Processing'; Status='Critical'; Source='Sample monitor'; Time='16:00' }
        [pscustomobject]@{ Observation='Latency exceeded sample baseline'; Resource='Compute Vega'; Category='Performance'; Status='Warning'; Source='Sample probe'; Time='15:50' }
        [pscustomobject]@{ Observation='Gateway check completed'; Resource='Gateway North'; Category='Availability'; Status='Healthy'; Source='Sample probe'; Time='15:45' }
        [pscustomobject]@{ Observation='Audit delivery delayed'; Resource='Audit Pipeline'; Category='Processing'; Status='Warning'; Source='Sample monitor'; Time='15:40' }
        [pscustomobject]@{ Observation='Owner record reviewed'; Resource='Identity Hub'; Category='Ownership'; Status='Informational'; Source='Sample inventory'; Time='15:35' }
        [pscustomobject]@{ Observation='Recovery source unavailable'; Resource='External assurance'; Category='Governance'; Status='NotChecked'; Source='No source supplied'; Time=$null }
    ) -Columns @('Observation','Resource','Category','Status','Source','Time') -PageSize 4

$null = $Report |
    Add-PSIView -Id hierarchy -Title 'Hierarchy' -Subtitle 'Fictional service structure and linked details' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Service hierarchy' |
    Add-PSIRow -Columns 12 |
    Add-PSITree -Id 'adaptive-hierarchy' -Title 'Service hierarchy' -Nodes $HierarchyNodes -Relationships $PresentationRelationships -DetailProperties @('Region','Owner','Availability')
$null = $Report |
    Add-PSIView -Id topology -Title 'Topology' -Subtitle 'Fictional dependencies and an evidence-only endpoint' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Service topology' |
    Add-PSIRow -Columns 12 |
    Add-PSITopology -Id 'adaptive-topology' -Title 'Service topology' -Nodes $HierarchyNodes -Relationships $PresentationRelationships -DetailProperties @('Region','Owner')
$null = $Report |
    Add-PSIView -Id relationships -Title 'Relationships' -Subtitle 'Incoming and outgoing service connections' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Relationship explorer' |
    Add-PSIRow -Columns 12 |
    Add-PSIRelationshipExplorer -Id 'adaptive-relationships' -Title 'Service relationships' -Nodes $HierarchyNodes -Relationships $PresentationRelationships

$File = Export-PSIReport -Report $Report -Path $OutputPath
Write-Host "Generated adaptive demo: $($File.FullName)"
Write-Host "Fictional services: $($Services.Count); size: $($File.Length) bytes."
if (-not $NoBrowser) {
    try {
        if ($IsMacOS) { & open $File.FullName 2>$null }
        elseif ($IsWindows -or $env:OS -eq 'Windows_NT') { Start-Process -FilePath $File.FullName }
        else { & xdg-open $File.FullName 2>$null }
    }
    catch { Write-Warning "Could not open the default browser: $($_.Exception.Message)" }
}

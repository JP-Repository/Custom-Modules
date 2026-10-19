function ConvertTo-PSIPrintProjection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    function E($Value) { ConvertTo-PSIHtmlEncoded -Value $Value }
    function V($Object, $Name, $Fallback = '') {
        $Value = Get-PSIProperty -InputObject $Object -Name $Name -DefaultValue $Fallback
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { return $Fallback }
        return $Value
    }
    function Status($Value) {
        '<span class="psi-print-status">' + (E $Value) + '</span>'
    }
    function ReasonText($Value) {
        $Text = [string] $Value
        $Text = $Text.Replace('1 blocking checks require action.', '1 blocking check requires action.')
        $Text = $Text.Replace('1 open critical findings affect this assessment.', '1 open critical finding affects this assessment.')
        $Text = $Text.Replace('1 checks are blocked.', '1 check is blocked.')
        $Text = $Text.Replace('1 checks were not tested', '1 check was not tested')
        $Text = $Text.Replace('1 checks have unknown results', '1 check has an unknown result')
        $Text = $Text.Replace('1 checks require review and contribute half credit.', '1 check requires review and contributes half credit.')
        $Text = $Text.Replace('1 not-applicable checks are excluded', '1 not-applicable check is excluded')
        return $Text
    }
    function TextLine($Label, $Value) {
        if ([string]::IsNullOrWhiteSpace([string] $Value)) { return '' }
        '<div><dt>' + (E $Label) + '</dt><dd>' + (E $Value) + '</dd></div>'
    }
    function Section($Id, $Number, $Title) {
        '<section class="psi-print-section" id="psi-print-' + $Id + '"><header class="psi-print-section-heading"><span>' + $Number + '</span><h2>' + (E $Title) + '</h2></header>'
    }
    function Row($Cells) {
        '<tr>' + ((@($Cells) | ForEach-Object { '<td>' + $_ + '</td>' }) -join '') + '</tr>'
    }
    function Table($Headers, $Rows) {
        '<table><thead><tr>' + ((@($Headers) | ForEach-Object { '<th scope="col">' + (E $_) + '</th>' }) -join '') + '</tr></thead><tbody>' + ($Rows -join "`n") + '</tbody></table>'
    }

    $B = [System.Text.StringBuilder]::new()
    $Assessment = V $Report 'ApplicationAssessment' $null
    $Model = V $Report 'ApplicationModel' $null
    $Meta = if ($null -ne $Assessment) { V $Assessment 'Metadata' @{} } else { @{} }
    $PrintConfig = V $Meta 'Print' @{}
    $ReportPrintConfig = if ($null -eq $Assessment) { V $Report 'PrintDisplay' $null } else { $null }
    $PrintDisplay = Resolve-PSIPrintDisplay -Configuration $(if ($null -ne $Assessment) { V $Meta 'PrintDisplay' $null } else { $ReportPrintConfig }) -LegacyConfiguration $PrintConfig
    $ReportTitle = [string] (V $Report 'Title')
    $Target = if ($null -ne $Assessment) { [string] (V $Assessment 'Target') } else { '' }
    $Generated = ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm zzz')
    $Version = [string] (V $Report 'ModuleVersion')
    $Decision = if ($null -ne $Assessment) { [string] (V $Assessment 'Decision' 'Unknown') } else { 'Report' }
    $Score = if ($null -ne $Assessment -and $null -ne $Assessment.Score) { "$($Assessment.Score)%" } else { 'Not scored' }
    $ScoreLabel=if ($null -eq $Assessment) { 'Assessment score' } else { switch ([string](V $Assessment 'AssessmentType')) { 'Readiness' { 'Readiness score' } 'Health' { 'Health score' } 'Security' { 'Security score' } default { 'Assessment score' } } }
    $Coverage = if ($null -ne $Assessment) { V $Meta 'EvidenceCoveragePercent' $null } else { V $ReportPrintConfig 'CoveragePercent' $null }
    $CoverageText = if ($null -ne $Coverage) { "$Coverage%" } else { 'Not supplied' }
    $FindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ResourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $EvidenceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Assessment) {
        foreach ($Id in @($Assessment.FindingIds)) { [void] $FindingIds.Add([string] $Id) }
        foreach ($Id in @($Assessment.ResourceIds)) { [void] $ResourceIds.Add([string] $Id) }
        foreach ($Id in @($Assessment.EvidenceIds)) { [void] $EvidenceIds.Add([string] $Id) }
    }
    $Findings = if ($null -ne $Model) { @($Model.Findings | Where-Object { $null -eq $Assessment -or $FindingIds.Contains([string] $_.Id) } | Sort-Object @{ Expression = { if ($_.Status -eq 'NotTested') { 4 } elseif ($_.Status -in @('Resolved','AcceptedRisk','NotApplicable')) { 5 } else { switch ($_.Severity) { Critical { 0 } Warning { 1 } Info { 2 } default { 3 } } } } }, Title) } else { @() }
    $Resources = if ($null -ne $Model) { @($Model.Resources | Where-Object { $null -eq $Assessment -or $ResourceIds.Contains([string] $_.Id) }) } else { @() }
    $Evidence = if ($null -ne $Model) { @($Model.Evidence | Where-Object { $null -eq $Assessment -or $EvidenceIds.Contains([string] $_.Id) }) } else { @() }
    $Checks = if ($null -ne $Assessment) { @($Assessment.Checks) } else { @() }
    $EvidenceChecks = @{}
    foreach ($Check in $Checks) {
        foreach ($Id in @($Check.EvidenceIds)) {
            if (-not $EvidenceChecks.ContainsKey([string] $Id)) { $EvidenceChecks[[string] $Id] = [System.Collections.Generic.List[string]]::new() }
            $EvidenceChecks[[string] $Id].Add([string] $Check.Id)
        }
    }
    $Categories = if ($null -ne $Assessment) { @($Assessment.Categories) } else { @() }
    $Exceptions = if ($null -ne $Assessment) { @($Assessment.Exceptions) } else { @() }
    $Sections = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Assessment) {
        foreach ($Entry in @(@('summary','Executive summary'),@('posture','Assessment posture'),@('scope','Scope'),@('top-findings','Top findings'),@('categories','Category summary'),@('checks','Checks summary'),@('findings','Detailed findings'),@('resources','Resources summary'),@('evidence','Evidence appendix'),@('exceptions','Exceptions'),@('methodology','Methodology and coverage'),@('metadata','Report metadata'))) {
            if ($Entry[0] -eq 'top-findings' -and $Findings.Count -eq 0) { continue }
            if ($Entry[0] -eq 'findings' -and $Findings.Count -eq 0) { continue }
            if ($Entry[0] -eq 'resources' -and $Resources.Count -eq 0) { continue }
            if ($Entry[0] -eq 'evidence' -and ($Evidence.Count -eq 0 -or (V $PrintConfig 'IncludeEvidenceAppendix' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'checks' -and ($Checks.Count -eq 0 -or (V $PrintConfig 'IncludeChecks' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'exceptions' -and ($Exceptions.Count -eq 0 -or (V $PrintConfig 'IncludeExceptions' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'categories' -and $Categories.Count -eq 0) { continue }
            $Sections.Add($Entry)
        }
    }
    else {
        foreach ($Entry in @(@('summary','Report summary'),@('scope','Sections'))) { $Sections.Add($Entry) }
        if (@(V $ReportPrintConfig 'Tables' @()).Count -gt 0) { $Sections.Add(@('inventory-tables',[string](V $ReportPrintConfig 'TableSectionTitle' 'Inventory tables'))) }
        $Sections.Add(@('metadata','Report metadata'))
    }

    [void] $B.AppendLine('<article class="psi-print-document" id="psi-print-document" aria-label="Printable report" hidden>')
    [void] $B.AppendLine('<header class="psi-print-running"><strong>' + (E $ReportTitle) + '</strong><span>' + (E $Target) + ' | ' + (E $Generated) + ' | PSInsightHTML v' + (E $Version) + '</span></header>')
    [void] $B.AppendLine('<section class="psi-print-cover"><p class="psi-print-kicker">' + (E $PrintDisplay.ReportIdentity) + '</p><h1>' + (E $ReportTitle) + '</h1><p class="psi-print-subtitle">' + (E (V $Report 'Subtitle')) + '</p>')
    if ($null -ne $Assessment) { [void] $B.AppendLine('<p class="psi-print-assessment">' + (E (V $Assessment 'Name')) + '</p>') }
    if ($null -ne $Assessment) {
        [void] $B.AppendLine('<dl class="psi-print-cover-grid">' + (TextLine 'Target' $Target) + (TextLine 'Scope' (V $Assessment 'Scope')) + (TextLine 'Decision' $Decision) + (TextLine $ScoreLabel $Score) + (TextLine 'Evidence coverage' $CoverageText) + (TextLine 'Generated' $Generated) + (TextLine 'Module version' $Version) + '</dl><p class="psi-print-cover-foot">Standalone report | Complete assessment snapshot</p></section>')
    } else {
        [void] $B.AppendLine('<dl class="psi-print-cover-grid">' + (TextLine 'Scope' (V $ReportPrintConfig 'Scope')) + (TextLine 'Collection profile' (V $ReportPrintConfig 'Profile')) + (TextLine 'Evidence coverage' $CoverageText) + (TextLine 'Generated' $Generated) + (TextLine 'Module version' $Version) + '</dl><p class="psi-print-cover-foot">' + (E (V $ReportPrintConfig 'CoverFoot' 'Standalone report | Inventory observations')) + '</p></section>')
    }
    [void] $B.AppendLine('<nav class="psi-print-contents" aria-label="Document contents"><h2>Contents</h2><ol>')
    for ($I=0; $I -lt $Sections.Count; $I++) { [void] $B.AppendLine('<li><a href="#psi-print-' + $Sections[$I][0] + '"><span>' + ($I+1) + '</span>' + (E $Sections[$I][1]) + '</a></li>') }
    [void] $B.AppendLine('</ol></nav>')
    $Number = 0
    foreach ($Entry in $Sections) {
        $Number++
        $Id = $Entry[0]
        [void] $B.AppendLine((Section $Id ('{0:d2}' -f $Number) $Entry[1]))
        switch ($Id) {
            'summary' {
                if ($null -ne $Assessment) {
                    $Counts = $Assessment.ScoreExplanation.Counts
                    [void] $B.AppendLine('<p class="psi-print-lead">' + (E (V $Assessment 'Description')) + '</p><dl class="psi-print-metrics">' + (TextLine 'Decision' $Decision) + (TextLine 'Score' $Score) + (TextLine 'Coverage' $CoverageText) + (TextLine 'Blockers' $Counts.Blockers) + (TextLine 'Review' $Counts.Review) + (TextLine 'Ready' $Counts.Ready) + (TextLine 'Not Tested' $Counts.NotTested) + '</dl>')
                    [void] $B.AppendLine('<h3>Primary reasons</h3><ul>')
                    foreach ($Reason in @($Assessment.ScoreExplanation.Reasons)) { [void] $B.AppendLine('<li>' + (E (ReasonText $Reason)) + '</li>') }
                    [void] $B.AppendLine('</ul><h3>Recommended next actions</h3><ul>')
                    foreach ($Action in @($Assessment.Recommendations)) { [void] $B.AppendLine('<li>' + (E $Action) + '</li>') }
                    [void] $B.AppendLine('</ul>')
                } else { [void] $B.AppendLine('<p class="psi-print-lead">' + (E (V $Report 'Subtitle')) + '</p><p>Observed records are presented without an assessment score or health verdict.</p>') }
            }
            'posture' { [void] $B.AppendLine('<dl class="psi-print-facts">' + (TextLine 'Overall decision' $Decision) + (TextLine 'Score' $Score) + (TextLine 'Assessment profile' (V $Assessment 'Profile')) + (TextLine 'Applicable checks' ($Checks.Count - $Assessment.ScoreExplanation.Counts.NotApplicable)) + (TextLine 'Not applicable' $Assessment.ScoreExplanation.Counts.NotApplicable) + '</dl><p>' + (E $Assessment.ScoreExplanation.CategoryFormula) + '</p>') }
            'scope' {
                if ($null -ne $Assessment) { [void] $B.AppendLine('<p>' + (E (V $Assessment 'Scope')) + '</p><dl class="psi-print-facts">' + (TextLine 'Target' $Target) + (TextLine 'Assessment type' (V $Assessment 'AssessmentType')) + (TextLine 'Profile' (V $Assessment 'Profile')) + (TextLine 'Linked resources' $Resources.Count) + (TextLine 'Linked evidence records' $Evidence.Count) + '</dl>') }
                else { [void] $B.AppendLine('<ul>'); foreach ($Part in $Report.Sections) { [void] $B.AppendLine('<li>' + (E $Part.Title) + '</li>') }; [void] $B.AppendLine('</ul>') }
            }
            'inventory-tables' {
                $SelectedIds = @(V $ReportPrintConfig 'Tables' @())
                foreach ($Part in $Report.Sections) {
                    foreach ($ReportRow in $Part.Rows) {
                        foreach ($Component in $ReportRow.Components) {
                            if ($Component.Type -ne 'Table' -or $Component.Properties.Id -notin $SelectedIds) { continue }
                            $Properties=$Component.Properties
                            $Columns=@($Properties.Columns | Select-Object -First 7)
                            [void] $B.AppendLine('<h3>' + (E $Properties.Title) + '</h3>')
                            $Headers=@(foreach ($Column in $Columns) { if ($Properties.ColumnLabels.ContainsKey([string]$Column)) { [string]$Properties.ColumnLabels[[string]$Column] } else { [string]$Column } })
                            $TableRows=@(foreach ($Record in @($Properties.Data)) {
                                $Cells=@(foreach ($Column in $Columns) {
                                    $Value=Get-PSIProperty -InputObject $Record -Name ([string]$Column) -DefaultValue $null
                                    if ($null -eq $Value) { '' } elseif ($Value -is [array]) { E ($Value -join ', ') } else { E $Value }
                                })
                                Row $Cells
                            })
                            [void] $B.AppendLine((Table $Headers $TableRows))
                        }
                    }
                }
            }
            'top-findings' {
                [void] $B.AppendLine('<ol class="psi-print-priority">')
                foreach ($Finding in @($Findings | Select-Object -First 6)) { [void] $B.AppendLine('<li><strong>' + (E $Finding.Title) + '</strong> ' + (Status $Finding.Severity) + '<span>' + (E $Finding.Category) + '</span><p>' + (E $Finding.Summary) + '</p></li>') }
                [void] $B.AppendLine('</ol>')
            }
            'categories' {
                $Rows = @()
                foreach ($Category in $Categories) {
                    $Members = @($Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
                    $Cells = @((E $Category.Name), (E $(if ($null -eq $Category.Score) { 'N/A' } else { "$($Category.Score)%" })), (Status $Category.Status))
                    foreach ($State in @('Ready','Review','Blocked','NotTested')) { $Cells += [string] @($Members | Where-Object { $_.Status -eq $State }).Count }
                    $Rows += Row $Cells
                }
                [void] $B.AppendLine((Table @('Category','Score','Status','Ready','Review','Blocked','Not Tested') $Rows))
            }
            'checks' {
                [void] $B.AppendLine('<p>' + $Checks.Count + ' checks in the complete assessment. Status labels remain readable in grayscale.</p>')
                foreach ($Category in $Categories) {
                    $Members = @($Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
                    if ($Members.Count -eq 0) { continue }
                    [void] $B.AppendLine('<h3>' + (E $Category.Name) + '</h3>')
                    $Rows = @()
                    foreach ($Check in $Members) {
                        $Cells = foreach ($Field in $PrintDisplay.Checks) {
                            $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Checks -Record $Check -Property $Field.Property) -Format $Field.Format
                            if ($Field.Format -eq 'Status' -and $Value) { Status $Value } else { E $Value }
                        }
                        $Rows += Row $Cells
                    }
                    [void] $B.AppendLine((Table @($PrintDisplay.Checks | ForEach-Object { $_.Label }) $Rows))
                }
            }
            'findings' {
                foreach ($Finding in $Findings) {
                    $Facts = [System.Text.StringBuilder]::new()
                    foreach ($Field in $PrintDisplay.Findings) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Findings -Record $Finding -Property $Field.Property) -Format $Field.Format
                        if ($Value) { [void] $Facts.Append((TextLine $Field.Label $Value)) }
                    }
                    [void] $B.AppendLine('<article class="psi-print-finding"><h3>' + (E $Finding.Title) + '</h3><p class="psi-print-record-meta">' + (E $Finding.Id) + ' | ' + (E $Finding.Category) + ' | ' + (Status $Finding.Severity) + ' | ' + (Status $Finding.Status) + '</p><p>' + (E $Finding.Summary) + '</p><dl class="psi-print-facts">' + $Facts.ToString() + '</dl></article>')
                }
            }
            'resources' {
                $Columns = @($PrintDisplay.Resources)
                $Rows = @()
                foreach ($Resource in $Resources) {
                    $Cells = foreach ($Column in $Columns) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Resources -Record $Resource -Property $Column.Property) -Format $Column.Format
                        if ($Column.Format -eq 'Status' -and $Value) { Status $Value } else { E $Value }
                    }
                    $Rows += Row $Cells
                }
                [void] $B.AppendLine((Table @($Columns | ForEach-Object { $_.Label }) $Rows))
            }
            'evidence' {
                [void] $B.AppendLine('<p>Summaries and references only. Raw evidence Data payloads are excluded.</p>')
                foreach ($Item in $Evidence) {
                    $CheckIds = if ($EvidenceChecks.ContainsKey([string] $Item.Id)) { @($EvidenceChecks[[string] $Item.Id]) } else { @() }
                    $Facts = [System.Text.StringBuilder]::new()
                    foreach ($Field in $PrintDisplay.Evidence) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Evidence -Record $Item -Property $Field.Property -CheckIds $CheckIds) -Format $Field.Format
                        if ($Value) { [void] $Facts.Append((TextLine $Field.Label $Value)) }
                    }
                    [void] $B.AppendLine('<article class="psi-print-evidence"><h3>' + (E $Item.Title) + '</h3><dl class="psi-print-facts">' + $Facts.ToString() + '</dl></article>')
                }
            }
            'exceptions' {
                foreach ($Item in $Exceptions) { [void] $B.AppendLine('<article class="psi-print-finding"><h3>' + (E $Item.Title) + '</h3><dl class="psi-print-facts">' + (TextLine 'Status' $Item.Status) + (TextLine 'Scope' (@($Item.ResourceIds) -join ', ')) + (TextLine 'Reason' $Item.Reason) + (TextLine 'Owner' $Item.Owner) + (TextLine 'Expires' $(if ($null -ne $Item.ExpiresAt) { ([datetime] $Item.ExpiresAt).ToString('yyyy-MM-dd') } else { '' })) + (TextLine 'Check' $Item.CheckId) + (TextLine 'Finding' $Item.FindingId) + '</dl></article>') }
            }
            'methodology' {
                [void] $B.AppendLine('<p>Evidence coverage: <strong>' + (E $CoverageText) + '</strong>. Coverage describes requested observations available for review; it is separate from ' + (E $ScoreLabel.ToLowerInvariant()) + '. Missing or partial evidence limits interpretation and should be reviewed before approval.</p>')
                $Collection = V $Meta 'CollectionCounts' $null
                if ($null -ne $Collection) { [void] $B.AppendLine('<dl class="psi-print-facts">'); foreach ($Field in @('Requested','Collected','Partial','Failed','NotSupported','NotTested','NotRequested')) { [void] $B.AppendLine((TextLine $Field (V $Collection $Field))) }; [void] $B.AppendLine('</dl>') }
                [void] $B.AppendLine('<p>Scoring: ' + (E $Assessment.ScoreExplanation.CategoryFormula) + ' Not Applicable checks are excluded. Not Tested and Unknown checks score zero until assessed.</p>')
                $Method = V $PrintConfig 'MethodologyText' ''
                if ($Method) { [void] $B.AppendLine('<p>' + (E $Method) + '</p>') }
            }
            'metadata' {
                [void] $B.AppendLine('<dl class="psi-print-facts">' + (TextLine 'Report' $ReportTitle) + (TextLine 'Assessment' (V $Assessment 'Name')) + (TextLine 'Target' $Target) + (TextLine 'Generated' $Generated) + (TextLine 'PSInsightHTML' $Version) + (TextLine 'Profile' (V $Assessment 'Profile')) + '</dl>')
            }
        }
        [void] $B.AppendLine('</section>')
    }
    [void] $B.AppendLine('<footer class="psi-print-end">' + (E $ReportTitle) + ' | ' + (E $Target) + ' | PSInsightHTML v' + (E $Version) + '</footer></article>')
    $B.ToString()
}

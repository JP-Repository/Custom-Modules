function ConvertTo-PSIHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [bool] $EnableReportPrint = $true
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object].'
    }
    $TableIds = Assert-PSIReportIds -Sections $SectionsProperty.Value

    $Title = ConvertTo-PSIHtmlEncoded -Value $Report.Title
    $Subtitle = ConvertTo-PSIHtmlEncoded -Value $Report.Subtitle
    $GeneratedOn = ConvertTo-PSIHtmlEncoded -Value ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $Theme = [string] $Report.Theme
    if ($Theme -notin @('Light', 'Dark', 'Auto')) {
        throw "Theme must be Light, Dark, or Auto. Found '$Theme'."
    }
    $ModuleVersion = ConvertTo-PSIHtmlEncoded -Value $Report.ModuleVersion

    $ThemeStylesheetPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/CSS/psi-theme.css'
    if (-not (Test-Path -LiteralPath $ThemeStylesheetPath -PathType Leaf)) {
        throw "The PSInsightHTML theme stylesheet is missing: '$ThemeStylesheetPath'."
    }
    $ThemeStylesheet = Get-Content -LiteralPath $ThemeStylesheetPath -Raw -ErrorAction Stop
    $VisualStylesheetPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/CSS/PSInsightHTML.css'
    if (-not (Test-Path -LiteralPath $VisualStylesheetPath -PathType Leaf)) {
        throw "The PSInsightHTML visual stylesheet is missing: '$VisualStylesheetPath'."
    }
    $ThemeStylesheet += "`n" + (Get-Content -LiteralPath $VisualStylesheetPath -Raw -ErrorAction Stop)
    $SectionMarkup = [System.Text.StringBuilder]::new()
    $NavigationMarkup = [System.Text.StringBuilder]::new()
    $HasTableComponents = $false
    $HasDrillDownComponents = $false
    $HasInsightComponents = $false
    $SectionIndex = 0
    $FindingAnchors = Get-PSIFindingAnchors -Sections $SectionsProperty.Value
    $FindingIndex = 0
    $AssessmentNavigationMarkup = [System.Text.StringBuilder]::new()
    $SeenAssessmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Section in $SectionsProperty.Value) {
        $SectionTitle = ConvertTo-PSIHtmlEncoded -Value $Section.Title
        $SectionId = "psi-section-$SectionIndex"
        [void] $NavigationMarkup.AppendLine("      <a href=`"#$SectionId`">$SectionTitle</a>")
        $IsOverview = (Get-PSIProperty -InputObject $Section -Name 'IsOverview' -DefaultValue $false) -eq $true
        $AssessmentId = [string] (Get-PSIProperty -InputObject $Section -Name 'AssessmentId')
        $SectionContext = ''
        if ($IsOverview) {
            $SectionContext = ' data-psi-overview="true"'
            [void] $AssessmentNavigationMarkup.AppendLine("      <a data-psi-nav-assessment=`"overview`" href=`"#$SectionId`">Overview</a>")
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($AssessmentId)) {
                $EncodedAssessmentId = ConvertTo-PSIHtmlEncoded -Value $AssessmentId
                $SectionContext = " data-psi-assessment-key=`"$EncodedAssessmentId`""
            }
            if (-not [string]::IsNullOrWhiteSpace($AssessmentId) -and $SeenAssessmentIds.Add($AssessmentId)) {
                $AssessmentName = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Section -Name 'AssessmentName' -DefaultValue $Section.Title)
                [void] $AssessmentNavigationMarkup.AppendLine("      <a data-psi-nav-assessment=`"$EncodedAssessmentId`" href=`"#$SectionId`">$AssessmentName</a>")
            }
        }
        [void] $SectionMarkup.AppendLine("      <section class=`"psi-section`" id=`"$SectionId`" aria-label=`"$SectionTitle`"$SectionContext>")
        [void] $SectionMarkup.AppendLine("        <h2>$SectionTitle</h2>")

        $RowsProperty = $Section.PSObject.Properties['Rows']
        if ($null -eq $RowsProperty -or $RowsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
            throw "Section '$($Section.Title)' does not contain a valid Rows collection."
        }

        $RowIndex = 0
        foreach ($Row in $RowsProperty.Value) {
            $Columns = [int] $Row.Columns
            if ($Columns -lt 1 -or $Columns -gt 12) {
                throw "Row Columns must be between 1 and 12. Found '$Columns'."
            }

            $OverviewRowAttribute = if ($IsOverview) { " data-psi-overview-row=`"$RowIndex`"" } else { '' }
            [void] $SectionMarkup.AppendLine("        <div class=`"psi-row`"$OverviewRowAttribute style=`"--psi-row-columns: $Columns`">")
            $RowIndex++
            $ComponentsProperty = $Row.PSObject.Properties['Components']
            if ($null -eq $ComponentsProperty -or $ComponentsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
                throw "A row in section '$($Section.Title)' does not contain a valid Components collection."
            }

            $KpiCount = @($ComponentsProperty.Value | Where-Object { $_.Type -eq 'KPI' }).Count
            $InsightCount = @($ComponentsProperty.Value | Where-Object { $_.Type -eq 'Insight' }).Count
            $KpiSpan = 12
            if ($KpiCount -gt 0) {
                $KpiSpan = [math]::Max(1, [math]::Floor($Columns / $KpiCount))
            }

            foreach ($Component in $ComponentsProperty.Value) {
                $Properties = $Component.Properties
                $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Properties -Name 'Status')) -AllowInvalid
                if ($null -eq $Status) {
                    $Status = 'Unknown'
                }
                $StatusClass = $Status.ToLowerInvariant()
                if ($Status -eq 'NotChecked') {
                    $StatusClass = 'not-checked'
                }

                switch ([string] $Component.Type) {
                    'Text' {
                        $Text = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Text')
                        $Size = [string] (Get-PSIProperty -InputObject $Properties -Name 'Size')
                        if ($Size -notin @('Small', 'Normal', 'Large')) {
                            $Size = 'Normal'
                        }

                        $SizeClass = $Size.ToLowerInvariant()
                        [void] $SectionMarkup.AppendLine("          <div class=`"psi-text psi-text-$SizeClass`">$Text</div>")
                    }
                    'KeyValue' {
                        $KeyValueTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $KeyValueData = Get-PSIProperty -InputObject $Properties -Name 'Data'
                        $KeyValueSpan = [int] (Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue 6)
                        if ($KeyValueSpan -lt 1 -or $KeyValueSpan -gt 12) { throw 'KeyValue Span must be between 1 and 12.' }
                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-keyvalue-card`" style=`"--psi-component-span: $KeyValueSpan`">")
                        [void] $SectionMarkup.AppendLine("            <h3>$KeyValueTitle</h3>")
                        [void] $SectionMarkup.AppendLine('            <dl class="psi-keyvalue-list">')
                        foreach ($Key in $KeyValueData.Keys) {
                            $SafeKey = ConvertTo-PSIHtmlEncoded -Value $Key
                            $RawValue = Get-PSIProperty -InputObject $KeyValueData -Name ([string] $Key)
                            if ($null -eq $RawValue) { $ValueText = [string] [char] 0x2014 }
                            elseif ($RawValue -is [string] -or $RawValue.GetType().IsValueType) { $ValueText = [string] $RawValue }
                            else { $ValueText = ConvertTo-Json -InputObject $RawValue -Depth 5 -Compress }
                            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $ValueText
                            [void] $SectionMarkup.AppendLine("              <div class=`"psi-keyvalue-row`"><dt>$SafeKey</dt><dd>$SafeValue</dd></div>")
                        }
                        [void] $SectionMarkup.AppendLine('            </dl>')
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                    'KPI' {
                        $KpiTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $RequestedKpiSpan = Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue $null
                        $KpiComponentSpan = if ($null -eq $RequestedKpiSpan) { $KpiSpan } else { [int] $RequestedKpiSpan }
                        if ($KpiComponentSpan -lt 1 -or $KpiComponentSpan -gt 12) { throw 'KPI Span must be between 1 and 12.' }
                        $RawKpiValue = (Get-PSIProperty -InputObject $Properties -Name 'Value')
                        if ($null -eq $RawKpiValue) {
                            $KpiValueText = [string] [char] 0x2014
                        }
                        elseif ($RawKpiValue -is [string] -or $RawKpiValue.GetType().IsValueType) {
                            $KpiValueText = [string] $RawKpiValue
                        }
                        else {
                            $KpiValueText = ConvertTo-Json -InputObject $RawKpiValue -Depth 5 -Compress
                        }
                        $KpiValue = ConvertTo-PSIHtmlEncoded -Value $KpiValueText
                        $KpiSubtitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Subtitle')
                        $KpiTrend = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Trend')
                        $KpiAction = Get-PSIProperty -InputObject $Properties -Name 'Action'
                        $ActionType = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Type')
                        $ActionTarget = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Target')
                        $HasGenericAction = $ActionType -in @('ScrollTo', 'FilterTable') -and -not [string]::IsNullOrWhiteSpace($ActionTarget)
                        if ($ActionType -eq 'FilterTable') {
                            $ActionProperty = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Property')
                            $ActionValue = Get-PSIProperty -InputObject $KpiAction -Name 'Value'
                            $HasSimpleValue = $null -ne $ActionValue -and ($ActionValue -is [string] -or $ActionValue.GetType().IsValueType)
                            $HasGenericAction = $HasGenericAction -and -not [string]::IsNullOrWhiteSpace($ActionProperty) -and $HasSimpleValue
                        }
                        if ($HasGenericAction) {
                            $NormalizedAction = [ordered]@{ Type = if ($ActionType -eq 'ScrollTo') { 'ScrollTo' } else { 'FilterTable' }; Target = $ActionTarget }
                            if ($ActionType -eq 'FilterTable') {
                                $NormalizedAction['Property'] = $ActionProperty
                                $NormalizedAction['Value'] = $ActionValue
                            }
                            $ActionJson = ConvertTo-Json -InputObject $NormalizedAction -Depth 5 -Compress
                        }
                        else {
                            $ActionJson = ConvertTo-Json -InputObject $KpiAction -Depth 5 -Compress
                        }
                        $ActionAttribute = ConvertTo-PSIHtmlEncoded -Value $ActionJson
                        $KpiFilter = (Get-PSIProperty -InputObject $Properties -Name 'Filter')
                        $KpiFilterAttribute = ''
                        if ($null -ne $KpiFilter -and $KpiFilter.Count -gt 0) {
                            $KpiFilterJson = ConvertTo-Json -InputObject $KpiFilter -Depth 5 -Compress
                            $KpiFilterAttribute = ConvertTo-PSIHtmlEncoded -Value $KpiFilterJson
                        }
                        $KpiIconMarkup = ''
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon'))) {
                            $KpiIconMarkup = Get-PSIIcon -Name ([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon')) -Size 21
                        }
                        $DrillDown = @((Get-PSIProperty -InputObject $Properties -Name 'DrillDown'))
                        $IsDrillDown = $DrillDown.Count -gt 0 -and $null -ne $DrillDown[0]
                        $HasFilterAction = -not [string]::IsNullOrEmpty($KpiFilterAttribute)
                        if ($IsDrillDown) {
                            $HasDrillDownComponents = $true
                            $DrillDownJson = ConvertTo-Json -InputObject $DrillDown -Depth 10 -Compress
                            $DrillDownAttribute = ConvertTo-PSIHtmlEncoded -Value $DrillDownJson
                        }
                        if ($IsDrillDown -or $HasFilterAction -or $HasGenericAction) {
                            $DataAttributes = ''
                            if ($IsDrillDown) {
                                $DataAttributes += " data-psi-drilldown data-psi-records=`"$DrillDownAttribute`""
                            }
                            if ($HasFilterAction) {
                                $DataAttributes += " data-psi-filter-action=`"$KpiFilterAttribute`""
                            }
                            $KpiAccessibleText = if ($IsDrillDown) { "View details for {0}: {1}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title'), $KpiValueText } elseif ($HasFilterAction -or $ActionType -eq 'FilterTable') { "Apply filter from {0}: {1}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title'), $KpiValueText } else { "Go to {0}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title') }
                            $KpiAccessibleName = ConvertTo-PSIHtmlEncoded -Value $KpiAccessibleText
                            if ($IsDrillDown) {
                                $DataAttributes += " data-psi-detail-title=`"$KpiTitle`""
                            }
                            [void] $SectionMarkup.AppendLine("          <button type=`"button`" class=`"psi-kpi-card psi-kpi-clickable psi-status-$StatusClass`" data-status=`"$Status`" data-action=`"$ActionAttribute`"$DataAttributes aria-label=`"$KpiAccessibleName`" style=`"--psi-component-span: $KpiComponentSpan`">")
                        }
                        else {
                            [void] $SectionMarkup.AppendLine("          <article class=`"psi-kpi-card psi-status-$StatusClass`" data-status=`"$Status`" data-action=`"$ActionAttribute`" style=`"--psi-component-span: $KpiComponentSpan`">")
                        }
                        if ($KpiIconMarkup) {
                            [void] $SectionMarkup.AppendLine("            <span class=`"psi-kpi-icon`">$KpiIconMarkup</span>")
                        }
                        [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-title`">$KpiTitle</p>")
                        [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-value`">$KpiValue</p>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Subtitle'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-subtitle`">$KpiSubtitle</p>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Trend'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-trend`">$KpiTrend</p>")
                        }
                        if ($IsDrillDown -or $HasFilterAction -or $HasGenericAction) {
                            $ViewDetailsIcon = Get-PSIIcon -Name 'arrow' -Size 16
                            $ActionHint = if ($IsDrillDown -or $HasFilterAction) { 'View details' } elseif ($ActionType -eq 'FilterTable') { 'Filter table' } else { 'Go to section' }
                            [void] $SectionMarkup.AppendLine("            <span class=`"psi-kpi-drill-hint`">$ActionHint $ViewDetailsIcon</span>")
                            [void] $SectionMarkup.AppendLine('          </button>')
                        }
                        else {
                            [void] $SectionMarkup.AppendLine('          </article>')
                        }
                    }
                    'Insight' {
                        $HasInsightComponents = $true
                        $InsightTitleText = [string] (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $InsightTitle = ConvertTo-PSIHtmlEncoded -Value $InsightTitleText
                        $InsightRawValue = (Get-PSIProperty -InputObject $Properties -Name 'Value')
                        if ($null -eq $InsightRawValue) { $InsightValueText = [string] [char] 0x2014 }
                        elseif ($InsightRawValue -is [string] -or $InsightRawValue.GetType().IsValueType) { $InsightValueText = [string] $InsightRawValue }
                        else { $InsightValueText = ConvertTo-Json -InputObject $InsightRawValue -Depth 5 -Compress }
                        $InsightValue = ConvertTo-PSIHtmlEncoded -Value $InsightValueText
                        $InsightDescription = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $InsightFilter = (Get-PSIProperty -InputObject $Properties -Name 'Filter')
                        $CanOpenEvidence = $null -ne $InsightFilter -and $InsightFilter.Count -gt 0
                        $InsightClasses = "psi-insight-card psi-status-$StatusClass"
                        $InsightSpan = if ($InsightCount -gt 0) { [math]::Max(1, [math]::Floor($Columns / $InsightCount)) } else { 12 }
                        $InsightIcon = ''
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon'))) {
                            $InsightIcon = Get-PSIIcon -Name ([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon')) -Size 20
                        }
                        if ($CanOpenEvidence) {
                            $HasDrillDownComponents = $true
                            $InsightDefinition = Resolve-PSIEvidenceDefinition -Filter $InsightFilter `
                                -EvidenceColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns')) `
                                -ExportColumns @((Get-PSIProperty -InputObject $Properties -Name 'ExportColumns')) `
                                -Labels (Get-PSIProperty -InputObject $Properties -Name 'ColumnLabels')
                            $InsightJson = ConvertTo-Json -InputObject $InsightDefinition -Depth 8 -Compress
                            $InsightAttribute = ConvertTo-PSIHtmlEncoded -Value $InsightJson
                            $InsightAccessibleName = ConvertTo-PSIHtmlEncoded -Value ("View evidence for {0}: {1}" -f $InsightTitleText, $InsightValueText)
                            [void] $SectionMarkup.AppendLine("          <button type=`"button`" class=`"$InsightClasses psi-insight-clickable`" data-status=`"$Status`" data-psi-insight=`"$InsightAttribute`" data-psi-detail-title=`"$InsightTitle`" aria-label=`"$InsightAccessibleName`" style=`"--psi-component-span: $InsightSpan`">")
                        }
                        else {
                            [void] $SectionMarkup.AppendLine("          <article class=`"$InsightClasses`" data-status=`"$Status`" style=`"--psi-component-span: $InsightSpan`">")
                        }
                        if ($InsightIcon) { [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-icon`">$InsightIcon</span>") }
                        [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-title`">$InsightTitle</span>")
                        [void] $SectionMarkup.AppendLine("            <strong class=`"psi-insight-value`">$InsightValue</strong>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Description'))) { [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-description`">$InsightDescription</span>") }
                        if ($CanOpenEvidence) { [void] $SectionMarkup.AppendLine('            <span class="psi-kpi-drill-hint">View evidence &rarr;</span>') }
                        if ($CanOpenEvidence) { [void] $SectionMarkup.AppendLine('          </button>') } else { [void] $SectionMarkup.AppendLine('          </article>') }
                    }
                    'Finding' {
                        $FindingDomId = $FindingAnchors[$FindingIndex].Id
                        $FindingIndex++
                        $FindingTitleText = [string] (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $FindingTitle = ConvertTo-PSIHtmlEncoded -Value $FindingTitleText
                        $FindingCategory = [string] (Get-PSIProperty -InputObject $Properties -Name 'Category')
                        $FindingDescription = [string] (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $FindingAffectedObject = [string] (Get-PSIProperty -InputObject $Properties -Name 'AffectedObject')
                        $FindingImpact = [string] (Get-PSIProperty -InputObject $Properties -Name 'Impact')
                        $FindingRecommendation = [string] (Get-PSIProperty -InputObject $Properties -Name 'Recommendation')
                        $FindingRuleId = [string] (Get-PSIProperty -InputObject $Properties -Name 'RuleId')
                        $FindingSource = [string] (Get-PSIProperty -InputObject $Properties -Name 'Source')
                        $EvidenceDefinition = Resolve-PSIEvidenceDefinition `
                            -TableId ([string] (Get-PSIProperty -InputObject $Properties -Name 'EvidenceTableId')) `
                            -Filter (Get-PSIProperty -InputObject $Properties -Name 'EvidenceFilter') `
                            -EvidenceColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns' -DefaultValue @())) `
                            -ExportColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns' -DefaultValue @())) `
                            -UseVisibleColumns
                        if ($null -ne $EvidenceDefinition -and -not $TableIds.Contains([string] $EvidenceDefinition.tableId)) {
                            Write-Warning "Finding '$FindingTitleText' references missing evidence table '$($EvidenceDefinition.tableId)'; its evidence action was omitted."
                            $EvidenceDefinition = $null
                        }
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-finding-card psi-status-$StatusClass`" id=`"$FindingDomId`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-finding-heading`"><span class=`"psi-status-badge psi-status-$StatusClass`">$Status</span>")
                        if (-not [string]::IsNullOrWhiteSpace($FindingCategory)) {
                            [void] $SectionMarkup.AppendLine('              <span class="psi-finding-category">' + (ConvertTo-PSIHtmlEncoded -Value $FindingCategory) + '</span>')
                        }
                        [void] $SectionMarkup.AppendLine('            </div>')
                        [void] $SectionMarkup.AppendLine("            <h3>$FindingTitle</h3>")
                        if (-not [string]::IsNullOrWhiteSpace($FindingDescription)) {
                            [void] $SectionMarkup.AppendLine('            <p class="psi-finding-description">' + (ConvertTo-PSIHtmlEncoded -Value $FindingDescription) + '</p>')
                        }
                        if (-not [string]::IsNullOrWhiteSpace($FindingAffectedObject) -or -not [string]::IsNullOrWhiteSpace($FindingImpact)) {
                            [void] $SectionMarkup.AppendLine('            <dl class="psi-finding-details">')
                            if (-not [string]::IsNullOrWhiteSpace($FindingAffectedObject)) {
                                [void] $SectionMarkup.AppendLine('              <div><dt>Affected object</dt><dd>' + (ConvertTo-PSIHtmlEncoded -Value $FindingAffectedObject) + '</dd></div>')
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingImpact)) {
                                [void] $SectionMarkup.AppendLine('              <div><dt>Impact</dt><dd>' + (ConvertTo-PSIHtmlEncoded -Value $FindingImpact) + '</dd></div>')
                            }
                            [void] $SectionMarkup.AppendLine('            </dl>')
                        }
                        if (-not [string]::IsNullOrWhiteSpace($FindingRecommendation)) {
                            [void] $SectionMarkup.AppendLine('            <div class="psi-finding-recommendation"><strong>Recommendation</strong><p>' + (ConvertTo-PSIHtmlEncoded -Value $FindingRecommendation) + '</p></div>')
                        }
                        if ($null -ne $EvidenceDefinition -or -not [string]::IsNullOrWhiteSpace($FindingRuleId) -or -not [string]::IsNullOrWhiteSpace($FindingSource)) {
                            [void] $SectionMarkup.AppendLine('            <footer class="psi-finding-footer">')
                            if ($null -ne $EvidenceDefinition) {
                                $HasDrillDownComponents = $true
                                $HasInsightComponents = $true
                                $EvidenceAttribute = ConvertTo-PSIHtmlEncoded -Value (ConvertTo-Json -InputObject $EvidenceDefinition -Depth 8 -Compress)
                                $EvidenceDescription = ConvertTo-PSIHtmlEncoded -Value $FindingDescription
                                $EvidenceName = ConvertTo-PSIHtmlEncoded -Value ("View evidence for $FindingTitleText")
                                [void] $SectionMarkup.AppendLine("              <button type=`"button`" class=`"psi-finding-evidence`" data-psi-insight=`"$EvidenceAttribute`" data-psi-detail-title=`"$FindingTitle`" data-psi-evidence-description=`"$EvidenceDescription`" aria-label=`"$EvidenceName`">View Evidence $(Get-PSIIcon -Name 'arrow' -Size 15)</button>")
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingRuleId)) {
                                [void] $SectionMarkup.AppendLine('              <span class="psi-finding-meta">Rule: ' + (ConvertTo-PSIHtmlEncoded -Value $FindingRuleId) + '</span>')
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingSource)) {
                                [void] $SectionMarkup.AppendLine('              <span class="psi-finding-meta">Source: ' + (ConvertTo-PSIHtmlEncoded -Value $FindingSource) + '</span>')
                            }
                            [void] $SectionMarkup.AppendLine('            </footer>')
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Status' {
                        $Label = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Label')
                        $Message = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Message')
                        [void] $SectionMarkup.AppendLine("          <div class=`"psi-status-panel psi-status-$StatusClass`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <span class=`"psi-status-indicator`" aria-hidden=`"true`"></span>")
                        [void] $SectionMarkup.AppendLine("            <div><strong>$Status</strong>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Label'))) {
                            [void] $SectionMarkup.AppendLine("              <span class=`"psi-status-label`">$Label</span>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Message'))) {
                            [void] $SectionMarkup.AppendLine("              <p>$Message</p>")
                        }
                        [void] $SectionMarkup.AppendLine('            </div>')
                        [void] $SectionMarkup.AppendLine('          </div>')
                    }
                    'Alert' {
                        $AlertTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $AlertMessage = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Message')
                        $AlertAction = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Action')
                        $Timestamp = (Get-PSIProperty -InputObject $Properties -Name 'Timestamp')
                        $Details = (Get-PSIProperty -InputObject $Properties -Name 'Details')
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-alert psi-status-$StatusClass`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-alert-heading`"><span class=`"psi-alert-severity`">$Status</span><h3>$AlertTitle</h3></div>")
                        [void] $SectionMarkup.AppendLine("            <p>$AlertMessage</p>")
                        if ($null -ne $Timestamp) {
                            $TimestampText = ConvertTo-PSIHtmlEncoded -Value ([string] $Timestamp)
                            [void] $SectionMarkup.AppendLine("            <time class=`"psi-alert-timestamp`">$TimestampText</time>")
                        }
                        if ($null -ne $Details) {
                            if ($Details -is [string] -or $Details.GetType().IsPrimitive) {
                                $DetailsText = [string] $Details
                            }
                            else {
                                $DetailsText = ConvertTo-Json -InputObject $Details -Depth 5 -Compress
                            }
                            $DetailsText = ConvertTo-PSIHtmlEncoded -Value $DetailsText
                            [void] $SectionMarkup.AppendLine("            <details><summary>Details</summary><p>$DetailsText</p></details>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Action'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-alert-action`"><strong>Suggested action:</strong> $AlertAction</p>")
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Recommendation' {
                        $RecommendationTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $Description = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $ActionText = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'ActionText')
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-recommendation psi-status-$StatusClass`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <span class=`"psi-recommendation-severity`">$Status</span>")
                        [void] $SectionMarkup.AppendLine("            <h3>$RecommendationTitle</h3>")
                        [void] $SectionMarkup.AppendLine("            <p>$Description</p>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'ActionText'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-recommendation-action`"><strong>Suggested action:</strong> $ActionText</p>")
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Table' {
                        $HasTableComponents = $true
                        $TableTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $ConfiguredTableId = [string] (Get-PSIProperty -InputObject $Properties -Name 'Id')
                        $TableId = if ([string]::IsNullOrWhiteSpace($ConfiguredTableId)) { 'psi-table-' + [guid]::NewGuid().ToString('N') } else { ConvertTo-PSIHtmlEncoded -Value $ConfiguredTableId }
                        $TableSpan = [int] (Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue 12)
                        if ($TableSpan -lt 1 -or $TableSpan -gt 12) { throw 'Table Span must be between 1 and 12.' }
                        $TableData = @((Get-PSIProperty -InputObject $Properties -Name 'Data'))
                        $TableColumns = @((Get-PSIProperty -InputObject $Properties -Name 'Columns'))
                        $ColumnLabels = (Get-PSIProperty -InputObject $Properties -Name 'ColumnLabels')
                        $Filters = @((Get-PSIProperty -InputObject $Properties -Name 'Filters'))
                        $Conditions = @((Get-PSIProperty -InputObject $Properties -Name 'Conditions' -DefaultValue @()))
                        $NullText = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'NullValueText')
                        $EmptyMessage = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'EmptyMessage')
                        if ($TableData.Count -eq 0 -and $EmptyMessage -eq 'No records match your filters.') { $EmptyMessage = 'No data available.' }
                        $PageSize = [int] (Get-PSIProperty -InputObject $Properties -Name 'PageSize')
                        $SearchEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableSearch')
                        $SortingEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableSorting')
                        $PaginationEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnablePagination')
                        $ExportEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableExport')
                        $TableExportMarkup = ''
                        $TableExportAttribute = ''
                        if ($ExportEnabled) {
                            $ExportDefinition = [ordered]@{
                                columns = @((Get-PSIProperty -InputObject $Properties -Name 'ExportColumns'))
                                labels = $ColumnLabels
                                formats = @((Get-PSIProperty -InputObject $Properties -Name 'ExportFormats'))
                                fileName = [string] (Get-PSIProperty -InputObject $Properties -Name 'ExportFileName')
                                worksheetName = [string] (Get-PSIProperty -InputObject $Properties -Name 'WorksheetName')
                            }
                            $TableExportAttribute = ' data-psi-export-config="' + (ConvertTo-PSIHtmlEncoded -Value (ConvertTo-Json -InputObject $ExportDefinition -Depth 5 -Compress)) + '"'
                            $TableExportMarkup = Get-PSIExportToolbar -Scope Table -Formats @((Get-PSIProperty -InputObject $Properties -Name 'ExportFormats'))
                        }
                        $ColumnCount = [math]::Max(1, $TableColumns.Count)
                        $EmptyRowHidden = if ($TableData.Count -eq 0) { '' } else { ' hidden' }

                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-table-card`" id=`"$TableId`" data-psi-table=`"true`" data-page-size=`"$PageSize`" data-search-enabled=`"$($SearchEnabled.ToString().ToLowerInvariant())`" data-sort-enabled=`"$($SortingEnabled.ToString().ToLowerInvariant())`" data-pagination-enabled=`"$($PaginationEnabled.ToString().ToLowerInvariant())`"$TableExportAttribute style=`"--psi-component-span: $TableSpan`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-table-heading`"><h3>$TableTitle</h3><span class=`"psi-table-result-count`" data-psi-result-count aria-live=`"polite`">$($TableData.Count) results</span></div>")
                        [void] $SectionMarkup.AppendLine('            <div class="psi-table-toolbar">')
                        if ($SearchEnabled) {
                            [void] $SectionMarkup.AppendLine('              <label class="psi-table-search"><span class="psi-visually-hidden">Search this table</span><input type="search" data-psi-search placeholder="Search records" autocomplete="off"></label>')
                        }
                        if ($Filters.Count -gt 0) {
                            if ($Filters.Count -gt 2) {
                                [void] $SectionMarkup.AppendLine("              <details class=`"psi-table-filter-disclosure`"><summary>Filters ($($Filters.Count))</summary>")
                                [void] $SectionMarkup.AppendLine('                <div class="psi-table-filterbar" data-psi-filterbar>')
                            }
                            else {
                                [void] $SectionMarkup.AppendLine('              <div class="psi-table-filterbar psi-table-filterbar-inline" data-psi-filterbar>')
                            }
                            [void] $SectionMarkup.AppendLine('              <div class="psi-table-filter-controls">')
                            for ($FilterIndex = 0; $FilterIndex -lt $Filters.Count; $FilterIndex++) {
                                $FilterDefinition = $Filters[$FilterIndex]
                                $FilterProperty = ConvertTo-PSIHtmlEncoded -Value $FilterDefinition.Property
                                $FilterLabel = ConvertTo-PSIHtmlEncoded -Value $FilterDefinition.Label
                                $FilterType = [string] $FilterDefinition.Type
                                $FilterElementId = "$TableId-filter-$FilterIndex"
                                $MultipleAttribute = if ($FilterType -eq 'MultiSelect') { ' multiple aria-describedby="psi-filter-help-' + $FilterElementId + '"' } else { '' }
                                [void] $SectionMarkup.AppendLine("                <label class=`"psi-filter-control`" for=`"$FilterElementId`"><span>$FilterLabel</span><select id=`"$FilterElementId`" data-psi-filter-property=`"$FilterProperty`" data-psi-filter-label=`"$FilterLabel`" data-psi-filter-type=`"$FilterType`"$MultipleAttribute>")
                                if ($FilterType -eq 'Select') {
                                    [void] $SectionMarkup.AppendLine('                  <option value="" selected>All</option>')
                                }
                                foreach ($FilterValue in $FilterDefinition.Values) {
                                    $FilterValueText = ConvertTo-PSIHtmlEncoded -Value $FilterValue
                                    [void] $SectionMarkup.AppendLine("                  <option value=`"$FilterValueText`">$FilterValueText</option>")
                                }
                                [void] $SectionMarkup.AppendLine('                </select></label>')
                                if ($FilterType -eq 'MultiSelect') {
                                    [void] $SectionMarkup.AppendLine("                <span class=`"psi-visually-hidden`" id=`"psi-filter-help-$FilterElementId`">Use the selection list to choose one or more values.</span>")
                                }
                            }
                            [void] $SectionMarkup.AppendLine('              </div>')
                            [void] $SectionMarkup.AppendLine('              </div>')
                            if ($Filters.Count -gt 2) { [void] $SectionMarkup.AppendLine('              </details>') }
                        }
                        [void] $SectionMarkup.AppendLine("              $TableExportMarkup")
                        [void] $SectionMarkup.AppendLine('            </div>')
                        if ($Filters.Count -gt 0) {
                            [void] $SectionMarkup.AppendLine('            <div class="psi-active-filter-row" hidden><span class="psi-active-filter-heading">Active filters</span><div class="psi-active-filter-list" data-psi-active-filters aria-live="polite"><span class="psi-active-filter-none">None</span></div><button type="button" class="psi-filter-clear-all" data-psi-clear-filters hidden>Clear all</button></div>')
                        }
                        [void] $SectionMarkup.AppendLine('            <div class="psi-table-scroll" role="region" aria-label="Scrollable table" tabindex="0">')
                        [void] $SectionMarkup.AppendLine("              <table data-psi-table-element id=`"$TableId-data`">")
                        [void] $SectionMarkup.AppendLine('                <thead><tr>')
                        if ($TableColumns.Count -eq 0) {
                            [void] $SectionMarkup.AppendLine('                  <th scope="col">Results</th>')
                        }
                        else {
                            for ($ColumnIndex = 0; $ColumnIndex -lt $TableColumns.Count; $ColumnIndex++) {
                                $ColumnName = [string] $TableColumns[$ColumnIndex]
                                $DisplayName = $ColumnName
                                if ($null -ne $ColumnLabels -and $ColumnLabels.ContainsKey($ColumnName)) {
                                    $DisplayName = [string] $ColumnLabels[$ColumnName]
                                }
                                $DisplayName = ConvertTo-PSIHtmlEncoded -Value $DisplayName
                                $SafeColumnName = ConvertTo-PSIHtmlEncoded -Value $ColumnName
                                if ($SortingEnabled) {
                                    [void] $SectionMarkup.AppendLine("                  <th scope=`"col`" data-psi-column=`"$SafeColumnName`" data-psi-sort-cell aria-sort=`"none`"><button type=`"button`" data-psi-sort=`"$ColumnIndex`">$DisplayName<span class=`"psi-sort-indicator`" aria-hidden=`"true`"></span></button></th>")
                                }
                                else {
                                    [void] $SectionMarkup.AppendLine("                  <th scope=`"col`" data-psi-column=`"$SafeColumnName`">$DisplayName</th>")
                                }
                            }
                        }
                        [void] $SectionMarkup.AppendLine('                </tr></thead>')
                        [void] $SectionMarkup.AppendLine('                <tbody data-psi-table-body>')

                        foreach ($Item in $TableData) {
                            $RowStatus = $null
                            foreach ($Condition in $Conditions) {
                                if ((Get-PSIProperty -InputObject $Condition -Name 'Scope') -eq 'Row' -and (Test-PSICondition -InputObject $Item -Condition $Condition)) {
                                    $RowStatus = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
                                    break
                                }
                            }
                            $RowClass = ''
                            if ($null -ne $RowStatus) {
                                $RowStatusClass = if ($RowStatus -eq 'NotChecked') { 'not-checked' } else { $RowStatus.ToLowerInvariant() }
                                $RowClass = " class=`"psi-row-status-$RowStatusClass`""
                            }
                            [void] $SectionMarkup.AppendLine("                  <tr data-psi-data-row$RowClass>")
                            foreach ($ColumnName in $TableColumns) {
                                $ExplicitCellStatus = $null
                                foreach ($Condition in $Conditions) {
                                    if ((Get-PSIProperty -InputObject $Condition -Name 'Scope') -eq 'Cell' -and
                                        [string]::Equals([string] (Get-PSIProperty -InputObject $Condition -Name 'Property'), [string] $ColumnName, [System.StringComparison]::OrdinalIgnoreCase) -and
                                        (Test-PSICondition -InputObject $Item -Condition $Condition)) {
                                        $ExplicitCellStatus = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
                                        break
                                    }
                                }
                                $ExplicitCellClass = ''
                                if ($null -ne $ExplicitCellStatus) {
                                    $ExplicitCellStatusClass = if ($ExplicitCellStatus -eq 'NotChecked') { 'not-checked' } else { $ExplicitCellStatus.ToLowerInvariant() }
                                    $ExplicitCellClass = "psi-cell-status-$ExplicitCellStatusClass"
                                }
                                $CellValue = Get-PSITableValue -InputObject $Item -Name ([string] $ColumnName)
                                if ($null -eq $CellValue) {
                                    $NullClass = if ($ExplicitCellClass) { "psi-null-value $ExplicitCellClass" } else { 'psi-null-value' }
                                    [void] $SectionMarkup.AppendLine("                    <td class=`"$NullClass`">$NullText</td>")
                                    continue
                                }

                                if ($CellValue -is [string] -or $CellValue.GetType().IsValueType) {
                                    $CellText = [string] $CellValue
                                }
                                else {
                                    $CellText = ConvertTo-Json -InputObject $CellValue -Depth 5 -Compress
                                }

                                if ($ExplicitCellClass) {
                                    $SafeCellText = ConvertTo-PSIHtmlEncoded -Value $CellText
                                    $CellType = [System.Type]::GetTypeCode($CellValue.GetType())
                                    $NumericClass = if ($CellType -in @([System.TypeCode]::Byte, [System.TypeCode]::SByte, [System.TypeCode]::Int16, [System.TypeCode]::UInt16, [System.TypeCode]::Int32, [System.TypeCode]::UInt32, [System.TypeCode]::Int64, [System.TypeCode]::UInt64, [System.TypeCode]::Single, [System.TypeCode]::Double, [System.TypeCode]::Decimal)) { 'psi-numeric-cell ' } else { '' }
                                    [void] $SectionMarkup.AppendLine("                    <td class=`"$NumericClass$ExplicitCellClass`">$SafeCellText</td>")
                                    continue
                                }

                                $CellStatus = Resolve-PSIStatus -Status $CellText -AllowInvalid

                                if ($null -ne $CellStatus) {
                                    $CellStatusClass = $CellStatus.ToLowerInvariant()
                                    if ($CellStatus -eq 'NotChecked') {
                                        $CellStatusClass = 'not-checked'
                                    }
                                    $CellText = ConvertTo-PSIHtmlEncoded -Value $CellStatus
                                    [void] $SectionMarkup.AppendLine("                    <td><span class=`"psi-status-badge psi-status-$CellStatusClass`">$CellText</span></td>")
                                }
                                else {
                                    $CellText = ConvertTo-PSIHtmlEncoded -Value $CellText
                                    $CellType = [System.Type]::GetTypeCode($CellValue.GetType())
                                    $NumericTypes = @(
                                        [System.TypeCode]::Byte, [System.TypeCode]::SByte,
                                        [System.TypeCode]::Int16, [System.TypeCode]::UInt16,
                                        [System.TypeCode]::Int32, [System.TypeCode]::UInt32,
                                        [System.TypeCode]::Int64, [System.TypeCode]::UInt64,
                                        [System.TypeCode]::Single, [System.TypeCode]::Double,
                                        [System.TypeCode]::Decimal
                                    )
                                    $CellClass = if ($CellType -in $NumericTypes) { ' class="psi-numeric-cell"' } else { '' }
                                    [void] $SectionMarkup.AppendLine("                    <td$CellClass>$CellText</td>")
                                }
                            }
                            [void] $SectionMarkup.AppendLine('                  </tr>')
                        }

                        $ColSpan = [math]::Max(1, $TableColumns.Count)
                        [void] $SectionMarkup.AppendLine("                  <tr class=`"psi-table-empty`" data-psi-empty$EmptyRowHidden><td colspan=`"$ColSpan`">$EmptyMessage</td></tr>")
                        [void] $SectionMarkup.AppendLine('                </tbody>')
                        [void] $SectionMarkup.AppendLine('              </table>')
                        [void] $SectionMarkup.AppendLine('            </div>')
                        if ($PaginationEnabled) {
                            [void] $SectionMarkup.AppendLine("            <nav class=`"psi-table-pagination`" data-psi-pagination aria-label=`"Table pages`"><button type=`"button`" data-psi-previous disabled>Previous</button><span data-psi-page-info>Page 1 of 1</span><button type=`"button`" data-psi-next disabled>Next</button></nav>")
                        }
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                    'Chart' {
                        $ChartTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $ChartType = [string] (Get-PSIProperty -InputObject $Properties -Name 'ChartType')
                        $ChartResult = ConvertTo-PSIChartMarkup -Properties $Properties
                        $ChartPoints = [int] $ChartResult.DataPointCount
                        $NullValues = [int] $ChartResult.NullValueCount
                        $ChartSummary = "$ChartPoints points"
                        if ($NullValues -gt 0) {
                            $ChartSummary += "; $NullValues null values omitted"
                        }
                        $SafeSummary = ConvertTo-PSIHtmlEncoded -Value $ChartSummary

                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-chart-card`" data-chart-type=`"$ChartType`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-chart-heading`"><h3>$ChartTitle</h3><span class=`"psi-chart-summary`">$SafeSummary</span></div>")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-chart-visualization`">$($ChartResult.Svg)</div>")
                        if (-not [string]::IsNullOrEmpty([string] $ChartResult.Legend)) {
                            [void] $SectionMarkup.AppendLine("            $($ChartResult.Legend)")
                        }
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                }
            }

            [void] $SectionMarkup.AppendLine('        </div>')
        }

        [void] $SectionMarkup.AppendLine('      </section>')
        $SectionIndex++
    }

    $InteractionScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-interactions.js'
    if (-not (Test-Path -LiteralPath $InteractionScriptPath -PathType Leaf)) {
        throw "The PSInsightHTML interaction script is missing: '$InteractionScriptPath'."
    }
    $TableScript = ''
    if ($HasTableComponents) {
        $TableScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-table.js'
        if (-not (Test-Path -LiteralPath $TableScriptPath -PathType Leaf)) {
            throw "The PSInsightHTML table script is missing: '$TableScriptPath'."
        }
        $TableScript = Get-Content -LiteralPath $TableScriptPath -Raw -ErrorAction Stop
        $TableScript = "  <script>`n$TableScript`n  </script>"
    }
    $InteractionScript = Get-Content -LiteralPath $InteractionScriptPath -Raw -ErrorAction Stop
    $InteractionScript = "  <script>`n$InteractionScript`n  </script>"
    $StatusContractJson = ConvertTo-Json -InputObject ([ordered]@{ values = @($PSIStatusValues); aliases = $PSIStatusAliases }) -Depth 3 -Compress
    $StatusRegistryScript = @"
  <script>
  (function () {
    'use strict';
    var contract = $StatusContractJson;
    window.PSIStatus = {
      normalize: function (value) {
        if (typeof value !== 'string') { return null; }
        var candidate = value.trim().toLowerCase();
        var canonical = contract.values.filter(function (item) { return item.toLowerCase() === candidate; })[0];
        if (canonical) { return canonical; }
        var alias = Object.keys(contract.aliases).filter(function (item) { return item.toLowerCase() === candidate; })[0];
        return alias ? contract.aliases[alias] : null;
      },
      classSuffix: function (status) {
        return status === 'NotChecked' ? 'not-checked' : status.toLowerCase();
      }
    };
  }());
  </script>
"@

    $ExportScript = ''
    if ($HasTableComponents -or $HasInsightComponents -or $EnableReportPrint) {
        $ExportScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-export.js'
        if (-not (Test-Path -LiteralPath $ExportScriptPath -PathType Leaf)) {
            throw "The PSInsightHTML export script is missing: '$ExportScriptPath'."
        }
        $ExportScript = Get-Content -LiteralPath $ExportScriptPath -Raw -ErrorAction Stop
        $ExportScript = "  <script>`n$ExportScript`n  </script>"
    }

    $DrillDownMarkup = ''
    if ($HasDrillDownComponents) {
        $DrillDownMarkup = @'
    <div class="psi-dialog-backdrop" data-psi-dialog-backdrop hidden>
      <section class="psi-dialog" role="dialog" aria-modal="true" aria-labelledby="psi-dialog-title" aria-describedby="psi-dialog-description psi-dialog-summary" tabindex="-1">
        <header class="psi-dialog-header"><div><p class="psi-eyebrow">Record details</p><h2 id="psi-dialog-title" data-psi-dialog-title>Details</h2></div><button type="button" class="psi-dialog-close" data-psi-dialog-close aria-label="Close details">__CLOSE_ICON__</button></header>
        <p id="psi-dialog-description" class="psi-dialog-description" data-psi-dialog-description></p>
        <p class="psi-dialog-summary" data-psi-dialog-summary aria-live="polite"></p>
        <div class="psi-dialog-tools"><label class="psi-dialog-search"><span>Search evidence</span><input type="search" data-psi-dialog-search autocomplete="off" placeholder="Search these records"></label><details class="psi-dialog-filter-disclosure" data-psi-dialog-filter-disclosure><summary data-psi-dialog-filter-summary>Filters</summary><div class="psi-dialog-filters" data-psi-dialog-filters></div></details></div>
        <div class="psi-dialog-actions"><button type="button" data-psi-dialog-apply hidden>Apply these filters to inventory</button>__EVIDENCE_EXPORT_TOOLBAR__</div>
        <div class="psi-dialog-table-scroll" role="region" aria-label="Evidence records" tabindex="0"><table class="psi-dialog-table"><thead data-psi-dialog-head></thead><tbody data-psi-dialog-body></tbody></table></div>
        <nav class="psi-dialog-pagination" data-psi-dialog-pagination aria-label="Evidence pages"><button type="button" data-psi-dialog-previous>Previous</button><span data-psi-dialog-page></span><button type="button" data-psi-dialog-next>Next</button></nav>
        <p class="psi-dialog-empty" data-psi-dialog-empty hidden>No records match this filter.</p>
      </section>
    </div>
'@
        $DrillDownMarkup = $DrillDownMarkup.Replace('__CLOSE_ICON__', (Get-PSIIcon -Name 'close' -Size 20))
        $DrillDownMarkup = $DrillDownMarkup.Replace('__EVIDENCE_EXPORT_TOOLBAR__', (Get-PSIExportToolbar -Scope Evidence))
    }

    $ReportExportMarkup = if ($EnableReportPrint) { Get-PSIExportToolbar -Scope Report -Formats @('Print') } else { '' }

    if ($null -ne $Report.PSObject.Properties['Assessments'] -and $Report.Assessments.Count -gt 0) {
        $NavigationContainerMarkup = @"
    <nav class="psi-assessment-nav" aria-label="Assessment groups">
$($AssessmentNavigationMarkup.ToString())    </nav>
    <details class="psi-section-nav-details">
      <summary>All sections ($($SectionsProperty.Value.Count))</summary>
      <nav class="psi-report-nav" aria-label="Report sections">
$($NavigationMarkup.ToString())      </nav>
    </details>
"@
    }
    else {
        $NavigationContainerMarkup = @"
    <nav class="psi-report-nav" aria-label="Report sections">
$($NavigationMarkup.ToString())    </nav>
"@
    }

    @"
<!DOCTYPE html>
<html lang="en" data-theme="$Theme">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$Title</title>
  <style>
    $ThemeStylesheet
  </style>
</head>
<body>
  <main class="psi-shell">
    <header class="psi-header">
      <div class="psi-header-main">
        <div class="psi-header-copy">
          <p class="psi-eyebrow">PSInsightHTML Report</p>
          <h1>$Title</h1>
          <p class="psi-subtitle">$Subtitle</p>
          <div class="psi-report-meta" aria-label="Report metadata">
            <span>Generated $GeneratedOn</span>
            <span>Module v$ModuleVersion</span>
            <span>Theme <span data-psi-theme-value>$Theme</span></span>
          </div>
        </div>
        <div class="psi-brand" aria-label="PSInsightHTML">
          <svg class="psi-brand-mark" viewBox="0 0 48 48" role="img" aria-label="PSInsightHTML abstract logo"><path d="M24 3 43 14v20L24 45 5 34V14L24 3Z" fill="none" stroke="var(--psi-logo-primary)" stroke-width="2.5"/><path d="M15 31V17h8a5 5 0 0 1 0 10h-4M27 31h7M27 31a4 4 0 0 1 0-8h7" fill="none" stroke="var(--psi-logo-secondary)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><circle cx="35" cy="17" r="2" fill="var(--psi-logo-primary)"/></svg>
          <span>PSInsightHTML</span>
        </div>
      </div>
      <div class="psi-header-actions">
      <div class="psi-theme-control" role="group" aria-label="Report color theme">
        <button type="button" data-psi-theme="Light" aria-pressed="false">$(Get-PSIIcon -Name 'theme/light' -Size 16)<span>Light</span></button>
        <button type="button" data-psi-theme="Dark" aria-pressed="false">$(Get-PSIIcon -Name 'theme/dark' -Size 16)<span>Dark</span></button>
        <button type="button" data-psi-theme="Auto" aria-pressed="false"><span class="psi-theme-auto-icon">$(Get-PSIIcon -Name 'settings' -Size 16)</span><span>Auto</span></button>
      </div>
      $ReportExportMarkup
      </div>
    </header>
    $NavigationContainerMarkup
$($SectionMarkup.ToString())
    <footer class="psi-footer"><span>Generated by PSInsightHTML</span><span>Module v$ModuleVersion &middot; Theme <span data-psi-theme-footer>$Theme</span></span></footer>
  </main>
    $DrillDownMarkup
    $ExportScript
    $StatusRegistryScript
    $InteractionScript
    $TableScript
</body>
</html>
"@
}

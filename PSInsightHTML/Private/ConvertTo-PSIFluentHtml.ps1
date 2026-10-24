function ConvertTo-PSIFluentHtml {
    <#
    .SYNOPSIS
    Render a report with the Fluent application renderer.

    .DESCRIPTION
    Runs the same validation as the classic renderer, projects the report into a JSON model
    (ConvertTo-PSIFluentModel) and embeds it with one stylesheet, the shared export helper and
    the Fluent application script into a single standalone HTML file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Report,
        [Parameter()][bool] $EnableReportPrint = $true
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object].'
    }
    if ([string] $Report.Theme -notin @('Light', 'Dark', 'Auto')) { throw "Theme must be Light, Dark, or Auto. Found '$($Report.Theme)'." }
    [void] (Assert-PSIReportIds -Sections $SectionsProperty.Value)
    if ($null -ne $Report.PSObject.Properties['ApplicationModel']) { [void] (Assert-PSIApplicationModel -Model $Report.ApplicationModel) }
    if ($null -ne $Report.PSObject.Properties['ApplicationAssessment']) {
        [void] (Resolve-PSIAssessmentPosture -Assessment $Report.ApplicationAssessment -Model $Report.ApplicationModel)
    }
    if ([string] (Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -eq 'Application') {
        # Validates views, navigation groups and icons exactly as the classic shell does.
        [void] (Resolve-PSIApplicationNavigation -Report $Report)
    }

    $Model = ConvertTo-PSIFluentModel -Report $Report -EnableReportPrint $EnableReportPrint
    $Root = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Assets'
    $Template = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.html'))
    $Css = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.css'))
    $Js = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.js'))
    $ExportJs = [System.IO.File]::ReadAllText((Join-Path $Root 'JavaScript/psi-export.js'))

    # JSON inside <script type="application/json">: neutralise "</", and the two line separators
    # that are valid in JSON but not in older JavaScript parsers.
    $Escape = { param([string] $Text) $Text.Replace('</', '<\/').Replace([string] [char] 0x2028, ('\' + 'u2028')).Replace([string] [char] 0x2029, ('\' + 'u2029')) }
    $Json = & $Escape (ConvertTo-Json -InputObject $Model -Depth 24 -Compress)
    $Icons = & $Escape (ConvertTo-Json -InputObject (Get-PSIFluentIconSet) -Depth 3 -Compress)

    $Template.Replace('{{THEME}}', [string] $Report.Theme).
        Replace('{{VERSION}}', (ConvertTo-PSIHtmlEncoded -Value ([string] $Report.ModuleVersion))).
        Replace('{{TITLE}}', (ConvertTo-PSIHtmlEncoded -Value ([string] $Report.Title))).
        Replace('/*{{CSS}}*/', $Css).
        Replace('{{DATA}}', $Json).
        Replace('{{ICONS}}', $Icons).
        Replace('/*{{EXPORTJS}}*/', $ExportJs).
        Replace('/*{{JS}}*/', $Js)
}

function Test-PSIFluentSupport {
    # Component types and report features the Fluent renderer does not draw yet. Auto
    # rendering falls back to the classic renderer when any are present.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    $Missing = [System.Collections.Generic.List[string]]::new()
    $Supported = @('Text', 'KeyValue', 'KPI', 'Sparkline', 'EmptyState', 'Insight', 'Finding', 'Status', 'Alert', 'Recommendation', 'Table', 'Chart',
        'Explorer', 'AssessmentOverview', 'Tree', 'Topology', 'RelationshipExplorer')
    foreach ($Section in $Report.Sections) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ([string] $Component.Type -notin $Supported -and -not $Missing.Contains([string] $Component.Type)) { $Missing.Add([string] $Component.Type) }
            }
        }
    }
    , $Missing.ToArray()
}

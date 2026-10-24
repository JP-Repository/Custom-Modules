function Export-PSIReport {
    <#
    .SYNOPSIS
    Write a standalone HTML report.

    .DESCRIPTION
    Renders a completed report and writes an HTML file with embedded local assets.

    .PARAMETER Report
    Report containing at least one section.

    .PARAMETER Path
    Destination HTML path.

    .PARAMETER EnableReportPrint
    Whether to include the report print action.

    .PARAMETER Renderer
    Classic renders the original document/application markup. Fluent renders the interactive
    Fluent application (navigation rail, data grids, detail pane, search palette). Auto uses
    Fluent when every component in the report is supported by it, otherwise Classic.
    When omitted, the PSINSIGHTHTML_RENDERER environment variable is used, then Classic.

    .EXAMPLE
    Export-PSIReport -Report $report -Path ./Reports/Service-Health.html

    .EXAMPLE
    Export-PSIReport -Report $report -Path ./Reports/Service-Health.html -Renderer Fluent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [bool] $EnableReportPrint = $true,

        [Parameter()]
        [ValidateSet('Classic', 'Fluent', 'Auto')]
        [string] $Renderer
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]] -or $SectionsProperty.Value.Count -eq 0) {
        throw 'The report must contain at least one section before it can be exported.'
    }

    if (-not $Renderer) {
        $Renderer = if ($env:PSINSIGHTHTML_RENDERER -in @('Classic', 'Fluent', 'Auto')) { $env:PSINSIGHTHTML_RENDERER } else { 'Classic' }
    }
    if ($Renderer -eq 'Auto') {
        $Missing = Test-PSIFluentSupport -Report $Report
        if ($Missing.Count -gt 0) {
            Write-Verbose "Fluent renderer does not support $($Missing -join ', ') yet; using the classic renderer."
            $Renderer = 'Classic'
        }
        else { $Renderer = 'Fluent' }
    }

    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $ParentDirectory = Split-Path -Path $ResolvedPath -Parent
    if (-not (Test-Path -LiteralPath $ParentDirectory -PathType Container)) {
        [void] (New-Item -Path $ParentDirectory -ItemType Directory -Force -ErrorAction Stop)
    }

    $Html = if ($Renderer -eq 'Fluent') {
        ConvertTo-PSIFluentHtml -Report $Report -EnableReportPrint $EnableReportPrint
    }
    else {
        ConvertTo-PSIHtml -Report $Report -EnableReportPrint $EnableReportPrint
    }
    [System.IO.File]::WriteAllText($ResolvedPath, $Html, [System.Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
}

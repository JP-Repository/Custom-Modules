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

    .EXAMPLE
    Export-PSIReport -Report $report -Path ./Reports/Service-Health.html
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
        [bool] $EnableReportPrint = $true
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]] -or $SectionsProperty.Value.Count -eq 0) {
        throw 'The report must contain at least one section before it can be exported.'
    }

    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $ParentDirectory = Split-Path -Path $ResolvedPath -Parent
    if (-not (Test-Path -LiteralPath $ParentDirectory -PathType Container)) {
        [void] (New-Item -Path $ParentDirectory -ItemType Directory -Force -ErrorAction Stop)
    }

    $Html = ConvertTo-PSIHtml -Report $Report -EnableReportPrint $EnableReportPrint
    [System.IO.File]::WriteAllText($ResolvedPath, $Html, [System.Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
}

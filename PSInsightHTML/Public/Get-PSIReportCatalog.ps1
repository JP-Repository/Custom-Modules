function Get-PSIReportCatalog {
    <#
    .SYNOPSIS
    List integrated report providers.

    .DESCRIPTION
    Returns capability metadata for registered report commands without collecting data.

    .PARAMETER Provider
    Optional provider-name wildcard filter.

    .PARAMETER Name
    Optional report-name wildcard filter.

    .EXAMPLE
    $catalog = Get-PSIReportCatalog
    #>
    [CmdletBinding()]
    param(
        [Parameter()][ValidateNotNullOrEmpty()][string] $Provider = '*',
        [Parameter()][ValidateNotNullOrEmpty()][string] $Name = '*'
    )

    foreach ($Report in @(Get-PSIReportMetadata)) {
        if ($Report.Provider -notlike $Provider -or $Report.Name -notlike $Name) { continue }
        if (-not (Get-Command -Name $Report.Command -Module PSInsightHTML -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Catalog command '$($Report.Command)' for report '$($Report.Id)' is not exported by PSInsightHTML."
        }
        $Report
    }
}

function Add-PSIRow {
    <#
    .SYNOPSIS
    Add a component row.

    .DESCRIPTION
    Appends a row to the latest section; components can then be added to that row.

    .PARAMETER Report
    Report or assessment with an existing section.

    .PARAMETER Columns
    Grid column count, from 1 to 12.

    .EXAMPLE
    $report | Add-PSIRow -Columns 12 | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Columns = 12
    )

    process {
        $SectionsProperty = $Report.PSObject.Properties['Sections']
        if ($null -eq $SectionsProperty) {
            throw 'The report does not contain a Sections collection. Create a valid report with New-PSIReport.'
        }

        $Sections = $SectionsProperty.Value
        if ($Sections -isnot [System.Collections.Generic.List[object]]) {
            throw 'The report Sections property is not a List[object].'
        }

        if ($Sections.Count -eq 0) {
            throw 'A section must be created before adding a row.'
        }

        $LastSection = $Sections[$Sections.Count - 1]
        if ($null -eq $LastSection) {
            throw 'The most recently added section is null and cannot receive a row.'
        }

        $RowsProperty = $LastSection.PSObject.Properties['Rows']
        if ($null -eq $RowsProperty) {
            throw 'The most recently added section does not contain a Rows collection.'
        }

        if ($RowsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
            throw 'The most recently added section Rows property is not a List[object].'
        }

        $Row = [pscustomobject]@{
            Columns    = $Columns
            Components = [System.Collections.Generic.List[object]]::new()
        }

        $RowsProperty.Value.Add($Row)
        $Report
    }
}

function Get-PSILastRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject] $Report
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty) {
        throw 'The report does not contain a Sections collection.'
    }

    $Sections = @($SectionsProperty.Value)
    if ($Sections.Count -eq 0) {
        throw 'A section must be created before adding a row.'
    }

    $LastSection = $Sections[-1]
    if ($null -eq $LastSection) {
        throw 'The last report section is null and does not contain a Rows collection.'
    }

    $RowsProperty = $LastSection.PSObject.Properties['Rows']
    if ($null -eq $RowsProperty) {
        throw 'The last report section does not contain a Rows collection.'
    }

    if ($RowsProperty.Value -isnot [System.Collections.IList]) {
        throw 'The last report section Rows property is not a collection.'
    }

    $Rows = @($RowsProperty.Value)
    if ($Rows.Count -eq 0) {
        throw 'A row must be created before adding a component.'
    }

    $Rows[-1]
}

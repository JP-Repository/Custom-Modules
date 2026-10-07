function Add-PSIEmailRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter()][ValidateSet(1, 2, 3, 4)][int] $Columns = 1
    )
    process {
        if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or $Email.Sections.Count -eq 0) {
            throw 'Add a valid email section before adding a row.'
        }
        $Section = $Email.Sections[$Email.Sections.Count - 1]
        if ($Section.Rows -isnot [System.Collections.Generic.List[object]]) {
            throw 'The current section does not contain a valid Rows collection.'
        }
        $Section.Rows.Add([pscustomobject]@{
            Columns    = $Columns
            Components = [System.Collections.Generic.List[object]]::new()
        })
        $Email
    }
}

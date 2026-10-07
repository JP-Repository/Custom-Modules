function Get-PSIEmailLastRow {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email)

    if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or
        $Email.Sections -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightEmail email. Create it with New-PSIEmail.'
    }
    if ($Email.Sections.Count -eq 0) { throw 'Add an email section before adding a row or component.' }

    $Section = $Email.Sections[$Email.Sections.Count - 1]
    if ($Section.Rows -isnot [System.Collections.Generic.List[object]] -or $Section.Rows.Count -eq 0) {
        throw 'Add an email row before adding a component.'
    }
    $Section.Rows[$Section.Rows.Count - 1]
}

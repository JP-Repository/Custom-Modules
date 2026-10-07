function New-PSIEmailComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Type,
        [Parameter(Mandatory = $true)][ValidateNotNull()][System.Collections.IDictionary] $Properties
    )

    [pscustomobject]@{
        Type       = $Type
        Properties = $Properties
    }
}

function Add-PSIEmailComponentToLastRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Type,
        [Parameter(Mandatory = $true)][ValidateNotNull()][System.Collections.IDictionary] $Properties
    )

    $Row = Get-PSIEmailLastRow -Email $Email
    if ($Row.Components -isnot [System.Collections.Generic.List[object]]) {
        throw 'The current row does not contain a valid Components collection.'
    }
    $Row.Components.Add((New-PSIEmailComponent -Type $Type -Properties $Properties))
    $Email
}

function Add-PSIComponentToLastRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable] $Properties
    )

    $LastRow = Get-PSILastRow -Report $Report
    $ComponentsProperty = $LastRow.PSObject.Properties['Components']
    if ($null -eq $ComponentsProperty -or $ComponentsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The latest row does not contain a valid Components collection.'
    }

    $Component = New-PSIComponent -Type $Type -Properties $Properties
    $ComponentsProperty.Value.Add($Component)
    $Report
}

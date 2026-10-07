function New-PSIComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter()]
        [hashtable] $Properties = @{}
    )

    [pscustomobject]@{
        Type       = $Type
        Properties = $Properties
    }
}

function Get-PSIProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $DefaultValue = $null
    )

    if ($null -eq $InputObject) { return ,$DefaultValue }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $InputObject.Keys) {
            if ([string]::Equals([string] $Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ,$InputObject[$Key]
            }
        }
        return ,$DefaultValue
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) { return ,$DefaultValue }
    return ,$Property.Value
}

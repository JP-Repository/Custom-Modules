function Add-PSIFilter {
    <#
    .SYNOPSIS
    Define a table filter.

    .DESCRIPTION
    Creates a select or multiselect filter definition for Add-PSITable.

    .PARAMETER Property
    Data property to filter.

    .PARAMETER Values
    Selectable values.

    .PARAMETER Type
    Select or MultiSelect control.

    .EXAMPLE
    $filter = Add-PSIFilter -Property Status -Values @('Healthy','Warning')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Values,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Label = '',

        [Parameter()]
        [ValidateSet('Select', 'MultiSelect')]
        [string] $Type = 'Select'
    )

    if ([string]::IsNullOrWhiteSpace($Property)) {
        throw 'Filter Property cannot be null, empty, or whitespace.'
    }
    if ($Values.Count -eq 0) {
        throw 'A filter definition must contain at least one selectable value.'
    }

    $FilterValues = [System.Collections.Generic.List[string]]::new()
    $SeenValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ValueItem in $Values) {
        if ($null -eq $ValueItem) {
            throw 'Filter values cannot be null.'
        }
        $ValueText = [string] $ValueItem
        if ([string]::IsNullOrWhiteSpace($ValueText)) {
            throw 'Filter values cannot be empty or whitespace.'
        }
        if (-not $SeenValues.Add($ValueText)) {
            throw "Filter value '$ValueText' is duplicated."
        }
        $FilterValues.Add($ValueText)
    }

    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = $Property
    }

    [pscustomobject]@{
        Property = $Property
        Label    = $Label
        Type     = $Type
        Values   = [string[]] $FilterValues.ToArray()
    }
}

function Get-PSITableColumnNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data
    )

    $Names = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Item in $Data) {
        if ($null -eq $Item) {
            continue
        }

        if ($Item -is [System.Collections.IDictionary]) {
            foreach ($Key in $Item.Keys) {
                $Name = [string] $Key
                if (-not [string]::IsNullOrWhiteSpace($Name) -and $Seen.Add($Name)) {
                    $Names.Add($Name)
                }
            }

            continue
        }

        foreach ($Property in $Item.PSObject.Properties) {
            if (@('NoteProperty', 'Property', 'AliasProperty', 'CodeProperty') -contains [string] $Property.MemberType) {
                if (-not [string]::IsNullOrWhiteSpace($Property.Name) -and $Seen.Add($Property.Name)) {
                    $Names.Add($Property.Name)
                }
            }
        }
    }

    $Names.ToArray()
}

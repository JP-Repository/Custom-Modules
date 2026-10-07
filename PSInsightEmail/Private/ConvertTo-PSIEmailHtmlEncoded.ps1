function ConvertTo-PSIEmailHtmlEncoded {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object] $Value)

    if ($null -eq $Value) { return '' }
    [System.Net.WebUtility]::HtmlEncode([string] $Value)
}

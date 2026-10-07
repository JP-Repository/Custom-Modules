function ConvertTo-PSIHtmlEncoded {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object] $Value
    )

    process {
        if ($null -eq $Value) { return '' }
        [System.Net.WebUtility]::HtmlEncode([string] $Value)
    }
}

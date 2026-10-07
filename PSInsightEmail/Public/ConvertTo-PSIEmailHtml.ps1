function ConvertTo-PSIEmailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Email
    )
    process { ConvertTo-PSIEmailMarkup -Email $Email }
}

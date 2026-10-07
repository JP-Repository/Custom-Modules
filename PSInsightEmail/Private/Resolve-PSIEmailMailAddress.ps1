function Resolve-PSIEmailMailAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Address,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Label = 'address'
    )

    try { return [System.Net.Mail.MailAddress]::new($Address) }
    catch { throw "Invalid $Label email address '$Address': $($_.Exception.Message)" }
}

function Add-PSIEmailSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter()][AllowEmptyString()][string] $Description = ''
    )
    process {
        if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or
            $Email.Sections -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightEmail email. Create it with New-PSIEmail.'
        }
        $Email.Sections.Add([pscustomobject]@{
            Title       = $Title
            Description = $Description
            Rows        = [System.Collections.Generic.List[object]]::new()
        })
        $Email
    }
}

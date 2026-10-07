function Add-PSIEmailAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][AllowEmptyString()][string] $Name = '',
        [Parameter()][AllowEmptyString()][string] $ContentType = ''
    )
    process {
        if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or
            $Email.Attachments -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object does not contain a valid PSInsightEmail Attachments collection.'
        }
        $File = Resolve-PSIEmailLocalFile -Path $Path
        $ResolvedName = Resolve-PSIEmailResourceName -File $File -Name $Name
        $ResolvedContentType = Resolve-PSIEmailResourceContentType -Path $File.FullName -ContentType $ContentType
        foreach ($Existing in $Email.Attachments) {
            if ([string]::Equals([string] $Existing.Path, $File.FullName, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string] $Existing.Name, $ResolvedName, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Attachment '$ResolvedName' already references '$($File.FullName)' in this email."
            }
        }
        $Email.Attachments.Add([pscustomobject]@{
            PSTypeName  = 'PSInsightEmail.Attachment'
            Path        = $File.FullName
            Name        = $ResolvedName
            ContentType = $ResolvedContentType
            Length      = [long] $File.Length
        })
        $Email
    }
}

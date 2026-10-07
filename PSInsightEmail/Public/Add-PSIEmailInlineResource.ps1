function Add-PSIEmailInlineResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][AllowEmptyString()][string] $ContentId = '',
        [Parameter()][AllowEmptyString()][string] $Name = '',
        [Parameter()][AllowEmptyString()][string] $ContentType = ''
    )
    process {
        if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or
            $Email.InlineResources -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object does not contain a valid PSInsightEmail InlineResources collection.'
        }
        $File = Resolve-PSIEmailLocalFile -Path $Path
        $ResolvedName = Resolve-PSIEmailResourceName -File $File -Name $Name
        $ResolvedContentType = Resolve-PSIEmailResourceContentType -Path $File.FullName -ContentType $ContentType
        if ($ResolvedContentType -notin @('image/png', 'image/jpeg', 'image/gif')) {
            throw "Inline resource '$ResolvedName' has unsupported ContentType '$ResolvedContentType'. Phase 3 supports PNG, JPEG, and GIF images only."
        }
        $ResolvedContentId = if ([string]::IsNullOrWhiteSpace($ContentId)) {
            New-PSIEmailContentId -File $File
        }
        else { Assert-PSIEmailContentId -ContentId $ContentId }
        foreach ($Existing in $Email.InlineResources) {
            if ([string]::Equals([string] $Existing.ContentId, $ResolvedContentId, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Inline resource ContentId '$ResolvedContentId' already exists in this email."
            }
        }
        $Email.InlineResources.Add([pscustomobject]@{
            PSTypeName  = 'PSInsightEmail.InlineResource'
            Path        = $File.FullName
            Name        = $ResolvedName
            ContentType = $ResolvedContentType
            ContentId   = $ResolvedContentId
            Length      = [long] $File.Length
        })
        $Email
    }
}

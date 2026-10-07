function Get-PSIEmailContentType {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.csv'  { return 'text/csv' }
        '.html' { return 'text/html' }
        '.htm'  { return 'text/html' }
        '.txt'  { return 'text/plain' }
        '.json' { return 'application/json' }
        '.xml'  { return 'application/xml' }
        '.pdf'  { return 'application/pdf' }
        '.xlsx' { return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
        '.xls'  { return 'application/vnd.ms-excel' }
        '.zip'  { return 'application/zip' }
        '.png'  { return 'image/png' }
        '.jpg'  { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.gif'  { return 'image/gif' }
        default { return 'application/octet-stream' }
    }
}

function Resolve-PSIEmailLocalFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Path)

    if ([System.Uri]::IsWellFormedUriString($Path, [System.UriKind]::Absolute)) {
        throw "Resource path '$Path' must be a local file path; remote URLs are not supported."
    }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Resource file was not found: $Path" }
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.PSProvider.Name -ne 'FileSystem' -or $Item -isnot [System.IO.FileInfo]) {
        throw "Resource path must identify a local file, not a directory or another provider: $Path"
    }
    $Item
}

function Resolve-PSIEmailRegisteredFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()] $Resource,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label
    )

    $RegisteredPath = [string] $Resource.Path
    $File = Resolve-PSIEmailLocalFile -Path $RegisteredPath
    if (-not [string]::Equals($File.FullName, $RegisteredPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label path no longer resolves to its registered file: $RegisteredPath"
    }
    $File
}

function Resolve-PSIEmailResourceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo] $File,
        [Parameter()][AllowEmptyString()][string] $Name = ''
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return $File.Name }
    if ($Name -in @('.', '..') -or
        $Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Name -match '[\x00-\x1F<>:"/\\|?*]' -or $Name -ne [System.IO.Path]::GetFileName($Name)) {
        throw "Resource name '$Name' must be a safe file name without a directory path."
    }
    $Name
}

function Resolve-PSIEmailResourceContentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter()][AllowEmptyString()][string] $ContentType = ''
    )

    if ([string]::IsNullOrWhiteSpace($ContentType)) { return Get-PSIEmailContentType -Path $Path }
    if ($ContentType -notmatch '^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$') {
        throw "ContentType '$ContentType' is not a safe MIME media type."
    }
    $ContentType.ToLowerInvariant()
}

function Assert-PSIEmailContentId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $ContentId)

    if ($ContentId.Length -gt 127 -or $ContentId -notmatch '^[A-Za-z0-9][A-Za-z0-9._@-]*$') {
        throw "ContentId '$ContentId' is unsafe. Use letters, numbers, dots, underscores, hyphens, or @, beginning with a letter or number."
    }
    $ContentId
}

function New-PSIEmailContentId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.IO.FileInfo] $File)

    $Stem = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) -replace '[^A-Za-z0-9._-]', '-'
    $Stem = $Stem.Trim('-', '.', '_')
    if ([string]::IsNullOrWhiteSpace($Stem)) { $Stem = 'resource' }
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $PathBytes = [System.Text.Encoding]::UTF8.GetBytes($File.FullName.ToLowerInvariant())
        $Hash = ([BitConverter]::ToString($Hasher.ComputeHash($PathBytes))).Replace('-', '').ToLowerInvariant().Substring(0, 12)
    }
    finally { $Hasher.Dispose() }
    Assert-PSIEmailContentId -ContentId ("psi-$Stem-$Hash@psinsightemail")
}

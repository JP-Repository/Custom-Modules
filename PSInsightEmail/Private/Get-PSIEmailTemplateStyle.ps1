function Get-PSIEmailTemplateStyle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateSet('Operational', 'Health', 'Threshold')][string] $Template)

    switch ($Template) {
        'Health' {
            return @{
                Header = '#164e63'; HeaderAccent = '#0f766e'; HeaderMuted = '#ccfbf1'
                Accent = '#0f766e'; AccentSoft = '#f0fdfa'; Section = '#134e4a'
            }
        }
        'Threshold' {
            return @{
                Header = '#4c1d57'; HeaderAccent = '#b45309'; HeaderMuted = '#fef3c7'
                Accent = '#b45309'; AccentSoft = '#fffbeb'; Section = '#78350f'
            }
        }
        default {
            return @{
                Header = '#17365d'; HeaderAccent = '#2f6fad'; HeaderMuted = '#dbeafe'
                Accent = '#2f6fad'; AccentSoft = '#eff6ff'; Section = '#172f4d'
            }
        }
    }
}

function ConvertTo-PSIEmailLogoMarkup {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string] $Path = '',
        [Parameter()][AllowEmptyString()][string] $AltText = '',
        [Parameter()][AllowEmptyString()][string] $ContentId = '',
        [Parameter()][AllowEmptyCollection()][object[]] $InlineResources = @(),
        [Parameter()][switch] $Preview
    )

    $ResolvedAltText = if ([string]::IsNullOrWhiteSpace($AltText)) { 'Brand logo' } else { "$AltText logo" }
    if (-not [string]::IsNullOrWhiteSpace($ContentId)) {
        $SafeContentId = Assert-PSIEmailContentId -ContentId $ContentId
        if (-not $Preview) {
            return '<img src="cid:{0}" width="120" alt="{1}" style="display:block;width:auto;max-width:120px;height:auto;max-height:40px;border:0;outline:none;text-decoration:none;">' -f (ConvertTo-PSIEmailHtmlEncoded $SafeContentId), (ConvertTo-PSIEmailHtmlEncoded $ResolvedAltText)
        }
        foreach ($Resource in $InlineResources) {
            if ([string]::Equals([string] $Resource.ContentId, $SafeContentId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $Path = [string] $Resource.Path
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $Extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $MediaType = switch ($Extension) {
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        default { return '' }
    }
    try {
        $Bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
        if ($Bytes.Length -gt 1048576) { return '' }
        $Data = [Convert]::ToBase64String($Bytes)
        return '<img src="data:{0};base64,{1}" width="120" alt="{2}" style="display:block;width:auto;max-width:120px;height:auto;max-height:40px;border:0;outline:none;text-decoration:none;">' -f $MediaType, $Data, (ConvertTo-PSIEmailHtmlEncoded $ResolvedAltText)
    }
    catch { return '' }
}

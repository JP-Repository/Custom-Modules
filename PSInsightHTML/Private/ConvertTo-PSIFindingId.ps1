function ConvertTo-PSIFindingId {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Id = ''
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return 'psi-finding-' + [guid]::NewGuid().ToString('N')
    }
    $SafeId = [regex]::Replace($Id.Trim(), '[^A-Za-z0-9_-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($SafeId)) {
        return 'psi-finding-' + [guid]::NewGuid().ToString('N')
    }
    if ($SafeId -notmatch '^[A-Za-z]') { $SafeId = 'psi-finding-' + $SafeId }
    return $SafeId
}

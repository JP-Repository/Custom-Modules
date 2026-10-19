function Resolve-PSIADCollectionError {
    <# .SYNOPSIS Classify a collector error from structured exception data. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord] $ErrorRecord)
    $Exception=$ErrorRecord.Exception
    $Category=$ErrorRecord.CategoryInfo.Category
    if ($Exception -is [System.NotSupportedException]) { return 'Unsupported' }
    if ($Exception -is [System.Management.Automation.CommandNotFoundException]) { return 'CommandUnavailable' }
    if ($Exception -is [System.UnauthorizedAccessException] -or $Exception -is [System.Security.SecurityException] -or $Category -eq [System.Management.Automation.ErrorCategory]::PermissionDenied) { return 'AccessDenied' }
    if ($Exception -is [System.TimeoutException] -or $Category -eq [System.Management.Automation.ErrorCategory]::OperationTimeout) { return 'Timeout' }
    if ($Exception -is [System.Net.Sockets.SocketException]) { return 'HostUnreachable' }
    if ($Exception.GetType().FullName -eq 'Microsoft.Management.Infrastructure.CimException') {
        switch ([string]$Exception.StatusCode) {
            'InvalidClass' { return 'Unsupported' }
            'NotSupported' { return 'Unsupported' }
            'AccessDenied' { return 'AccessDenied' }
            'TimedOut' { return 'Timeout' }
            'NetworkError' { return 'HostUnreachable' }
        }
    }
    if ($Exception -is [System.Runtime.InteropServices.COMException] -and $Exception.HResult -eq -2147023174) { return 'RpcUnavailable' }
    if ($Exception.GetType().FullName -match 'PSRemotingTransportException$') { return 'WinRMUnavailable' }
    return 'Unknown'
}

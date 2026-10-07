function Resolve-PSIEmailStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Status)

    if ($Status -notin $script:PSIEmailStatusValues) {
        throw "Email status '$Status' is not supported. Use: $($script:PSIEmailStatusValues -join ', ')."
    }
    $Status
}

function Get-PSIEmailStatusStyle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Status)

    switch (Resolve-PSIEmailStatus -Status $Status) {
        'Critical'      { return @{ Background = '#fef2f2'; Border = '#dc2626'; Text = '#991b1b' } }
        'Warning'       { return @{ Background = '#fffbeb'; Border = '#d97706'; Text = '#92400e' } }
        'Healthy'       { return @{ Background = '#f0fdf4'; Border = '#16a34a'; Text = '#166534' } }
        'Informational' { return @{ Background = '#eff6ff'; Border = '#2563eb'; Text = '#1e40af' } }
        default         { return @{ Background = '#f8fafc'; Border = '#64748b'; Text = '#334155' } }
    }
}

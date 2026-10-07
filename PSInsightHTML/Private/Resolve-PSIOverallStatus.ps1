function Resolve-PSIOverallStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $FindingSummary
    )

    # No supplied findings means no assessed health verdict.
    if ($FindingSummary.Total -eq 0) { return 'Neutral' }
    foreach ($Status in @('Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral')) {
        if ($FindingSummary.$Status -gt 0) { return $Status }
    }
    'Neutral'
}

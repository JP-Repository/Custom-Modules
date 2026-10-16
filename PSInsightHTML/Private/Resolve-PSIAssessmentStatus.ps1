function Resolve-PSIAssessmentStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Status)
    switch ($Status) {
        Ready { 'Healthy' }
        Review { 'Warning' }
        Blocked { 'Critical' }
        NotTested { 'NotChecked' }
        NotApplicable { 'Neutral' }
        Unknown { 'Unknown' }
        default { throw "Unsupported assessment status '$Status'." }
    }
}

@{
    Name = 'DC Upgrade 2025'
    Description = 'Fictional future target readiness and selected baseline review.'
    Assessments = @('Inventory', 'Health', 'Readiness2025', 'Compliance')
    TargetOS = '2025'
    Frameworks = @(
        @{ FrameworkId = 'Microsoft-WindowsServer2025-DC'; Version = '2025 Domain Controller (Azure Policy reference)'; Mode = 'FutureTarget' }
    )
    Tags = @('Sample', 'Upgrade')
    Metadata = @{ Fictional = $true }
}

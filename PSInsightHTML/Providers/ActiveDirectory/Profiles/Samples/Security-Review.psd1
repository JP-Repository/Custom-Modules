@{
    Name = 'Security Review'
    Description = 'Fictional security review using two selected control mapping packs.'
    Assessments = @('Security', 'Compliance')
    Frameworks = @(
        @{ FrameworkId = 'Microsoft-WindowsServer2025-DC'; Version = '2025 Domain Controller (Azure Policy reference)'; Mode = 'FutureTarget' },
        @{ FrameworkId = 'NIST-SP800-53-Rev5.1'; Version = 'Revision 5.1'; Mode = 'CurrentState' }
    )
    Tags = @('Sample', 'Security')
    Metadata = @{ Fictional = $true }
}

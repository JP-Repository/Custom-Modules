@{
    Id = 'ActiveDirectory.CompleteOverview'
    Provider = 'ActiveDirectory'
    Name = 'Complete Domain Overview'
    Description = 'Linked, domain-scoped AD inventory, readiness, health, security and compliance reports.'
    Category = 'Infrastructure'
    Command = 'Invoke-PSIADCompleteOverview'
    Status = 'Pilot'
    SupportsSampleData = $true
    SupportsProvidedData = $true
    SupportsLiveCollection = $true
    MinimumPowerShellVersion = '5.1'
}

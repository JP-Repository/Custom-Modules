@{
    Id = 'ActiveDirectory.GroupPolicy'
    Provider = 'ActiveDirectory'
    Name = 'Group Policy Assessment'
    Description = 'Fictional Group Policy inventory and configuration assessment.'
    Category = 'Configuration'
    Command = 'New-PSIADGroupPolicyAssessment'
    Status = 'Available'
    SupportsSampleData = $true
    SupportsProvidedData = $false
    SupportsLiveCollection = $false
    MinimumPowerShellVersion = '5.1'
}

@{
    Id = 'ActiveDirectory.UserInventory'
    Provider = 'ActiveDirectory'
    Name = 'User Inventory'
    Description = 'Fictional Active Directory user inventory and lifecycle report.'
    Category = 'Identity'
    Command = 'New-PSIADUserInventory'
    Status = 'Available'
    SupportsSampleData = $true
    SupportsProvidedData = $true
    SupportsLiveCollection = $false
    MinimumPowerShellVersion = '5.1'
}

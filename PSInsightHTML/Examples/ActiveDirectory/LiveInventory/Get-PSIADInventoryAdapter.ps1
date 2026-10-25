function Get-PSIADInventoryAdapter {
    <# Read-only, domain-scoped directory queries. Called only for explicit live runs. #>
    [CmdletBinding()]
    param()
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module is required for live inventory.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    @{
        Domain = { param($Name) Get-ADDomain -Identity $Name -Server $Name -ErrorAction Stop }
        Groups = { param($Name, $Limit) @(Get-ADGroup -Filter * -Server $Name -Properties Description,GroupScope,GroupCategory -ResultSetSize ($Limit + 1) -ErrorAction Stop) }
        Users = { param($Name, $Limit) @(Get-ADUser -Filter * -Server $Name -Properties Enabled,Department,EmployeeType,Country,LastLogonDate,PasswordLastSet,AccountExpirationDate,PasswordNeverExpires -ResultSetSize ($Limit + 1) -ErrorAction Stop) }
        Computers = { param($Name, $Limit) @(Get-ADComputer -Filter * -Server $Name -Properties Enabled,DNSHostName,OperatingSystem,OperatingSystemVersion,LastLogonDate,Location -ResultSetSize ($Limit + 1) -ErrorAction Stop) }
        OUs = { param($Name, $Limit) @(Get-ADOrganizationalUnit -Filter * -Server $Name -Properties ProtectedFromAccidentalDeletion,gPLink,gPOptions -ResultSetSize ($Limit + 1) -ErrorAction Stop) }
        GroupPolicy = {
            param($Name, $Limit)
            if (-not (Get-Module -ListAvailable -Name GroupPolicy)) { throw 'The GroupPolicy PowerShell module is required for the GPO inventory.' }
            Import-Module GroupPolicy -ErrorAction Stop
            @(Get-GPO -All -Domain $Name -ErrorAction Stop | Select-Object -First ($Limit + 1))
        }
    }
}

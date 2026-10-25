function New-PSIADInventoryFixture {
    <# Fictional directory-shaped records; never queries an environment. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Groups','GroupPolicy','Users','Computers','OUs')][string] $ReportType)
    $Now = Get-Date
    switch ($ReportType) {
        'Groups' {
            @(
                [pscustomobject]@{ Name='App Operators'; SamAccountName='AppOperators'; GroupScope='Global'; GroupCategory='Security'; Description='Fictional application support access' },
                [pscustomobject]@{ Name='Helpdesk Readers'; SamAccountName='HelpdeskReaders'; GroupScope='DomainLocal'; GroupCategory='Security'; Description='Fictional read access' },
                [pscustomobject]@{ Name='Project Updates'; SamAccountName='ProjectUpdates'; GroupScope='Universal'; GroupCategory='Distribution'; Description='Fictional mailing list' }
            )
        }
        'GroupPolicy' {
            @(
                [pscustomobject]@{ DisplayName='Fictional Workstation Baseline'; Id='00000000-0000-0000-0000-000000000001'; GpoStatus='AllSettingsEnabled'; CreationTime=$Now.AddYears(-2); ModificationTime=$Now.AddDays(-18); Owner='EXAMPLE\\Policy Admins' },
                [pscustomobject]@{ DisplayName='Fictional Server Baseline'; Id='00000000-0000-0000-0000-000000000002'; GpoStatus='AllSettingsEnabled'; CreationTime=$Now.AddYears(-1); ModificationTime=$Now.AddDays(-35); Owner='EXAMPLE\\Policy Admins' },
                [pscustomobject]@{ DisplayName='Fictional Legacy Policy'; Id='00000000-0000-0000-0000-000000000003'; GpoStatus='AllSettingsDisabled'; CreationTime=$Now.AddYears(-4); ModificationTime=$Now.AddYears(-1); Owner='EXAMPLE\\Policy Admins' }
            )
        }
        'Users' {
            @(
                [pscustomobject]@{ Name='Avery Example'; SamAccountName='avery.example'; Enabled=$true; Department='Operations'; EmployeeType='Employee'; Country='US'; LastLogonDate=$Now.AddDays(-2); PasswordLastSet=$Now.AddDays(-43); AccountExpirationDate=$null; PasswordNeverExpires=$false },
                [pscustomobject]@{ Name='Morgan Example'; SamAccountName='morgan.example'; Enabled=$false; Department='Finance'; EmployeeType='Employee'; Country='GB'; LastLogonDate=$Now.AddDays(-92); PasswordLastSet=$Now.AddDays(-120); AccountExpirationDate=$Now.AddDays(30); PasswordNeverExpires=$false },
                [pscustomobject]@{ Name='Sample Service'; SamAccountName='svc-sample'; Enabled=$true; Department=$null; EmployeeType='Service'; Country=$null; LastLogonDate=$null; PasswordLastSet=$Now.AddDays(-200); AccountExpirationDate=$null; PasswordNeverExpires=$true }
            )
        }
        'Computers' {
            @(
                [pscustomobject]@{ Name='WS-SAMPLE-01'; DNSHostName='ws-sample-01.corp.example'; Enabled=$true; OperatingSystem='Windows 11'; OperatingSystemVersion='10.0'; LastLogonDate=$Now.AddDays(-1); Location='North' },
                [pscustomobject]@{ Name='SRV-SAMPLE-01'; DNSHostName='srv-sample-01.corp.example'; Enabled=$true; OperatingSystem='Windows Server 2022'; OperatingSystemVersion='10.0'; LastLogonDate=$Now.AddDays(-3); Location='Central' },
                [pscustomobject]@{ Name='WS-SAMPLE-OLD'; DNSHostName=$null; Enabled=$false; OperatingSystem='Windows 10'; OperatingSystemVersion=$null; LastLogonDate=$Now.AddDays(-200); Location=$null }
            )
        }
        'OUs' {
            @(
                [pscustomobject]@{ Name='Workstations'; DistinguishedName='OU=Workstations,DC=corp,DC=example'; ProtectedFromAccidentalDeletion=$true; gPLink='[LDAP://CN={00000000-0000-0000-0000-000000000001},CN=Policies,CN=System,DC=corp,DC=example;0]'; gPOptions=0 },
                [pscustomobject]@{ Name='Servers'; DistinguishedName='OU=Servers,DC=corp,DC=example'; ProtectedFromAccidentalDeletion=$true; gPLink=''; gPOptions=0 },
                [pscustomobject]@{ Name='Legacy'; DistinguishedName='OU=Legacy,DC=corp,DC=example'; ProtectedFromAccidentalDeletion=$false; gPLink=''; gPOptions=1 }
            )
        }
    }
}

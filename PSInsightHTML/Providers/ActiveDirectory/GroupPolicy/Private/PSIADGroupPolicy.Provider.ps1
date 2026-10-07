function New-PSIADGroupPolicySampleData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(100, 250)]
        [int] $GpoCount = 180,

        [Parameter()]
        [datetime] $AsOfDate = [datetime]::new(2026, 9, 27)
    )

    $Gpos = [System.Collections.Generic.List[object]]::new()
    $Links = [System.Collections.Generic.List[object]]::new()
    $SecurityFilters = [System.Collections.Generic.List[object]]::new()
    $Delegations = [System.Collections.Generic.List[object]]::new()
    $WmiAssignments = [System.Collections.Generic.List[object]]::new()
    $LinkOrderByTarget = @{}

    $Purposes = @('Workstation Baseline', 'Application Settings', 'Browser Configuration', 'Office Configuration', 'Server Baseline', 'Remote Access', 'Printing', 'Update Ring')
    $Regions = @('North', 'South', 'East', 'West', 'Central')
    $Targets = @(
        'OU=Workstations,OU=North,DC=corp,DC=example,DC=invalid',
        'OU=Servers,OU=North,DC=corp,DC=example,DC=invalid',
        'OU=Users,OU=South,DC=corp,DC=example,DC=invalid',
        'OU=Workstations,OU=East,DC=corp,DC=example,DC=invalid',
        'OU=Servers,OU=West,DC=corp,DC=example,DC=invalid',
        'OU=Users,OU=Central,DC=corp,DC=example,DC=invalid',
        'DC=corp,DC=example,DC=invalid',
        'CN=Demo-Site,CN=Sites,CN=Configuration,DC=corp,DC=example,DC=invalid'
    )
    $WmiCatalog = @(
        [pscustomobject]@{ Name='Sample Windows 11 Clients'; Description='Fictional workstation targeting example.'; QuerySummary='Operating system version begins with 10.0 and product type is workstation.' },
        [pscustomobject]@{ Name='Sample Windows Servers'; Description='Fictional server targeting example.'; QuerySummary='Operating system product type is server.' },
        [pscustomobject]@{ Name='Sample Portable Devices'; Description='Fictional device-class targeting example.'; QuerySummary='Computer system model is within a reviewed portable-device list.' },
        [pscustomobject]@{ Name='Sample Legacy Compatibility'; Description='Fictional compatibility targeting example.'; QuerySummary='Operating system build belongs to an approved compatibility range.' }
    )

    for ($Index = 1; $Index -le $GpoCount; $Index++) {
        $Name = 'GPO-{0}-{1}-{2:D3}' -f $Regions[($Index - 1) % $Regions.Count], $Purposes[($Index - 1) % $Purposes.Count].Replace(' ', '-'), $Index
        $GpoId = [guid] ('10000000-0000-4000-8000-{0:x12}' -f $Index)
        $UserConfiguration = 'Enabled'
        $ComputerConfiguration = 'Enabled'
        if ($Index % 10 -eq 0) {
            $UserConfiguration = 'Disabled'
            $ComputerConfiguration = 'Disabled'
        }
        elseif ($Index % 5 -eq 0) { $UserConfiguration = 'Disabled' }
        elseif ($Index % 7 -eq 0) { $ComputerConfiguration = 'Disabled' }

        $ConfigurationState = if ($UserConfiguration -eq 'Disabled' -and $ComputerConfiguration -eq 'Disabled') { 'Both disabled' }
            elseif ($UserConfiguration -eq 'Disabled') { 'Computer only' }
            elseif ($ComputerConfiguration -eq 'Disabled') { 'User only' }
            else { 'User and Computer' }
        $SettingsState = if ($Index % 17 -eq 0) { 'Empty' } else { 'Configured' }
        $LinkCount = if ($Index % 11 -eq 0) { 0 } else { 1 + ($Index % 3) }
        $DisabledLinkCount = 0
        for ($LinkIndex = 0; $LinkIndex -lt $LinkCount; $LinkIndex++) {
            $Target = $Targets[($Index + ($LinkIndex * 3)) % $Targets.Count]
            $TargetType = if ($Target.StartsWith('OU=')) { 'OU' } elseif ($Target.StartsWith('CN=')) { 'Site' } else { 'Domain' }
            if (-not $LinkOrderByTarget.ContainsKey($Target)) { $LinkOrderByTarget[$Target] = 0 }
            $LinkOrderByTarget[$Target]++
            $LinkEnabled = if (($Index + $LinkIndex) % 13 -eq 0) { 'No' } else { 'Yes' }
            if ($LinkEnabled -eq 'No') { $DisabledLinkCount++ }
            $Links.Add([pscustomobject]@{
                GpoName = $Name
                GpoId = [string] $GpoId
                Target = $Target
                TargetType = $TargetType
                LinkEnabled = $LinkEnabled
                Enforced = if (($Index + $LinkIndex) % 17 -eq 0) { 'Yes' } else { 'No' }
                LinkOrder = [int] $LinkOrderByTarget[$Target]
            })
        }

        $FilterType = switch ($Index % 4) {
            0 { 'Authenticated Users' }
            1 { 'Domain Computers' }
            2 { 'Custom group' }
            3 { 'Mixed' }
        }
        $Principals = switch ($FilterType) {
            'Authenticated Users' { @([pscustomobject]@{ Name='Authenticated Users'; Permission='Read; Apply Group Policy'; Apply='Yes' }) }
            'Domain Computers' { @([pscustomobject]@{ Name='EXAMPLE\Domain Computers'; Permission='Read; Apply Group Policy'; Apply='Yes' }) }
            'Custom group' { @([pscustomobject]@{ Name='EXAMPLE\Sample Policy Scope'; Permission='Read; Apply Group Policy'; Apply='Yes' }) }
            'Mixed' { @(
                [pscustomobject]@{ Name='Authenticated Users'; Permission='Read'; Apply='No' },
                [pscustomobject]@{ Name='EXAMPLE\Sample Policy Scope'; Permission='Read; Apply Group Policy'; Apply='Yes' }
            ) }
        }
        foreach ($Principal in $Principals) {
            $SecurityFilters.Add([pscustomobject]@{
                GpoName = $Name
                Principal = $Principal.Name
                Permission = $Principal.Permission
                ApplyState = $Principal.Apply
                FilterType = $FilterType
            })
        }

        $Delegations.Add([pscustomobject]@{
            GpoName = $Name
            Trustee = 'EXAMPLE\Sample GPO Administrators'
            PermissionLevel = 'Edit settings, delete, and modify security'
            Source = 'Explicit'
        })
        if ($Index % 3 -eq 0) {
            $Delegations.Add([pscustomobject]@{
                GpoName = $Name
                Trustee = 'EXAMPLE\Sample Policy Editors'
                PermissionLevel = 'Edit settings'
                Source = if ($Index % 2 -eq 0) { 'Inherited' } else { 'Explicit' }
            })
        }

        $WmiFilterName = $null
        if ($Index % 6 -eq 0) {
            $WmiCatalogIndex = [int] (($Index / 6 - 1) % $WmiCatalog.Count)
            $WmiDefinition = $WmiCatalog[$WmiCatalogIndex]
            $WmiFilterName = $WmiDefinition.Name
            $WmiAssignments.Add([pscustomobject]@{
                GpoName = $Name
                FilterName = $WmiDefinition.Name
                Description = $WmiDefinition.Description
                QuerySummary = $WmiDefinition.QuerySummary
            })
        }

        $CreatedDate = $AsOfDate.Date.AddYears(-6).AddDays($Index * 8)
        $ModifiedDate = $CreatedDate.AddDays(30 + ($Index % 360))
        if ($ModifiedDate -gt $AsOfDate) { $ModifiedDate = $AsOfDate }
        # A narrow sample configuration check, not a security or compliance verdict.
        $DemoAssessment = if ($LinkCount -gt 0 -and $DisabledLinkCount -eq 0 -and
            $SettingsState -eq 'Configured' -and $ConfigurationState -ne 'Both disabled') { 'Healthy' } else { 'Info' }
        $Gpos.Add([pscustomobject]@{
            GpoName = $Name
            GpoId = [string] $GpoId
            Created = $CreatedDate.ToString('yyyy-MM-dd')
            Modified = $ModifiedDate.ToString('yyyy-MM-dd')
            UserConfiguration = $UserConfiguration
            ComputerConfiguration = $ComputerConfiguration
            ConfigurationState = $ConfigurationState
            UserVersion = if ($SettingsState -eq 'Empty') { 0 } else { 1 + ($Index % 24) }
            ComputerVersion = if ($SettingsState -eq 'Empty') { 0 } else { 1 + ($Index % 31) }
            SettingsState = $SettingsState
            LinkState = if ($LinkCount -eq 0) { 'Unlinked' } else { 'Linked' }
            LinkCount = $LinkCount
            DisabledLinkCount = $DisabledLinkCount
            WmiFilterName = $WmiFilterName
            WmiUsage = if ($null -eq $WmiFilterName) { 'No filter' } else { 'Has filter' }
            SecurityFilterType = $FilterType
            SecurityFilteringSummary = (@($Principals | Where-Object { $_.Apply -eq 'Yes' } | ForEach-Object { $_.Name }) -join '; ')
            DemoAssessment = $DemoAssessment
        })
    }

    [pscustomobject]@{
        Source = 'Deterministic fictional Group Policy assessment sample; no live directory connection.'
        AsOfDate = $AsOfDate
        Gpos = $Gpos.ToArray()
        Links = $Links.ToArray()
        SecurityFilters = $SecurityFilters.ToArray()
        Delegations = $Delegations.ToArray()
        WmiAssignments = $WmiAssignments.ToArray()
    }
}

function Get-PSIADGroupPolicyDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property
    )

    @($Data | Group-Object -Property $Property | Sort-Object -Property Name | ForEach-Object {
        [pscustomobject]@{ Category = [string] $_.Name; Count = [int] $_.Count }
    })
}

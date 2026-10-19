Describe 'AD organizational assessment profiles' {
    BeforeAll {
        $script:Root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        . (Join-Path $Root 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        $script:ProfilesRoot=Join-Path $Root 'Providers/ActiveDirectory/Profiles/Samples'
        $script:Nist=@{ FrameworkId='NIST-SP800-53-Rev5.1'; Version='Revision 5.1'; Mode='CurrentState' }
        $script:Microsoft=@{ FrameworkId='Microsoft-WindowsServer2025-DC'; Version='2025 Domain Controller (Azure Policy reference)'; Mode='FutureTarget' }
    }

    It 'loads each fictional offline profile and normalizes its selection' {
        $Monthly=Resolve-PSIADAssessmentProfile -Path (Join-Path $ProfilesRoot 'Monthly-AD-Review.psd1')
        $Upgrade=Resolve-PSIADAssessmentProfile -Path (Join-Path $ProfilesRoot 'DC-Upgrade-2025.psd1')
        $Security=Resolve-PSIADAssessmentProfile -Path (Join-Path $ProfilesRoot 'Security-Review.psd1')
        $Monthly.SelectedAssessments | Should -Contain 'Inventory'
        $Monthly.SelectedFrameworks.Count | Should -Be 0
        $Upgrade.TargetOS | Should -Be '2025'
        $Upgrade.SelectedFrameworks[0].Mode | Should -Be 'FutureTarget'
        $Security.SelectedFrameworks.Count | Should -Be 2
        $Security.SelectedControls.Count | Should -Be 9
    }
    It 'rejects unknown or duplicate assessments' {
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Inventory','Unknown') } } | Should -Throw '*Unknown assessment*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Health','Health') } } | Should -Throw '*Duplicate assessment*'
    }
    It 'validates framework identity, pinned version and mode' {
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@(@{ FrameworkId='Absent'; Version='1'; Mode='CurrentState' }) } } | Should -Throw '*Unknown compliance framework*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@(@{ FrameworkId=$Nist.FrameworkId; Version='5.0'; Mode='CurrentState' }) } } | Should -Throw '*Unknown version*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@(@{ FrameworkId=$Nist.FrameworkId; Version=$Nist.Version; Mode='FutureTarget' }) } } | Should -Throw '*Invalid mode*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist,$Nist) } } | Should -Throw '*Duplicate framework*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance') } } | Should -Throw '*requires at least one*'
    }
    It 'defaults to primary controls in the selected pack only' {
        $Result=Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist) }
        $Result.SelectedControls.Count | Should -Be 3
        $Result.ExcludedControls.Count | Should -Be 0
        $Result.SelectedControls[0].Identity | Should -Match '^NIST-SP800-53-Rev5\.1\|Revision 5\.1\|'
        @($Result.SelectedControls | Where-Object ControlId -eq 'AU-12').Count | Should -Be 1
    }
    It 'includes and excludes primary controls without selecting supporting mappings' {
        $Result=Resolve-PSIADAssessmentProfile -Profile @{
            Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist)
            ControlSelections=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('SC-8') })
            ControlExclusions=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('AU-12') })
        }
        $Result.SelectedControls.Count | Should -Be 1
        $Result.SelectedControls[0].ControlId | Should -Be 'SC-8'
        $Result.ExcludedControls.Count | Should -Be 2
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist); ControlSelections=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('AU-12') }); ControlExclusions=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('AU-12') }) } } | Should -Throw '*both included and excluded*'
    }
    It 'rejects unknown and duplicate control references' {
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist); ControlSelections=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('Absent') }) } } | Should -Throw '*Unknown selected control*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist); ControlSelections=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('SC-8','SC-8') }) } } | Should -Throw '*Duplicate control ID*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Compliance'); Frameworks=@($Nist); ControlSelections=@(@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('SC-8') },@{ FrameworkId=$Nist.FrameworkId; ControlIds=@('AU-12') }) } } | Should -Throw '*Duplicate ControlSelections entry*'
    }
    It 'validates target OS and preserves explicit context' {
        (Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Readiness2025'); TargetOS='2025' }).TargetOS | Should -Be '2025'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Readiness2022'); TargetOS='2019' } } | Should -Throw '*Invalid TargetOS*'
    }
    It 'accepts supported scoped threshold overrides and rejects unsafe values' {
        $Result=Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Health','Security'); ThresholdOverrides=@{ Health=@{ DiskReviewFreeGB=20 }; Security=@{ PrivilegedInactivityReviewDays=120 } } }
        $Result.ThresholdOverrides.Health.DiskReviewFreeGB | Should -Be 20
        $Result.ThresholdOverrides.Security.PrivilegedInactivityReviewDays | Should -Be 120
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Health'); ThresholdOverrides=@{ Health=@{ DiskReviewGB=20 } } } } | Should -Throw '*Unknown or read-only*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Health'); ThresholdOverrides=@{ Health=@{ DiskReviewFreeGB='20' } } } } | Should -Throw '*finite positive number*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Health'); ThresholdOverrides=@{ Health=@{ DiskCriticalFreeGB=20 } } } } | Should -Throw '*ordering*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Security'); ThresholdOverrides=@{ Security=@{ ReadyScoreMinimum=101 } } } } | Should -Throw '*exceed 100*'
        { Resolve-PSIADAssessmentProfile -Profile @{ Name='Test'; Assessments=@('Security'); ThresholdOverrides=@{ Security=@{ PrivilegedInactivityReviewDays=1.5 } } } } | Should -Throw '*whole number*'
    }
    It 'does not mutate its input, mapping packs or threshold packs' {
        $InputProfile=@{ Name='Test'; Assessments=@('Health','Compliance'); Frameworks=@($Nist); ThresholdOverrides=@{ Health=@{ DiskReviewFreeGB=20 } }; Metadata=@{ Fictional=$true } }
        $Before=ConvertTo-Json -InputObject $InputProfile -Depth 8 -Compress
        $PackBefore=ConvertTo-Json -InputObject (Get-PSIADControlMappings -FrameworkId $Nist.FrameworkId) -Depth 8 -Compress
        $ThresholdPath=Join-Path $Root 'Providers/ActiveDirectory/Rules/Health/Thresholds.psd1'
        $ThresholdBefore=ConvertTo-Json -InputObject (Import-PowerShellDataFile $ThresholdPath) -Depth 4 -Compress
        $Result=Resolve-PSIADAssessmentProfile -Profile $InputProfile
        $Result.ThresholdOverrides.Health.DiskReviewFreeGB=30
        (ConvertTo-Json -InputObject $InputProfile -Depth 8 -Compress) | Should -Be $Before
        (ConvertTo-Json -InputObject (Get-PSIADControlMappings -FrameworkId $Nist.FrameworkId) -Depth 8 -Compress) | Should -Be $PackBefore
        (ConvertTo-Json -InputObject (Import-PowerShellDataFile $ThresholdPath) -Depth 4 -Compress) | Should -Be $ThresholdBefore
    }
    It 'parses in Windows PowerShell 5.1 language mode' {
        $File=Join-Path $Root 'Providers/ActiveDirectory/Profiles/Resolve-PSIADAssessmentProfile.ps1'
        $Tokens=$null; $Errors=$null
        $Ast=[System.Management.Automation.Language.Parser]::ParseFile($File,[ref]$Tokens,[ref]$Errors)
        @($Errors).Count | Should -Be 0
        $Ast.Extent.Text | Should -Not -Match '\?\?|\?\.|\s\?\s'
        foreach ($Sample in @(Get-ChildItem $ProfilesRoot -Filter '*.psd1')) { { Import-PowerShellDataFile $Sample.FullName } | Should -Not -Throw }
    }
}

Describe 'AD selected control mapping' {
    BeforeAll {
        $script:Root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $Root 'PSInsightHTML.psd1') -Force
        . (Join-Path $Root 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        $script:Raw=Collect-PSIADSnapshot -UseSampleData -Profile Full
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
        $script:SecurityEvidence=New-PSIADSecurityEvidenceModel $Snapshot
        $script:HealthEvidence=New-PSIADHealthEvidenceModel $Snapshot
        $null=Add-PSIADSecurityFictionalObservations $Snapshot $SecurityEvidence
        $null=Add-PSIADHealthFictionalObservations $Snapshot $HealthEvidence
        $script:Security=Test-PSIADSecurity $Snapshot $SecurityEvidence
        $script:Health=Test-PSIADHealth $Snapshot $HealthEvidence
        $script:Pack=Get-PSIADControlMappings
        $script:Compliance=Test-PSIADCompliance $Snapshot $Security $Health
        $script:NIST=Test-PSIADCompliance $Snapshot $Security $Health (Get-PSIADControlMappings -FrameworkId 'NIST-SP800-53-Rev5.1')
    }
    It 'loads a pinned, referenced contract with unique mapping identifiers' {
        $Pack.FrameworkVersion | Should -Be '2025 Domain Controller (Azure Policy reference)'
        @($Pack.Controls).Count | Should -Be 7
        @($Pack.Controls | Where-Object { -not $_.ControlId -or -not $_.Reference -or -not $_.EvidenceRequirements }).Count | Should -Be 0
        @($Pack.Controls | Where-Object MappingType -eq Supporting).Count | Should -Be 1
    }
    It 'keeps supporting context separate from the six distinct control results' {
        $Compliance.Counts.Mapped | Should -Be 6
        @($Compliance.Controls | Where-Object MappingType -eq Supporting).Count | Should -Be 0
        @($Compliance.Controls | Where-Object { $_.SupportingMappings.Count }).Count | Should -Be 1
    }
    It 'keeps blocked source observations as future-target context without a false failure' {
        $Control=@($Compliance.Controls | Where-Object ControlId -eq CCE-36173-3)[0]
        $Control.Status | Should -Be ContextOnly
        $Control.Applicability | Should -Be ContextOnly
        @($Security.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'ntlmv1-usage' -and $_.Status -eq 'Blocked' }).Count | Should -BeGreaterThan 0
    }
    It 'keeps partial and missing evidence from becoming Pass' {
        @($Compliance.Controls | Where-Object { $_.MappingType -eq 'Partial' -and $_.Status -eq 'Pass' }).Count | Should -Be 0
        @($Compliance.Controls | Where-Object { $_.MissingChecks -gt 0 -and $_.Status -eq 'Pass' }).Count | Should -Be 0
        $NIST.Counts.PartiallyAssessed | Should -BeGreaterThan 0
    }
    It 'shows context-only Microsoft resources and assessed NIST resources' {
        @($Compliance.ResourceResults | Where-Object Status -eq ContextOnly).Count | Should -Be 48
        @($NIST.ResourceResults | Where-Object Applicability -eq Applicable).Count | Should -BeGreaterThan 0
    }
    It 'links control results to original checks, findings, evidence and resources' {
        $Control=@($Compliance.Controls | Where-Object ControlId -eq 'CCE-36173-3')[0]
        $Control.CheckIds.Count | Should -BeGreaterThan 0
        $Control.FindingIds.Count | Should -BeGreaterThan 0
        $Control.EvidenceIds.Count | Should -BeGreaterThan 0
        $Control.ResourceIds.Count | Should -BeGreaterThan 0
        @($Security.Model.Evidence | Where-Object Id -in $Control.EvidenceIds).Count | Should -BeGreaterThan 0
    }
    It 'does not claim full framework coverage or a blended compliance score' {
        $Compliance.FrameworkCoverage.Percent | Should -BeNullOrEmpty
        $Compliance.FrameworkCoverage.Label | Should -Match 'Selected Control Mapping'
        $Compliance.EvidenceCompleteness.Percent | Should -BeNullOrEmpty
        $NIST.EvidenceCompleteness.Percent | Should -BeGreaterThan 0
        $Compliance.PSObject.Properties.Name | Should -Not -Contain Score
    }
    It 'keeps exception context without changing the mapped result' {
        $Copy=$Security.PSObject.Copy()
        $AssessmentCopy=$Security.Assessment.PSObject.Copy()
        $Check=@($Security.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'ntlmv1-usage' -and $_.Status -eq 'Blocked' })[0]
        $AssessmentCopy.Exceptions=@([pscustomobject]@{ Id='fictional-exception'; CheckId=$Check.Id; FindingId=''; ResourceIds=@(); Title='Reviewed dependency'; Status='Approved'; Reason='Fictional context' })
        $Copy.Assessment=$AssessmentCopy
        $WithException=Test-PSIADCompliance $Snapshot $Copy $Health
        $Control=@($WithException.Controls | Where-Object ControlId -eq 'CCE-36173-3')[0]
        $Control.Status | Should -Be ContextOnly
        $Control.Exceptions[0].Id | Should -Be fictional-exception
    }
    It 'rejects invalid and unknown mapping definitions' {
        $Invalid=@{ Framework='F'; FrameworkVersion='1'; Controls=@(@{ ControlId='X'; MappingType='Direct'; Reference='https://learn.microsoft.com/'; SourceRuleIds=@('not-a-psi-rule') }) }
        { Test-PSIADCompliance $Snapshot $Security -MappingPack $Invalid } | Should -Throw '*Unknown mapped PSI rule*'
        $Invalid.Controls[0].MappingType='Impossible'
        { Test-PSIADCompliance $Snapshot $Security -MappingPack $Invalid } | Should -Throw '*Invalid compliance control mapping*'
    }
    It 'rejects mixed snapshots and leaves source objects unchanged' {
        $Before=ConvertTo-Json -InputObject $Security.Assessment.Checks -Depth 8 -Compress
        $Other=$Snapshot | Select-Object *
        { Test-PSIADCompliance $Other $Security } | Should -Throw '*same normalized snapshot*'
        $null=Test-PSIADCompliance $Snapshot $Security $Health
        (ConvertTo-Json -InputObject $Security.Assessment.Checks -Depth 8 -Compress) | Should -Be $Before
    }
    It 'preserves Health and Security fictional baselines' {
        $Health.HealthVerdict | Should -Be Critical
        $Health.Assessment.Score | Should -Be 61.8
        $Security.SecurityVerdict | Should -Be Critical
        $Security.Assessment.Score | Should -Be 37.4
        $SecurityEvidence.EvidenceCompleteness.Percent | Should -Be 28.4
    }
    It 'reuses one snapshot across inventory and both readiness targets' {
        $Inventory=New-PSIADDCInventoryModel $Snapshot
        $Ready22=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022
        $Ready25=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
        @($Inventory.DomainControllers).Count | Should -Be 8
        $Ready22.Assessment.Score | Should -Be 62.3
        $Ready22.Assessment.Decision | Should -Be Incomplete
        $Ready25.Assessment.Score | Should -Be 56.1
        $Ready25.Assessment.Decision | Should -Be NotReady
        [object]::ReferenceEquals($Snapshot,$Compliance.Snapshot) | Should -BeTrue
    }
    It 'keeps mocked-live missing evidence explicit without calling a real directory' {
        . (Join-Path $Root 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $Mock=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -Profile Full -CommandAdapter (New-PSIADLiveFixtureAdapter))
        $MockSecurity=Test-PSIADSecurity $Mock (New-PSIADSecurityEvidenceModel $Mock)
        $MockCompliance=Test-PSIADCompliance $Mock $MockSecurity -MappingPack (Get-PSIADControlMappings -FrameworkId 'NIST-SP800-53-Rev5.1')
        $MockCompliance.Counts.NotTested | Should -BeGreaterThan 0
        $MockCompliance.Counts.Pass | Should -Be 0
        $MockCompliance.EvidenceCompleteness.Percent | Should -BeLessThan 100
    }
    It 'generates searchable, printable standalone control views' {
        $Result=& (Join-Path $Root 'Examples/ActiveDirectory/Compliance/Invoke-PSIADCompliance.ps1') -Snapshot $Snapshot -NoBrowser -PassThru -OutputPath $TestDrive
        $Html=[System.IO.File]::ReadAllText($Result.HtmlPath)
        $Html | Should -Match 'Selected AD Control Mapping'
        $Html | Should -Match 'CCE-37864-6'
        $Html | Should -Match 'id="psi-print-document"'
        $Html | Should -Match 'Selected control mapping \| Not a certification'
        $Html | Should -Match 'Control registers'
        $Html | Should -Match 'Linked PSI checks'
        $Html | Should -Match 'Linked evidence references'
        $Html | Should -Match 'Not a certification or a complete framework assessment'
        $Html | Should -Match 'data-psi-app-view'
        $Html | Should -Not -Match '(?i)<(?:script|link|img)[^>]+(?:src|href)="https?://'
        $Html | Should -Not -Match '(?i)\bfetch\s*\('
    }
    It 'contains only read-only, PowerShell 5.1-parseable provider source' {
        foreach ($File in @(Get-ChildItem (Join-Path $Root 'Providers/ActiveDirectory/Compliance') -File -Filter '*.ps1')) {
            $Tokens=$null; $Errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($File.FullName,[ref]$Tokens,[ref]$Errors)
            @($Errors).Count | Should -Be 0
            (Get-Content $File.FullName -Raw) | Should -Not -Match '(?im)^\s*(Set-AD\w*|New-AD\w*|Remove-AD\w*|Add-AD\w*|Set-DnsServer\w*|Set-ItemProperty|Restart-Service|Stop-Service)\b'
        }
    }
}

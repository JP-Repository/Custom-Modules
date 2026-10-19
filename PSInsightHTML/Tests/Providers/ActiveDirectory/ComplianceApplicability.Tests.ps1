Describe 'AD multi-framework compliance applicability' {
    BeforeAll {
        $script:Root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $Root 'PSInsightHTML.psd1') -Force
        . (Join-Path $Root 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Full)
        $script:SE=New-PSIADSecurityEvidenceModel $Snapshot
        $script:HE=New-PSIADHealthEvidenceModel $Snapshot
        $null=Add-PSIADSecurityFictionalObservations $Snapshot $SE
        $null=Add-PSIADHealthFictionalObservations $Snapshot $HE
        $script:Security=Test-PSIADSecurity $Snapshot $SE
        $script:Health=Test-PSIADHealth $Snapshot $HE
        $script:Packs=@(Get-PSIADControlMappings -All)
        $script:MS=Test-PSIADCompliance $Snapshot $Security $Health $Packs[0]
        $script:NIST=Test-PSIADCompliance $Snapshot $Security $Health $Packs[1]
    }
    It 'registers two independently pinned mapping packs with unique identities' {
        $Packs.Count | Should -Be 2
        @($Packs | ForEach-Object FrameworkId | Sort-Object -Unique).Count | Should -Be 2
        @($Packs | Where-Object { -not $_.FrameworkVersion -or -not $_.Publisher -or -not $_.EvaluationMode }).Count | Should -Be 0
        { Get-PSIADControlMappings -FrameworkId 'missing' } | Should -Throw '*Unknown compliance framework*'
        @($MS.Controls+$NIST.Controls | ForEach-Object Identity | Sort-Object -Unique).Count | Should -Be 9
    }
    It 'distinguishes mapping from applicability on older fictional DCs' {
        $MS.FrameworkApplicability | Should -Be ContextOnly
        $MS.Counts.Mapped | Should -Be 6
        $MS.Counts.ContextOnly | Should -Be 6
        $MS.Counts.Fail | Should -Be 0
        @($MS.ResourceResults | Where-Object { $_.Status -ne 'ContextOnly' }).Count | Should -Be 0
        @($MS.ResourceResults | Where-Object OSVersion -eq '2016').Count | Should -BeGreaterThan 0
        @($MS.ResourceResults | Where-Object OSVersion -eq '2019').Count | Should -BeGreaterThan 0
    }
    It 'uses current-state technical applicability for the NIST slice' {
        $NIST.FrameworkApplicability | Should -Be Applicable
        $NIST.Counts.Applicable | Should -Be 3
        $NIST.Counts.Pass | Should -Be 0
        @($NIST.Controls | Where-Object { $_.MappingType -eq 'Partial' -and $_.Status -eq 'Pass' }).Count | Should -Be 0
        $NIST.EvidenceCompleteness.Percent | Should -BeGreaterThan 0
        $NIST.FrameworkCoverage.Percent | Should -BeNullOrEmpty
    }
    It 'uses one PSI rule in both frameworks without asserting control equivalence' {
        $Microsoft=@($MS.Controls | Where-Object { 'smb-signing' -in $_.SourceRuleIds })
        $Other=@($NIST.Controls | Where-Object { 'smb-signing' -in $_.SourceRuleIds })
        $Microsoft.Count | Should -Be 1
        $Other.Count | Should -Be 1
        $Microsoft[0].ControlId | Should -Not -Be $Other[0].ControlId
    }
    It 'makes OS, version and explicit role evidence deterministic' {
        $Mapping=@($Packs[0].Controls | Where-Object ControlId -eq 'CCE-37864-6')[0]
        (Resolve-PSIADComplianceApplicability $Snapshot $Packs[0] $Mapping 'dc-1').State | Should -Be ContextOnly
        $Copy=$Snapshot | Select-Object *
        $Copy.DomainControllers=@($Snapshot.DomainControllers | ForEach-Object { $_ | Select-Object * })
        $Copy.DomainControllers[0].OS='Windows Server 2025'
        (Resolve-PSIADComplianceApplicability $Copy $Packs[0] $Mapping 'dc-1').State | Should -Be Applicable
        $Copy.DomainControllers[0].OS=$null
        (Resolve-PSIADComplianceApplicability $Copy $Packs[0] $Mapping 'dc-1').State | Should -Be Unknown
        $Copy.DomainControllers[0].OS='Linux'
        (Resolve-PSIADComplianceApplicability $Copy $Packs[0] $Mapping 'dc-1').State | Should -Be NotApplicable
        $Copy.DomainControllers[0].OS='Windows Server 2025'
        $Copy.DomainControllers[0].InstalledFeatures=@([pscustomobject]@{ Name='AD-Domain-Services'; Installed=$false })
        (Resolve-PSIADComplianceApplicability $Copy $Packs[0] $Mapping 'dc-1').State | Should -Be NotApplicable
        (Resolve-PSIADComplianceApplicability $Snapshot $Packs[0] $Mapping 'site-1').State | Should -Be NotApplicable
        $DNSMapping=$Mapping.Clone(); $DNSMapping.ApplicableRoles=@('DNSServer')
        (Resolve-PSIADComplianceApplicability $Snapshot $Packs[0] $DNSMapping 'dc-7').State | Should -Be NotApplicable
        $FeatureMapping=$Mapping.Clone(); $FeatureMapping.RequiredFeatures=@('Missing-Fictional-Feature')
        (Resolve-PSIADComplianceApplicability $Snapshot $Packs[0] $FeatureMapping 'dc-1').State | Should -Be Unknown
    }
    It 'keeps unknown applicability from producing a pass or fail' {
        $Copy=$Snapshot | Select-Object *
        $Copy.DomainControllers=@($Snapshot.DomainControllers | ForEach-Object { $_ | Select-Object * })
        foreach ($DC in $Copy.DomainControllers) { $DC.OS=$null }
        $SC=$Security.PSObject.Copy(); $SC.Snapshot=$Copy
        $HC=$Health.PSObject.Copy(); $HC.Snapshot=$Copy
        $Result=Test-PSIADCompliance $Copy $SC $HC $Packs[0]
        $Result.FrameworkApplicability | Should -Be Unknown
        $Result.Counts.NotTested | Should -Be 6
        $Result.Counts.NotApplicable | Should -Be 0
        $Result.Counts.Fail | Should -Be 0
    }
    It 'aggregates a mixed estate from applicable resources only' {
        $Copy=$Snapshot | Select-Object *
        $Copy.DomainControllers=@($Snapshot.DomainControllers | ForEach-Object { $_ | Select-Object * })
        $Copy.DomainControllers[0].OS='Windows Server 2025'
        $SC=$Security.PSObject.Copy(); $SC.Snapshot=$Copy
        $HC=$Health.PSObject.Copy(); $HC.Snapshot=$Copy
        $Result=Test-PSIADCompliance $Copy $SC $HC $Packs[0]
        $Result.FrameworkApplicability | Should -Be Applicable
        $Result.Counts.Applicable | Should -Be 6
        @($Result.ResourceResults | Where-Object Applicability -eq Applicable).Count | Should -Be 6
        @($Result.ResourceResults | Where-Object Applicability -eq ContextOnly).Count | Should -Be 42
        $Result.Controls[0].Status | Should -Not -Be ContextOnly
    }
    It 'keeps supporting mappings out of result counts' {
        @($Packs[0].Controls | Where-Object MappingType -eq Supporting).Count | Should -Be 1
        @($Packs[1].Controls | Where-Object MappingType -eq Supporting).Count | Should -Be 1
        $MS.Counts.Mapped | Should -Be 6
        $NIST.Counts.Mapped | Should -Be 3
    }
    It 'allows a Direct mapping to pass only with complete Ready evidence' {
        $Pack=@{ FrameworkId='Test-Direct'; Framework='Test direct'; FrameworkVersion='1'; EvaluationMode='CurrentState'; ApplicableOperatingSystems=@('Windows Server'); ApplicableRoles=@('DomainController'); Controls=@(@{ ControlId='X-1'; ControlTitle='Signing'; ControlDescription='Selected signing observation'; SourceRuleIds=@('smb-signing'); EvidenceRequirements=@('EffectivePolicy'); MappingType='Direct'; MappingConfidence='High'; Reference='https://csrc.nist.gov/' }) }
        $Ready=@($Security.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'smb-signing' -and $_.Status -eq 'Ready' } | Select-Object -First 1)
        $Ready.Count | Should -Be 1
        $SC=$Security.PSObject.Copy(); $AC=$Security.Assessment.PSObject.Copy(); $AC.Checks=$Ready; $SC.Assessment=$AC
        (Test-PSIADCompliance $Snapshot $SC -MappingPack $Pack).Controls[0].Status | Should -Be Pass
        $AC.Checks=@($Security.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'smb-signing' -and $_.Status -eq 'Blocked' } | Select-Object -First 1)
        if ($AC.Checks.Count) { (Test-PSIADCompliance $Snapshot $SC -MappingPack $Pack).Controls[0].Status | Should -Be Fail }
    }
    It 'never treats a Supporting relationship as a standalone control outcome' {
        $Pack=@{ FrameworkId='Test-Support'; Framework='Test support'; FrameworkVersion='1'; EvaluationMode='CurrentState'; ApplicableOperatingSystems=@('Windows Server'); ApplicableRoles=@('DomainController'); Controls=@(
            @{ ControlId='X-2'; ControlTitle='Audit'; ControlDescription='Audit'; SourceRuleIds=@('audit-policy'); EvidenceRequirements=@('EffectiveAuditPolicy'); MappingType='Partial'; MappingConfidence='Low'; Reference='https://csrc.nist.gov/' },
            @{ MappingId='X-2-support'; ControlId='X-2'; ControlTitle='Log support'; ControlDescription='Support'; SourceRuleIds=@('event-retention'); EvidenceRequirements=@('EventLogConfiguration'); MappingType='Supporting'; MappingConfidence='Low'; Reference='https://csrc.nist.gov/' }
        ) }
        $Result=Test-PSIADCompliance $Snapshot $Security $Health $Pack
        $Result.Counts.Mapped | Should -Be 1
        $Result.Controls[0].SupportingMappings.Count | Should -Be 1
        $Result.Controls[0].Status | Should -Not -Be Pass
    }
    It 'retains one snapshot and does not mutate source outcomes' {
        [object]::ReferenceEquals($Snapshot,$MS.Snapshot) | Should -BeTrue
        [object]::ReferenceEquals($Snapshot,$NIST.Snapshot) | Should -BeTrue
        $Before=ConvertTo-Json -InputObject $Security.Assessment.Checks -Depth 7 -Compress
        $null=Test-PSIADCompliance $Snapshot $Security $Health $Packs[1]
        (ConvertTo-Json -InputObject $Security.Assessment.Checks -Depth 7 -Compress) | Should -Be $Before
        $Security.Assessment.Score | Should -Be 37.4
        $SE.EvidenceCompleteness.Percent | Should -Be 28.4
        $Health.Assessment.Score | Should -Be 61.8
    }
    It 'generates offline comparison, context, crosswalk and print metadata' {
        $Result=& (Join-Path $Root 'Examples/ActiveDirectory/Compliance/Invoke-PSIADCompliance.ps1') -Snapshot $Snapshot -NoBrowser -PassThru -OutputPath $TestDrive
        $Html=[System.IO.File]::ReadAllText($Result.HtmlPath)
        $Result.FrameworkResults.Count | Should -Be 2
        foreach ($Needle in @('Framework Comparison','Context Only','Crosswalk','Revision 5.1','FutureTarget','id="psi-print-document"','SC-8','CCE-37864-6')) { $Html | Should -Match $Needle }
        $Html | Should -Not -Match '(?i)<(?:script|link|img)[^>]+(?:src|href)="https?://'
        $Html | Should -Not -Match '(?i)\bfetch\s*\('
    }
    It 'uses only parseable, read-only provider compliance scripts' {
        foreach ($File in @(Get-ChildItem (Join-Path $Root 'Providers/ActiveDirectory/Compliance') -Recurse -File -Filter '*.ps1')) {
            $Tokens=$null; $Errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($File.FullName,[ref]$Tokens,[ref]$Errors)
            @($Errors).Count | Should -Be 0
            (Get-Content $File.FullName -Raw) | Should -Not -Match '(?im)^\s*(Set-AD\w*|New-AD\w*|Remove-AD\w*|Add-AD\w*|Set-DnsServer\w*|Set-ItemProperty|Restart-Service|Stop-Service)\b'
        }
    }
}

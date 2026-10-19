Describe 'AD Security evidence expansion' {
    BeforeAll {
        $script:Root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $Root 'PSInsightHTML.psd1') -Force
        . (Join-Path $Root 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        . (Join-Path $Root 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Raw=Collect-PSIADSnapshot -Domain root.example.test -Profile Security -CommandAdapter (New-PSIADLiveFixtureAdapter)
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
        $script:Evidence=New-PSIADSecurityEvidenceModel $Snapshot
        $script:Assessment=Test-PSIADSecurity $Snapshot $Evidence
    }
    It 'collects one optional runtime batch per in-scope DC without running Health remote checks' {
        @($Snapshot.SecurityRuntimeResults).Count | Should -Be 3
        @($Snapshot.CollectionResults | Where-Object { $_.CollectorId -eq 'Remote' -and $_.Requested }).Count | Should -Be 0
        @($Snapshot.CollectionResults | Where-Object CollectorId -eq SecurityRuntime).Count | Should -Be 3
        @($Snapshot.DomainControllers | Where-Object Domain -ne 'root.example.test').Count | Should -Be 0
    }
    It 'keeps effective SMB observation stronger than a selected registry DWORD' {
        $Fact=@($Evidence.Observations | Where-Object { $_.RuleId -eq 'smb-signing' -and $_.DC -eq 'dc-a.root.example.test' })[0]
        $Fact.Value | Should -Be Required
        $Fact.CollectionState | Should -Be Collected
        $Fact.EvidenceType | Should -Be EffectivePolicy
        $Fact.SourceType | Should -Be ProviderInput
        $Fact.SimulatedSourceType | Should -Be RuntimeConfiguration
        $Fact.Confidence | Should -Be Sample
    }
    It 'does not promote registry LDAP policy to effective' {
        $Fact=@($Evidence.Observations | Where-Object { $_.RuleId -eq 'ldap-signing' -and $_.DC -eq 'dc-a.root.example.test' })[0]
        $Fact.CollectionState | Should -Not -Be Collected
        $Fact.EvidenceType | Should -Be SelectedRegistry
    }
    It 'retains GPO links as low confidence intent' {
        @($Evidence.GpoIntent).Count | Should -Be 1
        $Evidence.GpoIntent[0].EffectivePolicyEstablished | Should -BeFalse
        $Evidence.GpoIntent[0].SourceType | Should -Be ProviderInput
        $Evidence.GpoIntent[0].SimulatedSourceType | Should -Be Directory
        $Evidence.GpoIntent[0].Confidence | Should -Be Sample
    }
    It 'preserves direct and nested privileged paths, account metadata, and forest context' {
        $Nested=@($Evidence.PrivilegedAccess.Members | Where-Object Principal -eq admin-b)[0]
        $Nested.Direct | Should -BeFalse
        $Nested.NestedPath.Count | Should -Be 3
        $Nested.Metadata.PasswordNeverExpires | Should -BeTrue
        @($Evidence.PrivilegedAccess.Groups | Where-Object { $_.Group -eq 'Enterprise Admins' -and $_.Scope -eq 'ForestRoot' }).Count | Should -Be 1
    }
    It 'preserves unresolved principals instead of silently discarding them' {
        $Unresolved=@($Evidence.PrivilegedAccess.Members | Where-Object ResolutionState -eq Failed)
        $Unresolved.Count | Should -Be 1
        $Unresolved[0].CollectionState | Should -Be Partial
        (@($Evidence.Observations | Where-Object RuleId -eq privileged-members)[0]).CollectionState | Should -Not -Be Collected
    }
    It 'derives KRBTGT age only from collected typed password metadata' {
        $Fact=@($Evidence.Observations | Where-Object RuleId -eq krbtgt-age)[0]
        $Fact.EvidenceType | Should -Be AccountMetadata
        $Fact.Value | Should -BeGreaterThan 300
        $Fact.SourceType | Should -Be ProviderInput
        $Fact.SimulatedSourceType | Should -Be Directory
        $Fact.Confidence | Should -Be Sample
    }
    It 'preserves sample provenance through projection without changing the fictional conclusion' {
        $Sample=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Security)
        $SampleEvidence=New-PSIADSecurityEvidenceModel $Sample
        $null=Add-PSIADSecurityFictionalObservations $Sample $SampleEvidence
        $SampleAssessment=Test-PSIADSecurity $Sample $SampleEvidence
        $Runtime=@($SampleEvidence.Observations | Where-Object { $_.RuleId -eq 'smb-signing' -and $_.DC -eq 'dc-01.corp.example' })[0]
        $Krbtgt=@($SampleEvidence.Observations | Where-Object RuleId -eq krbtgt-age)[0]
        $Runtime.SourceType | Should -Be ProviderInput
        $Runtime.SimulatedSourceType | Should -Be RuntimeConfiguration
        $Runtime.Confidence | Should -Be Sample
        $Krbtgt.SourceType | Should -Be ProviderInput
        $Krbtgt.SimulatedSourceType | Should -Be Directory
        $Krbtgt.Confidence | Should -Be Sample
        @($SampleEvidence.AuthenticationTelemetry | Where-Object SourceType -ne ProviderInput).Count | Should -Be 0
        $SampleAssessment.SecurityVerdict | Should -Be Critical
        $SampleAssessment.Assessment.Score | Should -Be 37.4
        $SampleEvidence.EvidenceCompleteness.Percent | Should -Be 28.4
    }
    It 'keeps partial audit policy and LDAPS certificate capability unverified' {
        foreach ($Id in @('audit-policy','ldaps-capability')) {
            $Fact=@($Evidence.Observations | Where-Object { $_.RuleId -eq $Id -and $_.DC -eq 'dc-a.root.example.test' })[0]
            $Fact.CollectionState | Should -Be Partial
            $Fact.Detail | Should -Not -BeNullOrEmpty
        }
        (@($Evidence.Observations | Where-Object RuleId -eq ldaps-usage)[0]).CollectionState | Should -Not -Be Collected
    }
    It 'retains Security log configuration as a bounded factual observation' {
        $Fact=@($Evidence.Observations | Where-Object { $_.RuleId -eq 'event-retention' -and $_.DC -eq 'dc-a.root.example.test' })[0]
        $Fact.Value | Should -Be 2048
        $Fact.Detail.LogMode | Should -Be Circular
    }
    It 'attributes NTLMv1 evidence to its DC, account and bounded window' {
        $Fact=@($Evidence.Observations | Where-Object { $_.RuleId -eq 'ntlmv1-usage' -and $_.DC -eq 'dc-b.root.example.test' })[0]
        $Fact.Value | Should -Be Observed
        $Fact.Detail[0].Account | Should -Be legacy-user
        $Fact.Detail[0].CollectionWindowHours | Should -Be 72
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'ntlmv1-usage' -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'retains Kerberos AES and RC4 attribution without declaring absent RC4 safe' {
        @($Evidence.AuthenticationTelemetry | Where-Object { $_.Kind -eq 'Kerberos' -and $_.Version -eq 'AES256' }).Count | Should -BeGreaterThan 0
        $Rc4=@($Evidence.AuthenticationTelemetry | Where-Object Version -eq RC4)[0]
        $Rc4.Service | Should -Be 'HTTP/legacy.example.test'
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'rc4-usage' -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'keeps firewall and Defender observations distinct from exposure and third-party status' {
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'firewall' -and $_.DC -eq 'dc-a.root.example.test' })[0]).Value | Should -Be Enabled
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'defender' -and $_.DC -eq 'dc-a.root.example.test' })[0]).Value | Should -Be Healthy
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'defender' -and $_.DC -eq 'dc-c.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'distinguishes Credential Guard running from LSASS and WDigest configuration' {
        $Guard=@($Evidence.Observations | Where-Object { $_.RuleId -eq 'credential-guard' -and $_.DC -eq 'dc-a.root.example.test' })[0]
        $Guard.Value | Should -Be Enabled
        $Guard.Detail.Running | Should -BeTrue
        foreach ($Id in @('lsass-protection','wdigest')) { (@($Evidence.Observations | Where-Object { $_.RuleId -eq $Id -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Be Partial }
    }
    It 'keeps SMBv1 runtime complete and Schannel registry configuration partial' {
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'smbv1' -and $_.DC -eq 'dc-a.root.example.test' })[0]).Value | Should -Be Disabled
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'tls10' -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Be Partial
    }
    It 'does not invent DNS security conclusions without complete zone transfer configuration' {
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'dns-zone-transfer' -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'projects complete DNS transfer configuration and preserves unknown modes' {
        $Copy=$Snapshot | Select-Object *
        $Dcs=@($Snapshot.DomainControllers | ForEach-Object { $_ | Select-Object * })
        $Dcs[0].DNSRole=$true; $Dcs[0].DNSQueryStates=@{ Zones='Collected' }
        $Dcs[0].DNSZones=@([pscustomobject]@{ Name='root.example.test'; ZoneType='Primary'; SecureSecondaries='TransferAnyServer' })
        $Copy.DomainControllers=$Dcs
        $Projected=New-PSIADSecurityEvidenceModel $Copy
        $Fact=@($Projected.Observations | Where-Object { $_.RuleId -eq 'dns-zone-transfer' -and $_.DC -eq 'dc-a.root.example.test' })[0]
        $Fact.Value | Should -Be Unrestricted
        $Fact.CollectionState | Should -Be Collected
        $Dcs[0].DNSZones[0].SecureSecondaries='Unknown'
        $Unknown=New-PSIADSecurityEvidenceModel $Copy
        (@($Unknown.Observations | Where-Object { $_.RuleId -eq 'dns-zone-transfer' -and $_.DC -eq 'dc-a.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'keeps failed and unsupported runtime collection explicit' {
        (@($Snapshot.SecurityRuntimeResults | Where-Object DC -eq 'dc-c.root.example.test')[0]).State | Should -Be NotSupported
        (@($Evidence.Observations | Where-Object { $_.RuleId -eq 'firewall' -and $_.DC -eq 'dc-c.root.example.test' })[0]).CollectionState | Should -Not -Be Collected
    }
    It 'improves evidence coverage through collected facts and consumes them with unchanged rules' {
        $Evidence.EvidenceCompleteness.Percent | Should -BeGreaterThan 0
        (@($Assessment.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'smb-signing' -and $_.Status -eq 'Ready' })).Count | Should -Be 1
        (@($Assessment.Assessment.Checks | Where-Object { $_.Metadata.RuleId -eq 'ntlmv1-usage' -and $_.Status -eq 'Blocked' })).Count | Should -Be 1
    }
    It 'preserves the same snapshot for Inventory, both Readiness profiles and Health' {
        $Before=$Snapshot | ConvertTo-Json -Depth 30 -Compress
        $Inventory=New-PSIADDCInventoryModel $Snapshot
        $Ready22=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022
        $Ready25=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
        $HealthEvidence=New-PSIADHealthEvidenceModel $Snapshot
        $Health=Test-PSIADHealth $Snapshot $HealthEvidence
        $Inventory.Summary.DCCount | Should -Be 3
        $Ready22.Assessment | Should -Not -BeNullOrEmpty
        $Ready25.Assessment | Should -Not -BeNullOrEmpty
        $Health.Assessment | Should -Not -BeNullOrEmpty
        ($Snapshot | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly $Before
    }
    It 'parses new provider files for PowerShell 5.1 and excludes mutation commands' {
        foreach ($File in @('Collectors/Get-PSIADSecurityRuntimeFacts.ps1','Collectors/Get-PSIADPrivilegedFacts.ps1','Fixtures/Add-PSIADSecuritySampleFacts.ps1')) {
            $Path=Join-Path $Root "Providers/ActiveDirectory/$File"
            $Tokens=$null; $Errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$Tokens,[ref]$Errors)
            @($Errors).Count | Should -Be 0
            (Get-Content $Path -Raw) | Should -Not -Match '(?im)\b(Set|Add|New|Remove)-AD\w+\b|\bauditpol\s+/set\b|\bSet-GP\w+\b|\b(Set|New|Remove)-NetFirewall\w+\b'
        }
    }
}

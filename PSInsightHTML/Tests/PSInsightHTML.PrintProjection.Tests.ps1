$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'Dedicated Application print projection' {
    BeforeAll {
        $script:Output = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        $Report = New-PSIReport -Title 'Fictional assessment' -Subtitle 'Sample only' -Layout Application -Theme Dark
        $script:Report = $Report
        $Finding = New-PSIApplicationFinding -Definition @{ Id='finding-one'; Title='A <priority> finding'; Severity='Critical'; Status='Open'; Category='Availability'; Summary='Observed failure'; ReadinessImpact='Healthy service'; AffectedResourceIds=@('resource-one'); EvidenceIds=@('evidence-one'); Recommendation=@{ Action='Investigate the sample' }; Validation=@{ Method='Repeat the check' } }
        $Resource = New-PSIResource -Definition @{ Id='resource-one'; Name='Example resource'; Type='Service'; Status='Critical'; Properties=@{ Region='Fictional'; Secret='not approved for print' }; FindingIds=@('finding-one'); EvidenceIds=@('evidence-one') }
        $Evidence = New-PSIEvidenceRecord -Definition @{ Id='evidence-one'; Title='Sample observation'; Type='Sample'; Source='Fictional monitor'; Summary='Failure seen'; Data=@{ Secret='RAW_PAYLOAD_MUST_NOT_PRINT' }; FindingIds=@('finding-one'); ResourceIds=@('resource-one') }
        $Model = New-PSIApplicationModel -Findings @($Finding) -Resources @($Resource) -Evidence @($Evidence)
        $null = $Report | Set-PSIApplicationModel -Model $Model
        $Category = New-PSIAssessmentCategory -Definition @{ Id='availability'; Name='Availability'; CheckIds=@('check-one') }
        $Check = New-PSIAssessmentCheck -Definition @{ Id='check-one'; Name='Service response'; CategoryId='availability'; Status='Blocked'; IsBlocking=$true; ObservedState='Failed'; ExpectedState='Healthy'; FindingIds=@('finding-one'); ResourceIds=@('resource-one'); EvidenceIds=@('evidence-one') }
        $Assessment = New-PSIApplicationAssessment -Definition @{ Id='assessment-one'; Name='Sample readiness'; AssessmentType='Readiness'; Target='Fictional target'; Profile='Sample profile'; Scope='Fictional scope'; Categories=@($Category); Checks=@($Check); FindingIds=@('finding-one'); ResourceIds=@('resource-one'); EvidenceIds=@('evidence-one'); Recommendations=@('Review evidence'); Metadata=@{ EvidenceCoveragePercent=80; Print=@{ ResourceColumns=@('Name','Type','Status') } }; Exceptions=@(@{ Id='exception-one'; Title='Sample exception'; Reason='Change window'; Status='Pending'; ResourceIds=@('resource-one') }) }
        $null = $Report | Set-PSIApplicationAssessment -Assessment $Assessment
        $Report | Add-PSISection -Title 'Overview' | Add-PSIRow | Add-PSIText -Text 'Interactive content' | Out-Null
        Export-PSIReport -Report $Report -Path $script:Output | Out-Null
        $script:Html = [System.IO.File]::ReadAllText($script:Output)
        $script:PrintHtml = [regex]::Match($script:Html, '(?s)<article class="psi-print-document".*?</article>\s*<div class="psi-global-search').Value
        if (-not $script:PrintHtml) { $script:PrintHtml = [regex]::Match($script:Html, '(?s)<article class="psi-print-document".*?<footer class="psi-print-end">.*?</footer></article>').Value }
    }
    AfterAll { if (Test-Path -LiteralPath $script:Output) { Remove-Item -LiteralPath $script:Output -Force } }

    It 'generates a separate model-based document and does not print the interactive shell' {
        $script:PrintHtml | Should -Match 'psi-print-cover'
        $script:PrintHtml | Should -Match 'psi-print-contents'
        $script:PrintHtml | Should -Not -Match 'psi-app-sidebar|data-psi-app-view|data-psi-export-toolbar|data-psi-table-search'
        $script:Html | Should -Match 'psi-app-shell'
    }
    It 'includes cover, management summary, posture and methodology from the model' {
        $script:PrintHtml | Should -Match 'Fictional target'
        $script:PrintHtml | Should -Match 'NotReady'
        $script:PrintHtml | Should -Match '80%'
        $script:PrintHtml | Should -Match 'Primary reasons|Recommended next actions'
        $script:PrintHtml | Should -Match 'Availability'
        $script:PrintHtml | Should -Match 'Evidence coverage'
    }
    It 'orders findings, includes check and resource registers, and excludes raw evidence payloads' {
        $script:PrintHtml | Should -Match 'A &lt;priority&gt; finding'
        $script:PrintHtml | Should -Match 'check-one'
        $script:PrintHtml | Should -Match 'Example resource'
        $script:PrintHtml | Should -Match 'Sample observation'
        $script:PrintHtml | Should -Match 'Collection state</dt><dd>Not supplied'
        $script:PrintHtml | Should -Match 'Checks</dt><dd>check-one'
        $script:PrintHtml | Should -Not -Match 'RAW_PAYLOAD_MUST_NOT_PRINT|not approved for print'
    }
    It 'includes recorded exceptions and paper-safe status labels' {
        $script:PrintHtml | Should -Match 'Sample exception'
        $script:PrintHtml | Should -Match 'psi-print-status">Blocked'
        $script:Html | Should -Match 'table-header-group'
    }
    It 'uses a dedicated light print theme and standalone print action' {
        $script:Html | Should -Match 'data-theme="Dark"'
        $script:Html | Should -Match 'color-scheme: light !important'
        $script:Html | Should -Match 'PSIPrint\.print\(\)'
        $script:Html | Should -Match 'beforeprint'
        $script:Html | Should -Match 'afterprint'
        $script:Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
    }
    It 'escapes untrusted report identity before placing it in page-margin CSS' {
        InModuleScope PSInsightHTML {
            $Safe = ConvertTo-PSICssString -Value 'Sample "</style> report'
            $Safe | Should -Not -Match '"|</style>|[\r\n]'
            $Safe | Should -Match '\\3c '
        }
        $script:Html | Should -Match '@bottom-left \{ content:'
        $script:Html | Should -Match '@bottom-right \{ content:'
    }
    It 'leaves legacy reports without a dedicated print container' {
        $Legacy = New-PSIReport -Title Legacy
        $Legacy | Add-PSISection -Title Basic | Add-PSIRow | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try { Export-PSIReport -Report $Legacy -Path $Path | Out-Null; [System.IO.File]::ReadAllText($Path) | Should -Not -Match 'id="psi-print-document"' }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }
    It 'honors disabled report printing without embedding projection assets' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            Export-PSIReport -Report $script:Report -Path $Path -EnableReportPrint $false | Out-Null
            $Disabled = [System.IO.File]::ReadAllText($Path)
            $Disabled | Should -Not -Match 'id="psi-print-document"|root\.PSIPrint|data-psi-export-scope="report"'
            $Disabled | Should -Match 'psi-app-shell'
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }
    It 'prints all linked model records independently of active view filters and pagination' {
        $script:PrintHtml | Should -Match 'Example resource'
        $script:PrintHtml | Should -Match 'Sample observation'
        $script:PrintHtml | Should -Match 'Service response'
        $script:PrintHtml | Should -Not -Match 'data-psi-filter|data-psi-pagination|data-psi-app-view'
    }
    It 'omits exceptions and evidence sections when absent or explicitly excluded' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $OriginalExceptions = $Report.ApplicationAssessment.Exceptions
            $OriginalPrint = $Report.ApplicationAssessment.Metadata.Print
            try {
                $Report.ApplicationAssessment.Exceptions = @()
                $Report.ApplicationAssessment.Metadata.Print = @{ IncludeEvidenceAppendix=$false }
                $Document = ConvertTo-PSIPrintProjection -Report $Report
                $Document | Should -Not -Match 'id="psi-print-exceptions"|id="psi-print-evidence"'
                $Document | Should -Match 'id="psi-print-checks"'
            }
            finally {
                $Report.ApplicationAssessment.Exceptions = $OriginalExceptions
                $Report.ApplicationAssessment.Metadata.Print = $OriginalPrint
            }
        }
    }
    It 'sorts current critical findings before warning findings' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $Warning = New-PSIApplicationFinding -Definition @{ Id='finding-two'; Title='Warning observation'; Severity='Warning'; Status='Open'; Category='Availability' }
            $Original = $Report.ApplicationModel.Findings
            $OriginalIds = $Report.ApplicationAssessment.FindingIds
            try {
                $Report.ApplicationModel.Findings = @($Warning) + @($Original)
                $Report.ApplicationAssessment.FindingIds = @('finding-two','finding-one')
                $Document = ConvertTo-PSIPrintProjection -Report $Report
                $Document.IndexOf('A &lt;priority&gt; finding') | Should -BeLessThan $Document.IndexOf('Warning observation')
            }
            finally {
                $Report.ApplicationModel.Findings = $Original
                $Report.ApplicationAssessment.FindingIds = $OriginalIds
            }
        }
    }
}

Describe 'Optional provider print display contract' {
    BeforeAll {
        $script:Report = New-PSIReport -Title 'Safe print fixture' -Layout Application
        $Resource = New-PSIResource -Definition @{ Id='resource-safe'; Name='Long-example-resource-name-that-needs-wrapping.example.invalid'; Type='Service'; Status='Warning'; Properties=@{ Region='<west>'; Secret='LEAK_RESOURCE_SECRET'; Empty=''; Owner=$null } }
        $Evidence = New-PSIEvidenceRecord -Definition @{ Id='evidence-safe'; Title='Evidence item'; Type='Observation'; Source='source.example.invalid'; Summary='Observed <text>'; Data=@{ Token='LEAK_RAW_TOKEN' }; Metadata=@{ CollectionStateApplicability='NotApplicable' }; ResourceIds=@('resource-safe') }
        $Model = New-PSIApplicationModel -Resources @($Resource) -Evidence @($Evidence)
        $null = $script:Report | Set-PSIApplicationModel -Model $Model
        $Category = New-PSIAssessmentCategory -Definition @{ Id='sample'; Name='Sample'; CheckIds=@('check-safe') }
        $Check = New-PSIAssessmentCheck -Definition @{ Id='check-safe'; Name='Check'; CategoryId='sample'; Status='Review'; ObservedState='Observed'; ExpectedState='Expected'; ResourceIds=@('resource-safe'); EvidenceIds=@('evidence-safe') }
        $Assessment = New-PSIApplicationAssessment -Definition @{ Id='assessment-safe'; Name='Sample'; AssessmentType='Readiness'; Target='Sample'; Profile='Sample profile'; Scope='Fictional fixture'; Categories=@($Category); Checks=@($Check); ResourceIds=@('resource-safe'); EvidenceIds=@('evidence-safe'); Metadata=@{} }
        $null = $script:Report | Set-PSIApplicationAssessment -Assessment $Assessment
        $script:Report | Add-PSISection -Title 'Overview' | Add-PSIRow | Out-Null
    }
    It 'uses safe zero-configuration fields and omits raw payloads' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $Html = ConvertTo-PSIPrintProjection -Report $Report
            $Html | Should -Match 'Long-example-resource-name'
            $Html | Should -Match 'Collection state</dt><dd>Not applicable'
            $Html | Should -Not -Match 'LEAK_RESOURCE_SECRET|LEAK_RAW_TOKEN'
        }
    }
    It 'accepts generic resource and evidence labels, order, and formatting' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $Report.ApplicationAssessment.Metadata.PrintDisplay = @{
                ReportIdentity=@{ Kicker='Fictional document' }
                Resources=@{ Columns=@(
                    @{ Property='Status'; Label='Health'; Order=3; Format='Status' },
                    @{ Property='Region'; Label='Area'; Order=1 },
                    @{ Property='Name'; Label='Resource'; Order=2 }
                ) }
                Evidence=@{ Fields=@(
                    @{ Property='Summary'; Label='Observation'; Order=2 },
                    @{ Property='Source'; Label='Origin'; Order=1 }
                ) }
            }
            $Html = ConvertTo-PSIPrintProjection -Report $Report
            $Html | Should -Match 'Fictional document'
            $Html | Should -Match '<th scope="col">Area</th><th scope="col">Resource</th><th scope="col">Health</th>'
            $Html | Should -Match '<th scope="col">Area</th>.*?&lt;west&gt;'
            $Html | Should -Match 'Origin</dt><dd>source.example.invalid</dd>.*Observation</dt><dd>Observed &lt;text&gt;'
        }
    }
    It 'normalizes duplicate, malformed, unsupported, and sensitive requests without breaking print' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $Report.ApplicationAssessment.Metadata.PrintDisplay = @{
                Resources=@{ Columns=@(
                    @{ Property='Region'; Label='Area'; Order=0 },
                    @{ Property='Region'; Label='Duplicate' },
                    @{ Property='Secret'; Label='Unsafe' },
                    @{ Property='Password'; Label='Password' },
                    @{ Property='Owner'; Label='Owner'; Format='Execute' },
                    @{ Property='Name'; Label='Name'; Order='bad' },
                    @{ Label='No property' }
                ) }
                Evidence=@{ Fields=@(
                    @{ Property='Data'; Label='Raw data' },
                    @{ Property='Metadata'; Label='Raw metadata' },
                    @{ Property='Summary'; Label='Summary'; Format='Text' }
                ) }
            }
            $Html = ConvertTo-PSIPrintProjection -Report $Report
            $Html | Should -Match 'Area|Name'
            $Html | Should -Not -Match 'Duplicate|LEAK_RESOURCE_SECRET|LEAK_RAW_TOKEN|No property|Raw data|Raw metadata'
            @([regex]::Matches($Html, '<th scope="col">Area</th>')).Count | Should -Be 1
        }
    }
    It 'omits empty values and supports explicit collection states' {
        InModuleScope PSInsightHTML -Parameters @{ Report=$script:Report } {
            $Report.ApplicationAssessment.Metadata.PrintDisplay = @{ Evidence=@{ Fields=@(
                @{ Property='CollectionState'; Label='Collection state' },
                @{ Property='Scope'; Label='Scope' },
                @{ Property='CollectedAt'; Label='Collected'; Format='DateTime' }
            ) } }
            $Evidence = $Report.ApplicationModel.Evidence[0]
            $Evidence.Metadata = @{}
            $Missing = ConvertTo-PSIPrintProjection -Report $Report
            $Missing | Should -Match 'Collection state</dt><dd>Not supplied'
            $Missing | Should -Not -Match 'Collected</dt><dd>'
            $Evidence.Metadata = @{ CollectionState='Partial' }
            $Partial = ConvertTo-PSIPrintProjection -Report $Report
            $Partial | Should -Match 'Collection state</dt><dd>Partial'
            $Evidence.Metadata = @{ CollectionStateApplicability='NotApplicable' }
        }
    }
    It 'normalizes field models and rejects complex values' {
        InModuleScope PSInsightHTML {
            $Fields = Resolve-PSIPrintDisplay -Configuration @{ Resources=@{ Columns=@(@{ Property='Name'; Order=2 },@{ Property='Status'; Order=1; Format='Status' }) } }
            $Fields.Resources[0].Property | Should -Be 'Status'
            $Fields.Resources[0].Visible | Should -BeTrue
            (Format-PSIPrintField -Value @{ Password='secret' } -Format Text) | Should -Be ''
            (Format-PSIPrintField -Value @() -Format List) | Should -Be ''
            (Format-PSIPrintField -Value $true -Format Boolean) | Should -Be 'Yes'
        }
    }
    It 'normalizes generic check and finding fields without exposing nested objects' {
        InModuleScope PSInsightHTML {
            $Fields = Resolve-PSIPrintDisplay -Configuration @{
                Checks=@{ Columns=@(@{ Property='Status'; Label='Result'; Format='Status' }) }
                Findings=@{ Fields=@(@{ Property='Recommendation'; Label='Action' },@{ Property='Metadata'; Label='Raw' }) }
            }
            $Fields.Checks[0].Label | Should -Be 'Result'
            $Fields.Findings.Count | Should -Be 1
            $Finding = [pscustomobject]@{ Recommendation=@{ Action='Review sample evidence'; Password='LEAK' } }
            (Get-PSIPrintFieldValue -Kind Findings -Record $Finding -Property Recommendation) | Should -Be 'Review sample evidence'
        }
    }
    It 'keeps long names and values wrapped in the standalone print stylesheet' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            Export-PSIReport -Report $script:Report -Path $Path | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'Long-example-resource-name-that-needs-wrapping'
            $Html | Should -Match 'word-wrap: break-word; overflow-wrap: anywhere'
            $Html | Should -Not -Match 'LEAK_RESOURCE_SECRET|LEAK_RAW_TOKEN|<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*='
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }
}

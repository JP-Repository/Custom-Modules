$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'Generic application assessment and posture' {
    BeforeAll {
        function New-ScenarioAssessment {
            param([string[]] $Statuses, [double[]] $Weights, [int[]] $Blockers = @(), [object[]] $Exceptions = @())
            $Checks = @(
                for ($I = 0; $I -lt $Statuses.Count; $I++) {
                    New-PSIAssessmentCheck -Definition @{
                        Id="check-$I"; Name="Check $I"; CategoryId='category-one'; Status=$Statuses[$I]
                        Weight=$Weights[$I]; IsBlocking=($I -in $Blockers); ObservedState='<observed>'
                        ExpectedState='Expected'; Recommendation=@{ Action='Review supplied data' }
                        Validation=@{ Method='Compare snapshots'; ExpectedResult='Expected'; Command='Get-SampleOnly' }
                    }
                }
            )
            $Category = New-PSIAssessmentCategory -Definition @{ Id='category-one'; Name='Sample <category>'; Icon='Rules'; Weight=2; CheckIds=@($Checks | ForEach-Object { $_.Id }) }
            New-PSIApplicationAssessment -Definition @{
                Id='assessment-one'; Name='Sample <assessment>'; AssessmentType='Readiness'; Target='Target <sample>'
                Profile='Fictional profile'; GeneratedAt=[datetime]'2026-10-16'; Categories=@($Category); Checks=$Checks
                Exceptions=$Exceptions; ReadyScoreMinimum=90; ReviewScoreMinimum=75
            }
        }
    }

    It 'creates an assessment, category and check with a structured explanation' {
        $A = New-ScenarioAssessment -Statuses @('Ready') -Weights @(1)
        $A.Score | Should -Be 100
        $A.Decision | Should -Be 'Ready'
        $A.OverallStatus | Should -Be 'Healthy'
        $A.Categories[0].Score | Should -Be 100
        $A.ScoreExplanation.CategoryScores[0].Weight | Should -Be 2
        $A.ScoreExplanation.CheckPoints.NotApplicable | Should -Be 'Excluded'
    }

    It 'rejects duplicate category and check IDs, unknown categories and inconsistent CheckIds' {
        $A = New-ScenarioAssessment -Statuses @('Ready','Review') -Weights @(1,1)
        $A.Categories = @($A.Categories[0],$A.Categories[0])
        { New-PSIApplicationAssessment -Definition @{Id='dup-cat';Name='Dup';AssessmentType='Health';Target='Sample';Profile='Sample';Categories=$A.Categories;Checks=$A.Checks} } | Should -Throw '*duplicate*'
        $A = New-ScenarioAssessment -Statuses @('Ready','Review') -Weights @(1,1)
        $A.Checks[1].Id = 'check-0'
        { New-PSIApplicationAssessment -Definition @{Id='dup';Name='Dup';AssessmentType='Health';Target='Sample';Profile='Sample';Categories=$A.Categories;Checks=$A.Checks} } | Should -Throw '*duplicate*'
        $A = New-ScenarioAssessment -Statuses @('Ready') -Weights @(1)
        $A.Checks[0].CategoryId = 'missing'
        { New-PSIApplicationAssessment -Definition @{Id='bad';Name='Bad';AssessmentType='Health';Target='Sample';Profile='Sample';Categories=$A.Categories;Checks=$A.Checks} } | Should -Throw '*missing Category*'
    }

    It 'rejects invalid check status, weights and computed category overrides' {
        { New-PSIAssessmentCheck -Definition @{Id='bad';Name='Bad';CategoryId='cat';Status='Maybe'} } | Should -Throw
        { New-PSIAssessmentCheck -Definition @{Id='bad';Name='Bad';CategoryId='cat';Status='Ready';Weight=0} } | Should -Throw
        { New-PSIAssessmentCategory -Definition @{Id='bad';Name='Bad';Score=90} } | Should -Throw
    }

    It 'uses check and category weights and never lets a high score hide a blocker' {
        $A = New-ScenarioAssessment -Statuses @('Ready','Blocked') -Weights @(20,1) -Blockers @(1)
        $A.Score | Should -Be 95.2
        $A.Decision | Should -Be 'NotReady'
        $A.OverallStatus | Should -Be 'Critical'
        $A.ScoreExplanation.Counts.Blockers | Should -Be 1
        $A.ScoreExplanation.Reasons -join ' ' | Should -Match 'blocking checks'
    }

    It 'combines category scores using category weights' {
        $Ready = New-PSIAssessmentCheck -Definition @{Id='ready-one';Name='Ready';CategoryId='cat-ready';Status='Ready'}
        $Blocked = New-PSIAssessmentCheck -Definition @{Id='blocked-one';Name='Blocked';CategoryId='cat-blocked';Status='Blocked'}
        $ReadyCategory = New-PSIAssessmentCategory -Definition @{Id='cat-ready';Name='Ready category';Weight=3;CheckIds=@('ready-one')}
        $BlockedCategory = New-PSIAssessmentCategory -Definition @{Id='cat-blocked';Name='Blocked category';Weight=1;CheckIds=@('blocked-one')}
        $A = New-PSIApplicationAssessment -Definition @{Id='weighted';Name='Weighted';AssessmentType='Health';Target='Sample';Profile='Sample';Categories=@($ReadyCategory,$BlockedCategory);Checks=@($Ready,$Blocked)}
        $A.Score | Should -Be 75
        $A.Decision | Should -Be 'NotReady'
        $A.ScoreExplanation.CategoryScores[0].Score | Should -Be 100
        $A.ScoreExplanation.CategoryScores[1].Score | Should -Be 0
    }

    It 'overrides a perfect score when an open critical finding is in scope' {
        $Finding = New-PSIApplicationFinding -Definition @{Id='critical-one';Title='Critical sample';Severity='Critical';Status='Open'}
        $Model = New-PSIApplicationModel -Findings @($Finding)
        $A = New-ScenarioAssessment -Statuses @('Ready') -Weights @(1)
        $A.FindingIds = @('critical-one')
        $Report = New-PSIReport -Title X -Layout Application
        $Report | Set-PSIApplicationModel -Model $Model | Out-Null
        $Report | Set-PSIApplicationAssessment -Assessment $A | Out-Null
        $A.Score | Should -Be 100
        $A.Decision | Should -Be 'NotReady'
        $A.ScoreExplanation.Counts.CriticalFindings | Should -Be 1
    }

    It 'excludes NotApplicable, treats NotTested as incomplete and Unknown explicitly' {
        $A = New-ScenarioAssessment -Statuses @('Ready','NotApplicable') -Weights @(1,20)
        $A.Score | Should -Be 100
        $A.Decision | Should -Be 'Ready'
        $A.ScoreExplanation.Counts.NotApplicable | Should -Be 1
        (New-ScenarioAssessment -Statuses @('Ready','NotTested') -Weights @(1,1)).Decision | Should -Be 'Incomplete'
        (New-ScenarioAssessment -Statuses @('Ready','Unknown') -Weights @(1,1)).Decision | Should -Be 'Unknown'
        $OnlyExcluded = New-ScenarioAssessment -Statuses @('NotApplicable') -Weights @(1)
        $OnlyExcluded.Score | Should -BeNullOrEmpty
        $OnlyExcluded.Decision | Should -Be 'Unknown'
    }

    It 'distinguishes review decisions from ready decisions using thresholds' {
        $A = New-ScenarioAssessment -Statuses @('Ready','Review') -Weights @(10,1)
        $A.Score | Should -Be 95.5
        $A.Decision | Should -Be 'ReadyWithReview'
        { New-PSIApplicationAssessment -Definition @{Id='bad';Name='Bad';AssessmentType='Health';Target='Sample';Profile='Sample';ReadyScoreMinimum=60;ReviewScoreMinimum=80} } | Should -Throw
    }

    It 'validates approved exceptions and keeps them informational' {
        $Exception = @{ Id='exception-one'; Title='Sample exception'; Reason='Sample review'; Status='Approved'; ApprovedBy='Fictional board'; ApprovedAt=[datetime]'2026-10-10'; ExpiresAt=[datetime]'2026-10-20'; CheckId='check-1' }
        $A = New-ScenarioAssessment -Statuses @('Ready','Blocked') -Weights @(20,1) -Blockers @(1) -Exceptions @($Exception)
        $A.Exceptions.Count | Should -Be 1
        $A.Decision | Should -Be 'NotReady'
        $Bad = $Exception.Clone(); $Bad.Remove('ApprovedBy')
        { New-ScenarioAssessment -Statuses @('Ready','Blocked') -Weights @(20,1) -Exceptions @($Bad) } | Should -Throw
        $Bad = $Exception.Clone(); $Bad.ExpiresAt = [datetime]'2026-10-09'
        { New-ScenarioAssessment -Statuses @('Ready','Blocked') -Weights @(20,1) -Exceptions @($Bad) } | Should -Throw
    }

    It 'rejects broken Finding, Resource and Evidence references on attachment' {
        $A = New-ScenarioAssessment -Statuses @('Review') -Weights @(1)
        $A.FindingIds = @('missing')
        $Report = New-PSIReport -Title X -Layout Application
        $Report | Set-PSIApplicationModel -Model (New-PSIApplicationModel) | Out-Null
        { $Report | Set-PSIApplicationAssessment -Assessment $A } | Should -Throw '*broken FindingIds*'
    }

    It 'renders encoded posture, category navigation and a standalone Checks workspace' {
        $A = New-ScenarioAssessment -Statuses @('Ready','Blocked') -Weights @(20,1) -Blockers @(1)
        $A.Checks[1].Recommendation.Action = '<script>alert(1)</script>'
        $Report = New-PSIReport -Title X -Layout Application
        $Report | Set-PSIApplicationModel -Model (New-PSIApplicationModel) | Out-Null
        $Report | Set-PSIApplicationAssessment -Assessment $A | Out-Null
        $Report | Add-PSIView -Id overview -Title Overview -Initial | Add-PSISection -Title Overview | Add-PSIRow | Add-PSIAssessmentOverview | Out-Null
        $Report | Add-PSIView -Id checks -Title Checks | Add-PSISection -Title Checks | Add-PSIRow |
            Add-PSIExplorer -Id checks-list -Title Checks -Data $A.Checks -TitleProperty Name -StatusProperty Status -EntityType Check -FilterProperties @('CategoryId','Status') |
            Add-PSIRow | Add-PSIExplorer -Id categories-list -Title Categories -Data $A.Categories -TitleProperty Name -EntityType Category | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            Export-PSIReport -Report $Report -Path $Path | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'NOT READY'
            $Html | Should -Match '95.2%'
            $Html | Should -Match 'Sample &lt;assessment&gt;'
            $Html | Should -Match 'Target &lt;sample&gt;'
            $Html | Should -Match 'data-psi-category-target="checks"'
            $Html | Should -Match 'psi-assessment-category psi-status-critical'
            $Html | Should -Match 'psi-assessment-category-result'
            $Html | Should -Match 'Ready \| .* Review \| .* Blocked \| .* Not Tested'
            $Html | Should -Match 'psi-assessment-verdict'
            $Html | Should -Match 'data-psi-explorer-filter="CategoryId"'
            $Html | Should -Match '&lt;observed&gt;'
            $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
            $Html | Should -Not -Match '<script>alert\(1\)</script>'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\('
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }

    It 'generates a fictional 49-check demo with seven categories and two exceptions' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            & (Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/New-AdaptiveDemoReport.ps1') -OutputPath $Path -NoBrowser | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            ([regex]::Matches($Html,'id="adaptive-checks-item-[0-9]+"')).Count | Should -Be 49
            ([regex]::Matches($Html,'id="adaptive-categories-item-[0-9]+"')).Count | Should -Be 7
            ([regex]::Matches($Html,'id="adaptive-exceptions-item-[0-9]+"')).Count | Should -Be 2
            $Html | Should -Match 'data-psi-app-view="exceptions"'
            $Html | Should -Match 'NOT READY'
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }

    It 'leaves the legacy Report assessment API available without Application output' {
        $Legacy = New-PSIReport -Title Legacy
        $Legacy.PSObject.Properties['ApplicationAssessment'] | Should -BeNullOrEmpty
        { $Legacy | Set-PSIApplicationAssessment -Assessment (New-ScenarioAssessment -Statuses @('Ready') -Weights @(1)) } | Should -Throw
        (Get-Command New-PSIAssessment -Module PSInsightHTML).Name | Should -Be 'New-PSIAssessment'
    }
}

function New-PSIApplicationAssessment {
    <# .SYNOPSIS Create a generic assessment with computed posture and decision. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    $Allowed = @('Id','Name','Description','AssessmentType','Target','Profile','Scope','GeneratedAt','Categories','Checks','FindingIds','ResourceIds','EvidenceIds','Recommendations','Exceptions','Metadata','ReadyScoreMinimum','ReviewScoreMinimum')
    foreach ($Key in $Definition.Keys) { if ($Key -notin $Allowed) { throw "Assessment contains unknown or computed field '$Key'." } }
    $Ready = if ($Definition.ContainsKey('ReadyScoreMinimum')) { [double] $Definition.ReadyScoreMinimum } else { 90.0 }
    $Review = if ($Definition.ContainsKey('ReviewScoreMinimum')) { [double] $Definition.ReviewScoreMinimum } else { 75.0 }
    if ($Ready -lt 0 -or $Ready -gt 100 -or $Review -lt 0 -or $Review -gt $Ready) { throw 'Assessment score thresholds must satisfy 0 <= Review <= Ready <= 100.' }
    $Exceptions = @(
        foreach ($Exception in @($Definition.Exceptions | Where-Object { $null -ne $_ })) {
            if ($Exception -isnot [hashtable]) { throw 'Assessment Exceptions must be hashtables.' }
            New-PSIAssessmentContractObject -Kind Exception -Definition $Exception
        }
    )
    $Assessment = [pscustomobject]@{
        Id=$Definition.Id; Name=$Definition.Name; Description=$Definition.Description; AssessmentType=$Definition.AssessmentType
        Target=$Definition.Target; Profile=$Definition.Profile; Scope=$Definition.Scope
        GeneratedAt=if ($Definition.ContainsKey('GeneratedAt')) { $Definition.GeneratedAt } else { Get-Date }
        OverallStatus=$null; Score=$null; Decision=$null
        Categories=@($Definition.Categories); Checks=@($Definition.Checks)
        FindingIds=@($Definition.FindingIds | Where-Object { $null -ne $_ })
        ResourceIds=@($Definition.ResourceIds | Where-Object { $null -ne $_ })
        EvidenceIds=@($Definition.EvidenceIds | Where-Object { $null -ne $_ })
        Recommendations=@($Definition.Recommendations | Where-Object { $null -ne $_ })
        Exceptions=$Exceptions; Metadata=if ($Definition.Metadata) { $Definition.Metadata } else { @{} }
        Thresholds=[pscustomobject]@{ Ready=$Ready; Review=$Review }
        ScoreExplanation=$null
    }
    Resolve-PSIAssessmentPosture -Assessment $Assessment
}

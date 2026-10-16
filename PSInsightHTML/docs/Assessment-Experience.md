# Generic assessment experience (Milestone 11.5)

PSInsightHTML calculates and presents posture. Providers define what a check means, its expected state, whether it blocks a decision, and any recommendation or validation guidance. No provider collection, command execution, approval workflow, or remediation runs in the HTML.

The Application assessment is separate from the existing `New-PSIAssessment` report API. It requires `New-PSIReport -Layout Application` and an attached Milestone 11.4 intelligence model. Existing Report layout and provider reports remain compatible.

## Contracts

`New-PSIAssessmentCategory -Definition @{...}` accepts `Id`, `Name`, `Description`, `Icon`, positive `Weight`, `CheckIds`, `FindingIds`, `ResourceIds`, and `Metadata`. `Status` and `Score` are computed.

`New-PSIAssessmentCheck -Definition @{...}` accepts `Id`, `Name`, `Description`, `CategoryId`, `Status`, `Severity`, positive `Weight`, `IsBlocking`, `ObservedState`, `ExpectedState`, linked Finding/Resource/Evidence IDs, structured `Recommendation` and `Validation`, `Frameworks`, `Tags`, and `Metadata`. Check statuses are `Ready`, `Review`, `Blocked`, `NotTested`, `NotApplicable`, and `Unknown`. They are mapped to existing PSI semantic colors for display.

`New-PSIApplicationAssessment -Definition @{...}` accepts assessment identity, type, target, profile, scope, generated time, category and check arrays, linked Finding/Resource/Evidence IDs, provider-supplied recommendations, exceptions, metadata, and `ReadyScoreMinimum`/`ReviewScoreMinimum` thresholds. It calculates `Score`, `Decision`, `OverallStatus`, and `ScoreExplanation`. `Set-PSIApplicationAssessment` attaches the assessment to an Application report and validates its links against the attached intelligence model. `Add-PSIAssessmentOverview` renders a reusable posture workspace.

Exceptions are dictionaries inside the assessment definition with `Id`, `Title`, `Description`, `CheckId`, `FindingId`, `ResourceIds`, `Reason`, `Owner`, `ApprovedBy`, `ApprovedAt`, `ExpiresAt`, `Status`, and `Metadata`. Approved exceptions need an approver and approval time. `ExpiresAt` must follow `ApprovedAt`. Exceptions are displayed as records and do not suppress blockers automatically.

## Calculation and decision

- Check points: Ready 100, Review 50, Blocked 0, NotTested 0, Unknown 0. NotApplicable is excluded from its category's score denominator.
- A category score is the weighted mean of its applicable check points. A category with no applicable checks has no numeric score and is excluded from the overall denominator.
- The overall score is the weighted mean of applicable category scores, using category weights. Both weights are positive numbers supplied by the provider.
- Blocking Review/Blocked checks, any Blocked check, or an in-scope open Critical finding force `NotReady`, regardless of score. `NotTested` yields `Incomplete` if no blocker exists. `Unknown` yields `Unknown` if no higher-priority condition exists. Otherwise thresholds and Review counts produce `Ready`, `ReadyWithReview`, or `ReviewRequired`.
- `ScoreExplanation` exposes category scores, weights, check counts, point rules, reasons, and thresholds. `OverallStatus` maps the decision to PSI health colors; it is not the decision itself.

`NotReady` has higher precedence than a numeric threshold or a documented exception. Provider-supplied scores and decisions cannot override the calculation. Validation `Command` and recommendation `AutomationHint` remain descriptive text.

## Minimal use

```powershell
$check = New-PSIAssessmentCheck -Definition @{
    Id='check-one'; Name='Sample check'; CategoryId='platform'; Status='Review'
    Weight=1; ObservedState='Review needed'; ExpectedState='Ready'
    Recommendation=@{ Action='Inspect the sample observation' }
}
$category = New-PSIAssessmentCategory -Definition @{
    Id='platform'; Name='Platform'; Icon='ResourceServer'; Weight=2
    CheckIds=@('check-one')
}
$assessment = New-PSIApplicationAssessment -Definition @{
    Id='sample'; Name='Sample assessment'; AssessmentType='Readiness'
    Target='Fictional environment'; Profile='Fictional profile'
    Categories=@($category); Checks=@($check)
}
$report = New-PSIReport -Title 'Sample' -Layout Application
$report | Set-PSIApplicationModel -Model (New-PSIApplicationModel) | Out-Null
$report | Set-PSIApplicationAssessment -Assessment $assessment | Out-Null
$report | Add-PSIView -Id overview -Title Overview -Initial |
    Add-PSISection -Title Posture | Add-PSIRow | Add-PSIAssessmentOverview | Out-Null
```

The adaptive demo under `Examples/New-AdaptiveDemoReport.ps1` supplies fictional checks, relationships, evidence, and exceptions. Category cards navigate to the Checks view with category filtering. Check details link to existing Finding, Resource, and Evidence views. Generic explorer filters combine with local search; the workspace remains standalone and offline.

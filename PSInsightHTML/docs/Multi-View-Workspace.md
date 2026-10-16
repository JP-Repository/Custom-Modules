# Multi-view application workspace

Multi-view workspaces are opt-in. Create an Application report, then register
views before adding their sections. Sections added after `Add-PSIView` belong
to that view and remain in the report's flat `Sections` collection for existing
component and evidence contracts.

```powershell
$report = New-PSIReport -Title 'Sample operations' -Theme Auto -Layout Application
$report |
    Add-PSIView -Id overview -Title 'Overview' -Icon NavigationHome -Initial `
        -Commands @(@{ Label = 'Inspect resources'; Icon = 'ResourceServer'; TargetView = 'resources' }) |
    Add-PSISection -Title 'Readiness' |
    Add-PSIRow |
    Add-PSIKPI -Title 'Services' -Value 12 | Out-Null

$report |
    Add-PSIView -Id resources -Title 'Resources' -Icon ResourceServer |
    Add-PSISection -Title 'Inventory' |
    Add-PSIRow |
    Add-PSIExplorer -Id resource-list -Title 'Resources' -Data $records `
        -TitleProperty Name -SubtitleProperty Type -StatusProperty Status `
        -DetailProperties @('Name', 'Type', 'Status', 'Owner') | Out-Null

Export-PSIReport -Report $report -Path './Reports/sample.html'
```

`Add-PSIView` accepts a unique ID, title, subtitle, Fluent icon role, navigation
group, badge, optional initial selection, and optional commands. Each command
has a label, curated icon role, and target view ID. Targets are checked when the
report is exported. A view must contain at least one section. Existing
`-Layout Report` output and Application reports without registered views keep
their previous document navigation.

`Add-PSIExplorer` is a generic object list/detail component for Application
views. Property names select the list title, subtitle, status, and detail fields.
Values and labels are HTML encoded. It supports local search, arrow/Home/End
keyboard selection, a selected detail panel, and an empty state. On narrow
screens the detail follows the list in document order.

The generated HTML contains all view content, CSS, JavaScript, and curated SVG
paths. Only one primary view is presented at a time. Navigation changes the
active view and command title without a reload or anchor jump. The persistent
command bar retains theme and export actions. View commands can navigate to
another registered view. KPI and chart table-filter actions activate the view
containing the target table. URL history and global search are deferred.

Run `Examples/New-AdaptiveDemoReport.ps1` to regenerate the fictional
seven-view reference at `Reports/PSInsightHTML-Adaptive-Demo.html`. The browser
capture aid `Tests/Capture-ApplicationView.py` can inspect a specific view in
local Chrome on macOS; it uses only Python's standard library.

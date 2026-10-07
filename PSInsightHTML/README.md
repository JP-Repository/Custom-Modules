# PSInsightHTML

PSInsightHTML is a PowerShell 5.1-compatible framework for building standalone HTML assessment and inventory reports from PowerShell objects. The report engine is generic; provider-specific data interpretation and assessment rules live under `Providers/`.

The design favors offline delivery, readable Light/Dark/Auto themes, keyboard-accessible investigation controls, and a report object that can be composed before export. Generated HTML embeds its CSS, JavaScript, icons, and chart SVG; it does not load assets from a CDN.

## Install and import

Copy the `PSInsightHTML` directory to a local path. No dependency installation is needed for the generic engine. From that directory:

```powershell
Import-Module ./PSInsightHTML.psd1
Get-Command -Module PSInsightHTML
```

The manifest requires PowerShell 5.1 or later. Pester is needed only to run the tests.

## Quick start

```powershell
$report = New-PSIReport -Title 'Service Health' -Subtitle 'Fictional sample' -Theme Auto
$report | Add-PSISection -Title 'Summary' | Add-PSIRow |
    Add-PSIKPI -Title 'Available services' -Value 12 -Status Healthy | Out-Null

$services = @(
    [pscustomobject]@{ Name = 'Example API'; Status = 'Healthy'; Region = 'West' }
    [pscustomobject]@{ Name = 'Example queue'; Status = 'Warning'; Region = 'East' }
)
$report | Add-PSIRow | Add-PSITable -Title 'Services' -Data $services `
    -Columns @('Name', 'Status', 'Region') | Out-Null

Export-PSIReport -Report $report -Path ./Reports/Service-Health.html
```

The object model is `Report → Sections → Rows → Components`. `Add-PSISection` adds a section; `Add-PSIRow` adds a row to the latest section; component commands add to that row. These commands return the same report object for pipeline composition. `Export-PSIReport` writes the HTML when the report is complete.

## Assessment reports

An assessment has its own sections and structured findings. Add completed assessments to a report, then add a report overview:

```powershell
$report = New-PSIReport -Title 'Assessment Portfolio' -Theme Auto
$assessment = New-PSIAssessment -Id 'sample-service' -Name 'Sample Service' -Provider 'Example'
$evidence = @([pscustomobject]@{ Name = 'Example queue'; Status = 'Warning' })
$assessment | Add-PSISection -Title 'Evidence' | Add-PSIRow |
    Add-PSITable -Id 'sample-evidence' -Title 'Checks' -Data $evidence | Out-Null
$finding = New-PSIFinding -Title 'Review queue' -Status Warning `
    -EvidenceTableId 'sample-evidence' `
    -EvidenceFilter @{ Property = 'Status'; Operator = 'Equals'; Value = 'Warning' }
$assessment | Add-PSIFinding -Finding $finding | Out-Null
$report | Add-PSIAssessment -Assessment $assessment | Add-PSIReportOverview -IncludeTopFindings | Out-Null
Export-PSIReport -Report $report -Path ./Reports/Assessment-Portfolio.html
```

Findings carry severity, description, optional recommendation, and references to evidence in an existing table. Evidence actions open the shared viewer; the underlying table records are not copied into each finding. Assessment navigation follows assessment metadata and highlights the current group while scrolling.

## Reporting capabilities

- KPI, status, alert, recommendation, insight, text, key-value, table, and inline SVG chart components.
- Tables with search, select/multiselect filters, sorting, pagination, status badges, and CSV/XLSX/print actions. Export uses the current filtered result where supported.
- Bar, line, doughnut, and pie charts. Supported chart points can filter a related table.
- Declarative cell or row formatting via `New-PSICondition`, with status-based theme tokens. Conditions affect presentation; assessment rules belong to providers.
- Light, Dark, and Auto themes with a header switch. Print rules remove interaction-only controls and preserve readable status labels.
- Generic evidence drill-down, filtering, and export in a reusable dialog.

The public command list is available with `Get-Command -Module PSInsightHTML`; use `Get-Help <command> -Full` for command-specific usage.

## Providers and examples

`Providers/` contains integrated report commands and their private sample-data preparation. The current Active Directory examples use fictional data and require an explicit `-UseSampleData` switch, except User Inventory, which also accepts a supplied workbook. Importing the generic module does not collect live infrastructure data. See [provider architecture](docs/ProviderArchitecture.md) and [framework architecture](docs/Architecture.md).

Run the generic visual example or the composed assessment example from the project directory:

```powershell
./Examples/New-DemoReport.ps1 -NoBrowser
./Examples/New-ComposedADAssessmentDemo.ps1 -NoBrowser
```

The scripts under `Examples/ActiveDirectory/` demonstrate individual provider reports. HTML output goes to `Reports/` and is ignored by Git. `Examples/Data/` holds local sample data; the supplied workbook is excluded from Git. User Inventory's sample example and workbook-dependent tests require that workbook to be supplied locally in a fresh checkout.

## Tests

Install a PowerShell 5.1-compatible Pester version in your development environment, then run:

```powershell
Invoke-Pester -Path ./Tests
```

See [known limitations](docs/Known-Limitations.md), [roadmap](docs/Roadmap.md), and [changelog](CHANGELOG.md) for release scope and future work.

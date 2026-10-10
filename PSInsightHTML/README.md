# PSInsightHTML

Enterprise PowerShell HTML assessment and reporting framework.

Version 0.9.1 builds standalone reports from PowerShell objects. The generic engine renders supplied data; provider-specific interpretation lives under `Providers/`.

## Features

- Standalone HTML with embedded CSS, JavaScript, icons, and SVG charts; no CDN required.
- Light, Dark, and Auto themes, responsive layout, sticky assessment navigation, and print support.
- KPI cards, key/value panels, status indicators, alerts, text, insights, and recommendations.
- Tables with search, sorting, select/multiselect filters, pagination, CSV/XLSX export, and print actions.
- Conditional cell and row formatting; Bar, Line, Doughnut, and Pie charts.
- Structured findings, evidence drill-down, assessment composition, and a derived report overview.
- Six Active Directory sample providers and a PowerShell 5.1 compatibility target.

## Requirements

**Declared compatibility:** the manifest specifies PowerShell 5.1 as the minimum, targeting Windows PowerShell 5.1 and later PowerShell runtimes. The generic engine requires no external PowerShell modules.

**Runtime validation:** executable PowerShell source and embedded runtime assets are kept ASCII-safe so Windows PowerShell 5.1 does not depend on UTF-8-without-BOM decoding for Unicode punctuation. Native Windows PowerShell 5.1 validation must still be performed on Windows. See [release validation](docs/Release-Validation.md) for parser, import, command-surface, sample-generation, and Pester commands, and [known limitations](docs/Known-Limitations.md) for workbook and browser-validation constraints.

## Installation and import

Keep the complete module directory from this repository:

```text
Custom-Modules/
    PSInsightHTML/
        PSInsightHTML.psd1
        PSInsightHTML.psm1
        ...
```

From `Custom-Modules`, import directly:

```powershell
Import-Module ./PSInsightHTML/PSInsightHTML.psd1 -Force
```

Or, when already inside `PSInsightHTML`:

```powershell
Import-Module ./PSInsightHTML.psd1 -Force
```

Verify the loaded module and discover its commands:

```powershell
Get-Module PSInsightHTML
Get-Command -Module PSInsightHTML
Get-Help Add-PSITable -Full
```

The examples below assume the module is imported and the current directory is `Custom-Modules`. Installation uses this repository; no PowerShell Gallery package is assumed.

## Quick start

```powershell
$Report = New-PSIReport -Title 'Infrastructure snapshot' -Theme Auto
$Servers = @(
    [pscustomobject]@{ Name = 'server01.example.invalid'; Status = 'Healthy'; FreeGB = 80 }
    [pscustomobject]@{ Name = 'server02.example.invalid'; Status = 'Warning'; FreeGB = 12 }
)
$Report | Add-PSISection -Title 'Servers' | Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Servers' -Value $Servers.Count -Status Neutral -Span 3 | Out-Null
$Report | Add-PSIRow | Add-PSITable -Title 'Inventory' -Data $Servers |
    Out-Null
$Output = Export-PSIReport -Report $Report -Path ./Reports/Infrastructure.html
$Output.FullName
```

Open the resulting HTML in a browser. `Export-PSIReport` creates missing output directories and returns a `FileInfo`; it does not open a browser automatically. See the [Getting Started tutorial](docs/Getting-Started.md) for a complete investigation workflow.

## Core concepts and layout

```text
Report
  Sections
    Rows
      Components
```

A component is a display item, such as a KPI card or table. Create the report, add a section, add a row, then add components. `Add-PSIRow` targets the latest section; component commands target the latest row. These commands mutate and return the same report (or assessment), so pipeline chains build one object. `Out-Null` suppresses that returned object. Export is the HTML-writing step and takes an explicit `-Report` argument.

Rows accept `-Columns` from 1 through 12 (default 12). The browser uses a 12-track grid; `Columns` supplies the span for components such as text, status, alerts, recommendations, findings, and charts. It does not replace the grid with a different number of tracks. KPI, key/value, and table components accept `-Span` from 1 through 12, defaulting to 3, 6, and 12 respectively. On a 12-column row, two key/value panels with `-Span 6` sit alongside each other. Components wrap when the available tracks are filled, and responsive styles adjust the layout on smaller screens. Insights divide the row's column count among the insights in that row.

## Component examples

These snippets extend `$Report` from Quick start. Each new row goes into its current section:

```powershell
$Report | Add-PSIRow | Add-PSIText -Text 'Fictional infrastructure data.' -Size Small | Out-Null
$Report | Add-PSIRow | Add-PSIKPI -Title 'Review required' -Value 1 -Status Warning -Span 3 | Out-Null
$Report | Add-PSIRow | Add-PSIKeyValue -Title 'Scope' -Span 6 `
    -Data ([ordered]@{ Environment = 'Example'; Source = 'Fictional snapshot' }) | Out-Null
$Report | Add-PSIRow | Add-PSIStatus -Status Warning -Label 'Storage' -Message 'Review low capacity.' | Out-Null
$Report | Add-PSIRow | Add-PSIAlert -Status Warning -Title 'Capacity' `
    -Message 'One server has low free space.' -Action 'Review storage allocation.' | Out-Null
$Report | Add-PSIRow | Add-PSIInsight -Title 'Servers to review' -Value 1 -Status Warning | Out-Null
$Report | Add-PSIRow | Add-PSIRecommendation -Title 'Review capacity' -Status Warning `
    -Description 'Free space is below the sample threshold.' -ActionText 'Plan additional capacity.' | Out-Null
$Counts = @(
    [pscustomobject]@{ Status = 'Healthy'; Count = 1 }
    [pscustomobject]@{ Status = 'Warning'; Count = 1 }
)
$Report | Add-PSIRow | Add-PSIChart -Title 'Server status' -ChartType Bar `
    -Data $Counts -CategoryProperty Status -ValueProperty Count | Out-Null
```

`Add-PSIText` encodes text rather than accepting raw HTML. Charts support `Bar`, `Line`, `Doughnut`, and `Pie`. Status-bearing components accept `Healthy`, `Warning`, `Critical`, `Informational`, `Neutral`, `Unknown`, and `NotChecked`; `Info` is an alias for `Informational`.

## Tables and filters

This example uses `$Servers` and `$Report` from Quick start:

```powershell
$StatusFilter = Add-PSIFilter -Property Status -Label 'Health' `
    -Type MultiSelect -Values @('Healthy', 'Warning')
$Rules = @(
    New-PSICondition -Property FreeGB -Operator LessThan -Value 20 -Status Warning -Scope Cell
)
$Report | Add-PSIRow | Add-PSITable -Id 'server-inventory' -Title 'Server evidence' `
    -Data $Servers -Columns @('Name', 'Status', 'FreeGB') `
    -ColumnLabels @{ FreeGB = 'Free space (GB)' } -Filters @($StatusFilter) `
    -Conditions $Rules -EnableSearch $true -EnableSorting $true `
    -EnablePagination $true -PageSize 10 -EnableExport $true `
    -ExportFormats @('Csv', 'Xlsx', 'Print') `
    -EmptyMessage 'No servers match the selected filters.' -NullValueText '(not supplied)' | Out-Null
```

| Parameter | Purpose |
| --- | --- |
| `Columns` | Property names in display order; inferred from data when omitted. Specify them for predictable empty tables. |
| `ColumnLabels` | Hashtable mapping property names to display headings. |
| `EnableSearch`, `EnableSorting` | Boolean controls, both enabled by default. |
| `Filters` | Definitions returned by `Add-PSIFilter`; its `Type` is `Select` (default) or `MultiSelect`. Filter properties must be visible columns. |
| `EnablePagination`, `PageSize` | Pagination defaults to enabled, 10 rows per page; size accepts 1–500. |
| `EnableExport`, `ExportFormats` | Export defaults to enabled with `Csv`, `Xlsx`, and `Print`. Browser export uses the filtered result, across pages. |
| `ExportColumns` | Optional subset of visible columns; defaults to all displayed columns. |
| `ExportFileName`, `WorksheetName` | Optional output naming for browser exports. |
| `EmptyMessage`, `NullValueText` | Text for no matching records and missing/null values. |
| `Id` | Stable evidence/filter target. Must start with a letter and contain only letters, digits, underscores, or hyphens; unique within the report. Generated if omitted. |

`Add-PSIFilter` creates a definition rather than extending a report. Supply at least one nonempty, unique value; a table allows one filter definition per property.

## Conditional formatting

`New-PSICondition` creates presentation rules passed to `Add-PSITable -Conditions`:

- `Property`: source field to compare.
- `Operator`: `Equals`, `NotEquals`, `GreaterThan`, `GreaterThanOrEqual`, `LessThan`, `LessThanOrEqual`, `Contains`, `Match`, `IsNull`, or `IsNotNull`.
- `Value`: comparison target; required except for `IsNull` and `IsNotNull`. `Match` uses a regular expression.
- `Status`: visual status applied when the rule matches.
- `Scope`: `Cell` (default) colors the named field's cell; `Row` colors the matching record's row.

Rules are evaluated in order: the first matching condition wins for the relevant cell or row. A row rule and a cell rule can both apply. Formatting does not create findings or change summary counts.

```powershell
$Rules = @(
    New-PSICondition -Property FreeGB -Operator LessThan -Value 10 -Status Critical -Scope Row
    New-PSICondition -Property FreeGB -Operator LessThan -Value 20 -Status Warning -Scope Row
)
$Report | Add-PSIRow | Add-PSITable -Title 'Capacity review' -Data $Servers -Conditions $Rules | Out-Null
```

## Findings and evidence

A finding records an interpretation of evidence. After creating `server-inventory` in the table example:

```powershell
$Finding = New-PSIFinding -Title 'Low free space' -Status Warning -Category 'Capacity' `
    -Description 'One fictional server has less than 20 GB free.' `
    -Recommendation 'Review storage allocation.' -EvidenceTableId 'server-inventory' `
    -EvidenceFilter @{ Property = 'FreeGB'; Operator = 'LessThan'; Value = 20 } `
    -EvidenceColumns @('Name', 'FreeGB')
$Report | Add-PSIRow | Add-PSIFinding -Finding $Finding | Out-Null
```

`New-PSIFinding` creates the object; `Add-PSIFinding` adds its card to the current row and registers it for summaries. `Title` and `Status` are required. Optional descriptive fields include `Category`, `Description`, `AffectedObject`, `Impact`, `Recommendation`, `RuleId`, and `Source`.

`EvidenceTableId` references an existing table's `Id`. `EvidenceFilter` is a hashtable with `Property`, `Operator`, and `Value`, or a `Conditions` array of condition hashtables. It may include `Table`, which must match `EvidenceTableId`. Empty filters reference all records. `EvidenceColumns` selects visible source columns for the evidence view; omit it to use the table's visible columns. Evidence references are checked at export; a missing target table produces a warning and omits the evidence action. Records are referenced rather than duplicated into each finding.

Evidence operators are `Equals`, `NotEquals`, `GreaterThanOrEqual`, `LessThan`, `IsEmpty`, `IsNotEmpty`, `Contains`, and `In` (using `Values`). This is a separate contract from table formatting conditions. Multiple evidence conditions narrow the result together. The shared evidence viewer supports search, sorting, pagination, and export.

## Assessments and overview

Build independent assessments, then compose them into one report:

```powershell
$Portfolio = New-PSIReport -Title 'Assessment portfolio' -Theme Auto
$Capacity = New-PSIAssessment -Id 'capacity' -Name 'Capacity' -Provider 'Example'
$Capacity | Add-PSISection -Title 'Capacity checks' | Add-PSIRow |
    Add-PSIText -Text 'Fictional capacity review.' | Out-Null
$CapacityFinding = New-PSIFinding -Title 'Plan capacity review' -Status Informational
$Capacity | Add-PSIFinding -Finding $CapacityFinding | Out-Null
$Availability = New-PSIAssessment -Id 'availability' -Name 'Availability' -Provider 'Example'
$Availability | Add-PSISection -Title 'Availability checks' | Add-PSIRow |
    Add-PSIText -Text 'No structured findings supplied.' | Out-Null
$Portfolio | Add-PSIAssessment -Assessment $Capacity |
    Add-PSIAssessment -Assessment $Availability | Out-Null
Get-PSIFindingSummary -Findings $Portfolio.Findings.ToArray()
Get-PSIAssessmentSummary -Assessment $Capacity
Get-PSIReportSummary -Report $Portfolio
$Portfolio | Add-PSIReportOverview -IncludeTopFindings -MaxFindings 5 | Out-Null
Export-PSIReport -Report $Portfolio -Path ./Reports/Portfolio.html
```

Assessment IDs and table IDs must remain unique when composing. Complete assessments before adding them; their sections and findings are shared with the report, so treat them as immutable afterward. `Provider` is a label and does not trigger collection.

`Get-PSIFindingSummary` counts findings by canonical status. `Get-PSIAssessmentSummary` derives assessment counts and overall status. `Get-PSIReportSummary` derives report counts, finding summary, and assessment summaries. These commands inspect objects without writing HTML. Status comes from structured findings, not table colors; no findings means `Neutral`.

Call `Add-PSIReportOverview` once, after composing the report. It inserts an overview at the beginning, with derived severity totals, assessment navigation cards, and optionally top findings. Export after all content is complete.

## Active Directory providers

| Public command | Current input/workflow |
| --- | --- |
| `New-PSIADUserInventory` | Local sample workbook or supplied workbook; user account inventory and investigation insights. |
| `New-PSIADGroupPolicyAssessment` | Fictional Group Policy objects and links. |
| `New-PSIADGroupAssessment` | Fictional groups and memberships. |
| `New-PSIADReplicationAssessment` | Fictional domain controller replication assessment. |
| `New-PSIADDNSAssessment` | Fictional DNS servers, resolvers, zones, and forwarding. |
| `New-PSIADSitesSubnetsAssessment` | Fictional sites, subnets, and topology. |

All six support `-AsAssessment`, returning structured content without exporting HTML or opening a browser. Without it, they generate a standalone report, return the output file, and attempt to open it unless `-NoBrowser` is supplied. `-Path` controls the output file; omitted paths use the module's `Reports/` directory. All support `-Theme Light`, `Dark`, or `Auto` (provider default: `Auto`). Discover capability metadata with `Get-PSIReportCatalog`.

```powershell
Get-PSIReportCatalog
New-PSIADDNSAssessment -UseSampleData -Path ./Reports/DNS.html -NoBrowser
$DNS = New-PSIADDNSAssessment -UseSampleData -AsAssessment
$Groups = New-PSIADGroupAssessment -UseSampleData -AsAssessment
$ADReport = New-PSIReport -Title 'Sample AD assessments' -Theme Auto
$ADReport | Add-PSIAssessment -Assessment $DNS | Add-PSIAssessment -Assessment $Groups |
    Add-PSIReportOverview -IncludeTopFindings | Out-Null
Export-PSIReport -Report $ADReport -Path ./Reports/AD-Assessments.html
```

The five non-inventory providers require `-UseSampleData`; they do not accept supplied datasets. User Inventory requires either `-UseSampleData` or `-WorkbookPath`, never both. Workbook input must contain the `AD_User_Accounts` worksheet and the source schema consumed by its provider. The sample workbook at `Examples/Data/Active_Directory_Enterprise_User_Inventory_5000.xlsx` is excluded from Git and must be supplied locally before running its sample workflow. None of these providers performs live AD collection; there is no `-Live` parameter. See [provider architecture](docs/ProviderArchitecture.md).

## Themes and navigation

`New-PSIReport -Theme Light`, `-Theme Dark`, and `-Theme Auto` are supported; the generic report default is `Light`. Auto follows the browser/system preference. Standalone HTML includes theme controls and sticky assessment navigation for composed content. Print styling removes interaction controls; report printing is enabled by default and can be disabled with `Export-PSIReport -EnableReportPrint $false`.

## Example scripts

Paths below are relative to the module directory. From `Custom-Modules`, run scripts with a `./PSInsightHTML/` prefix, for example:

```powershell
./PSInsightHTML/Examples/New-DemoReport.ps1 -NoBrowser
./PSInsightHTML/Examples/New-ComposedADAssessmentDemo.ps1 -NoBrowser
```

| Script | Demonstrates |
| --- | --- |
| [New-DemoReport.ps1](Examples/New-DemoReport.ps1) | Generic components, charts, interactive tables, and fictional inventory. |
| [New-ComposedADAssessmentDemo.ps1](Examples/New-ComposedADAssessmentDemo.ps1) | Five AD assessments in one portfolio with findings, evidence, and overview. |
| [New-ADUserInventoryReport.ps1](Examples/New-ADUserInventoryReport.ps1) | Workbook-backed user inventory; requires the local sample workbook or supplied input. |
| [ActiveDirectory/DNS/New-DNSAssessmentReport.ps1](Examples/ActiveDirectory/DNS/New-DNSAssessmentReport.ps1) | DNS sample assessment. |
| [ActiveDirectory/GroupPolicy/New-GPOAssessmentReport.ps1](Examples/ActiveDirectory/GroupPolicy/New-GPOAssessmentReport.ps1) | Group Policy sample assessment. |
| [ActiveDirectory/Groups/New-GroupAssessmentReport.ps1](Examples/ActiveDirectory/Groups/New-GroupAssessmentReport.ps1) | Groups and membership sample assessment. |
| [ActiveDirectory/Replication/New-ReplicationAssessmentReport.ps1](Examples/ActiveDirectory/Replication/New-ReplicationAssessmentReport.ps1) | Replication sample assessment. |
| [ActiveDirectory/SitesSubnets/New-SitesSubnetsAssessmentReport.ps1](Examples/ActiveDirectory/SitesSubnets/New-SitesSubnetsAssessmentReport.ps1) | Sites and subnets sample assessment. |

Example wrappers retain `-OutputPath`; integrated provider commands use `-Path`.

## Sample Reports

These are static generated examples of PSInsightHTML output, curated with synthetic data only:

- [Framework Demo](SampleReports/PSInsightHTML-Demo.html) — core components, charts, tables, evidence drill-down, and interactions.
- [Composed AD Assessment](SampleReports/PSInsightHTML-Composed-AD-Assessment-Demo.html) — a multi-assessment portfolio with navigation, findings, evidence, and themes.
- [DNS Assessment](SampleReports/PSInsightHTML-DNSAssessment.html) — a provider example with KPIs, charts, filters, and tables.

GitHub may display HTML as source or offer a download rather than execute interactive behavior directly. Download an HTML file and open it locally in a browser to use its interactive features; no additional assets are needed. These curated samples are intentionally version-controlled in `SampleReports/`; normal generated output remains in the ignored `Reports/` directory. See the [sample notes](SampleReports/README.md).

## Data handling

PSInsightHTML renders data supplied to it. Review report content before distributing it: infrastructure reports may contain sensitive operational information.

## Known limitations

Large DOM-backed tables increase file size and browser cost. Current reports are snapshots; historical comparisons and live AD collection are future work. Workbook sample prerequisites and native Windows PowerShell validation remain constraints. See [Known Limitations](docs/Known-Limitations.md) for details.

## Tests

Pester is a development dependency. Run from inside the module directory because existing tests use the current directory to locate assets:

```powershell
Set-Location ./PSInsightHTML
Invoke-Pester -Path ./Tests
```

Workbook-dependent tests require the excluded local sample workbook.

## Documentation

- [Getting Started](docs/Getting-Started.md)
- [Architecture](docs/Architecture.md)
- [Provider Architecture](docs/ProviderArchitecture.md)
- [Known Limitations](docs/Known-Limitations.md)
- [Roadmap](docs/Roadmap.md)
- [Changelog](CHANGELOG.md)

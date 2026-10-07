# Getting Started with PSInsightHTML

Build a standalone capacity report from two fictional servers. Run the following blocks in order in one PowerShell session, starting in `Custom-Modules`. No AD connection or provider workbook is needed.

## 1. Import the module

```powershell
Import-Module ./PSInsightHTML/PSInsightHTML.psd1 -Force
Get-Module PSInsightHTML
Get-Command -Module PSInsightHTML
```

If you start inside the module directory, use `Import-Module ./PSInsightHTML.psd1 -Force` instead. Output paths below are relative to your current directory.

## 2. Create the report and data

```powershell
$Report = New-PSIReport -Title 'Capacity snapshot' -Subtitle 'Fictional example' -Theme Auto
$Servers = @(
    [pscustomobject]@{ Name = 'server01.example.invalid'; Status = 'Healthy'; FreeGB = 80 }
    [pscustomobject]@{ Name = 'server02.example.invalid'; Status = 'Warning'; FreeGB = 12 }
)
$ReviewCount = @($Servers | Where-Object { $_.FreeGB -lt 20 }).Count
```

Creating a report only creates an object. HTML is written at export. This example calculates its review count explicitly; formatting rules do not assess data for you.

## 3. Create a section

```powershell
$Report | Add-PSISection -Title 'Server capacity' | Out-Null
```

Sections group related content. Later rows are appended to the most recently added section.

## 4. Create a row

```powershell
$Report | Add-PSIRow -Columns 12 | Out-Null
```

A row holds display components. Component commands add to the latest row and return the same report, allowing pipelines.

## 5. Add KPIs

```powershell
$Report | Add-PSIKPI -Title 'Servers' -Value $Servers.Count -Status Neutral -Span 6 |
    Add-PSIKPI -Title 'Below 20 GB' -Value $ReviewCount -Status Warning -Span 6 | Out-Null
```

Two spans of 6 fill a 12-track row. Status changes appearance; it does not automatically add a structured finding.

## 6. Add a table

```powershell
$StatusFilter = Add-PSIFilter -Property Status -Label 'Health' -Type Select `
    -Values @('Healthy', 'Warning')
$Report | Add-PSIRow | Add-PSITable -Id 'capacity-evidence' -Title 'Server inventory' `
    -Data $Servers -Columns @('Name', 'Status', 'FreeGB') `
    -ColumnLabels @{ FreeGB = 'Free space (GB)' } -Filters @($StatusFilter) `
    -EnableSearch $true -EnableSorting $true -EnablePagination $true -PageSize 10 `
    -EnableExport $true -ExportFormats @('Csv', 'Xlsx', 'Print') `
    -EmptyMessage 'No servers match the filters.' -NullValueText '(not supplied)' | Out-Null
```

The stable table ID lets findings reference these records. Browser search, filters, sorting, pagination, and export are enabled; CSV/XLSX export includes filtered records across pages.

## 7. Add a condition

Normally create conditions before calling `Add-PSITable` and pass them with `-Conditions`. Here, add the rule to the table just created so the tutorial can build it step by step:

```powershell
$Condition = New-PSICondition -Property FreeGB -Operator LessThan -Value 20 `
    -Status Warning -Scope Cell
$Table = $Report.Sections[0].Rows[1].Components[0]
$Table.Properties.Conditions = @($Condition)
```

This uses the report's current object model; there is no separate public command for updating a table. `Cell` styles only `FreeGB`; `Row` styles the record's row. The first matching rule for the relevant cell or row wins. These presentation conditions do not register findings.

## 8. Add a finding with evidence

```powershell
$Finding = New-PSIFinding -Title 'Low free space' -Status Warning -Category 'Capacity' `
    -Description 'One fictional server has less than 20 GB free.' `
    -Impact 'Capacity may need attention.' -Recommendation 'Review storage allocation.' `
    -EvidenceTableId 'capacity-evidence' `
    -EvidenceFilter @{ Property = 'FreeGB'; Operator = 'LessThan'; Value = 20 } `
    -EvidenceColumns @('Name', 'FreeGB')
$Report | Add-PSIRow | Add-PSIFinding -Finding $Finding | Out-Null
Get-PSIReportSummary -Report $Report
```

The finding references the existing evidence table, rather than copying its records. Its evidence action opens matching records in the shared viewer. `EvidenceColumns` selects the displayed source columns. Evidence filters have their own supported operators; see the [README](../README.md#findings-and-evidence).

## 9. Export the report

```powershell
$Output = Export-PSIReport -Report $Report -Path ./Reports/Capacity-Snapshot.html
$Output.FullName
```

Export validates the report and evidence references, creates missing output directories, and returns the generated file. CSS, JavaScript, icons, and charts are embedded in the standalone HTML.

## 10. Open the HTML

Open the printed path in your browser. In Windows PowerShell you can also run:

```powershell
Start-Process -FilePath $Output.FullName
```

Try the theme selector, table search, status filter, column sorting, and export controls. Open the finding's evidence action to inspect the low-capacity server. Review content before sharing reports because supplied infrastructure data may contain sensitive operational information.

For multiple assessment groups and an overview, continue with [Assessments and overview](../README.md#assessments-and-overview). Consult [Known Limitations](Known-Limitations.md) for runtime and dataset constraints.

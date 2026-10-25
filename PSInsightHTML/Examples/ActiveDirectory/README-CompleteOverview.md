# Complete AD Domain Overview

`Invoke-PSIADCompleteOverview` is the exported single entry point for the linked AD report set. It collects **one domain-scoped DC snapshot** and reuses it for Domain Overview, DC Inventory, both DC Readiness targets, Health Evidence, Health, Security, Compliance, DNS, Replication, and Sites/Subnets. It also runs separate scoped read-only queries for GPOs, OUs, Groups, Users, and Computers. One command can create up to **16 standalone HTML reports**, plus `index.html` linking them.

The main Domain Overview includes DC inventory, sites, subnets, roles, replication, DC computer-object placement, GPO link intent, readiness comparison, and coverage. GPO link intent is not an effective-policy result. Individual reports provide the detail. The index lists any report that failed and its error; one failed query does not silently erase the other reports.

## Fictional demonstration

```powershell
Import-Module PSInsightHTML
Get-PSIReportCatalog -Name "*Complete Domain Overview*"
Invoke-PSIADCompleteOverview `
    -UseSampleData -OutputPath ./Reports/ADCompleteOverview-Sample -NoBrowser
```

Open `Reports/ADCompleteOverview-Sample/index.html`. No directory, DNS, CIM, or network query is made.

## Windows live pilot

Copy/install the module to a normal PowerShell module path, start **Windows PowerShell 5.1** on a management host, and verify `ActiveDirectory` and `GroupPolicy` are available. Use an account with the needed read permissions and access to the selected domain and DCs. Full collection requests remote, DNS, security, event, and dependency observations; unavailable permissions or tools are recorded as gaps.

```powershell
Import-Module PSInsightHTML -Force
$run = Invoke-PSIADCompleteOverview `
    -Domain 'ad.example.test' -CollectionProfile Full `
    -MaxObjects 2000 -OutputPath 'C:\Reports\PSInsightHTML' `
    -NoBrowser -PassThru
$run.IndexPath
$run.Results | Select-Object Name,Status,Error
```

The command displays the current collection or report-building step in the PowerShell progress area and prints a `[current/total] ReportName: Generated/Failed` line after each report. Add `-Verbose` to the command to see each requested DC evidence collector, its target, result, and duration, as well as scoped GPO, OU, group, user, and computer inventory queries and returned row counts. For a persistent console log, use `-Verbose 4> collector-verbose.log` (the progress display itself is interactive and is not written to that file). The generated reports' Collection Coverage sections retain collection outcomes and errors for later review.

Open the returned `index.html`. Live runs use a timestamped output folder. `-Only` limits the set when piloting, for example `-Only DomainOverview,DCInventory,DCReadiness2025,GroupPolicy,OUs`. `-CollectionProfile Core` makes fewer remote queries but many Health, Security, DNS, and Compliance checks may become Not Tested; **missing evidence is not healthy**. `-Theme Light`, `Dark`, or `Auto` controls generated reports. No live environment or native Windows PowerShell 5.1 runtime was available during development; those validations must be done on the pilot host.

Protect the output directory: the HTML, JSON/CSV sidecars, hostnames, addresses, account metadata, and errors can contain sensitive operational information. Review before distributing. The report set is a point-in-time observation, not continuous monitoring or a complete effective-policy audit. No AD modification cmdlets are used.

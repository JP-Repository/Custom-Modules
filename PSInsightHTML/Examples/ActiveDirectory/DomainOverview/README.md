# AD Domain Overview

`Invoke-PSIADDomainOverview.ps1` produces a domain-scoped Fluent application report from **one normalized AD snapshot**. It reuses the shared read-only provider, DC inventory model, and Windows Server 2022/2025 DC readiness rules. The generic PSInsightHTML renderer remains independent of Active Directory.

## Try the fictional sample

From the PSInsightHTML module folder:

```powershell
./Examples/ActiveDirectory/DomainOverview/Invoke-PSIADDomainOverview.ps1 `
    -UseSampleData `
    -OutputPath ./Reports/DomainOverview-Sample `
    -NoBrowser
```

Open `Reports/DomainOverview-Sample/ADDomainOverview.html`. No AD module, network access, or directory query is needed for the sample. Omit `-NoBrowser` to attempt opening the report after generation.

## Run on a selected domain

Run from a non-production pilot Windows host with the ActiveDirectory PowerShell module, suitable directory read permissions, and access to the selected domain:

```powershell
./Examples/ActiveDirectory/DomainOverview/Invoke-PSIADDomainOverview.ps1 `
    -Domain 'ad.example.test' `
    -CollectionProfile Core `
    -TargetOS 2025 `
    -OutputPath 'C:\Reports\PSInsightHTML' `
    -NoBrowser
```

`-Domain` is required for live collection; the script never silently selects the current domain. Collection is read-only. It writes an `ADDomainOverview.html` file to a timestamped subfolder of `-OutputPath`, so a new live run does not replace an earlier one. Review the output before sharing: hostnames, addresses, roles, and collection details can be sensitive. Keep live reports outside public repositories.

`Core` is the default collection profile. `Operational`, `Health`, `Security`, `Dependencies`, and `Full` request additional observations and may need remote permissions or tools. Failed or unavailable collectors appear in coverage; missing evidence is not treated as healthy. `-TargetOS 2022` changes which target's checks appear in detail, while the comparison still evaluates both targets from the same snapshot. `-Theme Light`, `Dark`, or `Auto` controls the initial theme.

## Reuse a normalized snapshot

Pass `-Snapshot` with the normalized object returned by `ConvertTo-PSIADDCReadinessModel`; this skips collection. `-PassThru` returns the snapshot, inventory, both readiness results, report object, and HTML path for further inspection. `-CommandAdapter` is available for mock-based provider validation, not needed for normal sample runs.

## Report scope and limits

The report contains an overview, controller register, topology observations, DC computer-object placement, GPO link intent, target-specific DC readiness comparison, and collection coverage. GPO link intent does not establish effective policy. It is a snapshot, not continuous monitoring or an overall AD health verdict. It does not change AD. It uses a reviewed subset of source fields in its tables and emits one self-contained HTML file. The 2022/2025 readiness decisions depend on the available evidence and must be reviewed before acting on them.

For one command that also generates dedicated GPO, OU and other inventories, use [Complete AD Domain Overview](../README-CompleteOverview.md). This script remains an example entry point, not a new exported module command or menu item. Native Windows PowerShell 5.1 and a real AD environment still require pilot validation before production use.

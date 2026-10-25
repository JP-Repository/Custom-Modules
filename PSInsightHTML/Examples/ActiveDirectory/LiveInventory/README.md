# Read-only AD inventory examples

`Invoke-PSIADInventoryReport.ps1` is a shared example runner for eight scoped inventories. The adjacent `Invoke-PSIAD*.ps1` scripts are short entry points for Groups, GroupPolicy, Users, Computers, OUs, DNS, Replication, and SitesSubnets. All generate standalone Fluent HTML and use the generic PSInsightHTML table, chart, filter, search, sort, pagination, and export components.

| Report type | Source | Meaning |
| --- | --- | --- |
| Groups | `Get-ADGroup` | Group metadata; no membership or effective-access conclusion |
| GroupPolicy | `Get-GPO -All` | GPO object metadata; no applied-policy conclusion |
| Users | `Get-ADUser` | Reviewed account fields; dates are observations, not findings |
| Computers | `Get-ADComputer` | Directory computer account fields; no reachability conclusion |
| OUs | `Get-ADOrganizationalUnit` | OU protection and direct `gPLink` count; no effective inheritance conclusion |
| DNS | Shared AD snapshot | DC DNS zones, forwarders, conditional forwarders, and query states |
| Replication | Shared AD snapshot | Partner metadata and reported failures at collection time |
| SitesSubnets | Shared AD snapshot | Sites containing assessed DCs, their mapped subnets, and observed links |

## Sample

From the module folder:

```powershell
./Examples/ActiveDirectory/LiveInventory/Invoke-PSIADInventoryReport.ps1 `
    -ReportType Groups -UseSampleData `
    -OutputPath ./Reports/Groups-Sample -NoBrowser
```

The sample uses only fictional records. The exported module command in [AD Complete Overview](../README-CompleteOverview.md) generates all reports together.

## Live pilot

Run in Windows PowerShell 5.1 on a Windows management host with the ActiveDirectory module. The GroupPolicy report also requires the GroupPolicy module. Specify the domain explicitly:

```powershell
./Examples/ActiveDirectory/LiveInventory/Invoke-PSIADInventoryReport.ps1 `
    -ReportType Users -Domain 'ad.example.test' `
    -MaxObjects 2000 -OutputPath 'C:\Reports\PSInsightHTML' -NoBrowser
```

Direct directory queries request at most `MaxObjects + 1` records where supported, so the report can detect a display limit. `Get-GPO -All` cannot apply this limit server-side; it reads the domain's GPO metadata and limits the displayed records. When a limit is reached, counts and charts describe **displayed records only**. No group membership, GPO application, account security finding, or host health is inferred. LastLogonDate is approximate. Review report contents before sharing; live names and attributes can be sensitive.

DNS defaults to the `Operational` collection profile because `Core` does not request DNS Server configuration. The snapshot-based reports accept a normalized `-Snapshot` to avoid another collection. Failed or unavailable collectors remain visible in Collection Coverage. An injected `-CommandAdapter` supports local tests without AD access. No example writes to AD.

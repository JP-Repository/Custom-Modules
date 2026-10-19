# DC Inventory example

This is a domain-scoped inventory of **what was observed**, not an AD health, security, compliance, or readiness assessment. No thresholds, severities, remediation actions, or scores are applied. Collection states such as `Collected`, `Partial`, `NotRequested`, `NotSupported`, and `Failed` describe evidence completeness, not service health.

The example imports the provider functions from `Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1`, collects once with `Collect-PSIADSnapshot`, normalizes with `ConvertTo-PSIADDCReadinessModel`, then builds the inventory projection and application. The `-Snapshot` parameter accepts an existing normalized snapshot so the report can be built without recollection. The same object can be passed independently to `Test-PSIADDCReadiness -TargetOS 2022` and `-TargetOS 2025`; no projection or assessment mutates it.

```powershell
& ./Examples/ActiveDirectory/DCInventory/Invoke-PSIADDCInventory.ps1 -UseSampleData -NoBrowser
```

For the fictional root/child mocked adapter, import the provider and fixture script, then pass `-Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -CollectionProfile Operational`. The explicit target domain controls the DC inventory; child-domain replication partners appear only as external evidence endpoints. No live AD is queried by either fixture.

Profiles: `Core` uses directory metadata and partner information without remote observations; `Operational` requests remote OS, disk, services, DNS client, shares, time and DNS Server information; `Full` adds the provider's additional supported observations. The fictional sample is a complete fixture and retains its values under every profile; the profile label shows which request was selected, not that fixture values were selectively recollected.

The projection presents domain/forest metadata, DCs, sites/subnets and site links, FSMO/GC, DNS clients and forwarders, time, uptime/storage, services/shares, replication links, resource hierarchy, topology, evidence and collection coverage. Search, command palette, table CSV/XLSX/print export and standalone HTML are supplied by the generic PSI engine. The report-owned `PrintDisplay.Tables` list selects concise inventory tables for the generic print projection.

Current shared-snapshot gaps: CPU observations, installed Windows feature inventory, and an explicit site-link collection state are not available. The existing remote OS and NIC query now projects memory, system-drive identity, addresses and subnet masks where returned; a failed or unrequested remote query leaves them blank. DNS Server `NotSupported` is displayed as unavailable collection, never as a DNS failure. `GlobalCatalog` and `RODC` are directory flags; `DNSRole` is an observed provider hint; none proves Windows feature installation. No new query was added for these fields. Future Health work can reuse this snapshot and add independent rules after the relevant evidence is collected.

Existing DNS, Replication, Sites/Subnets, GPO, Groups and User Inventory providers are not migrated here. Their inventory presentation could later consume the shared DNS, replication and site/subnet snapshot slices, while their assessment rules remain separate.

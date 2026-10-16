# Active Directory DC Readiness (Milestones 11.6–11.7)

This is a provider-owned application for Windows Server 2022 and 2025 domain controller readiness. All names, addresses, measurements, and approvals in the sample are fictional. Sample mode needs no Active Directory or Group Policy module. The PSI core has no AD collection or interpretation logic.

## Run the sample

From the PSInsightHTML module directory:

```powershell
pwsh -NoProfile -File Examples/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1 -TargetOS 2025 -UseSampleData -Theme Auto -NoBrowser
pwsh -NoProfile -File Examples/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1 -TargetOS 2022 -UseSampleData -Theme Light -NoBrowser
```

The default output directory is `Reports/DCReadiness`. `-OutputPath` accepts a local directory. Each run writes a standalone `DCReadiness-<target>.html`, `NormalizedInventory-<target>.json`, `Assessment-<target>.json`, `Checks-<target>.csv`, and `TargetComparison-<target>.json`. Target-specific sidecar names prevent a later run from overwriting the inventory that produced an earlier report. The comparison evaluates both targets from **one normalized snapshot** during that run. `-PassThru` also returns the in-memory result. The HTML embeds its CSS, JavaScript, icons, and data; it needs no network access.

## Architecture and contract

`Collect-PSIADDCReadiness.ps1` selects the fictional fixture or the live, read-only domain collector in `Live/`. `ConvertTo-PSIADDCReadinessModel.ps1` validates forest, domain, site, DC, replication, DNS, time, port, dependency, security, and threshold fields. It preserves typed `CollectedAt` and replication `LastSuccess` dates; an unavailable last success may be null in live mode. `Test-PSIADDCReadiness.ps1` interprets the same normalized inventory for either source, then creates public PSI Resources, Relationships, Evidence, Findings, Categories, Checks, and Assessment objects. The existing PSI posture engine calculates the score and decision. The application script renders the workspace views through public PSI components.

The normalized inventory has `SchemaVersion`, `ContractVersion`, `Source`, `CollectedAt`, `Forest`, `Domains`, `Sites`, `DomainControllers`, `Replication`, `Dependencies`, `Security`, `SecurityValues`, `Ports`, `DNS`, `Time`, `Thresholds`, `CollectionResults`, `CollectionLogs`, and `CollectionCoverage`. Source and target are separate: switching `-TargetOS` does not recollect or reshape source observations. Model links are validated by PSI contracts. Rule metadata on every Check includes rule ID, version, target, source URL, last-reviewed date, category, and rationale.

## Versioned rules and provenance

`Rules/WindowsServer2022.psd1` and `Rules/WindowsServer2025.psd1` define target-specific compatibility and health rules. `Rules/SecurityBaseline.psd1` defines provider security review topics and recommended GPO settings. `Rules/RuleSources.psd1` contains named source references and review dates. The provider labels its **own** disk (<10 GB free), replication latency (120 minutes in this sample), and posture score thresholds; these are not stated as universal Microsoft requirements.

Microsoft's [AD DS functional-level matrix](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/active-directory-functional-levels) allows a Server 2022 DC at Server 2012 R2 or 2016 functional levels, while a Server 2025 DC needs at least Server 2016 levels in an existing domain. The 2022 rule does **not** impose a 2016 minimum. The provider treats levels outside the explicit 2022 matrix as Review, except a 2025 functional level, which blocks a 2022 DC. [Microsoft's Exchange matrix](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/supportability-matrix?view=exchserver-se) introduces Server 2022 AD server support in Exchange 2019 CU12 and 2016 CU23, and Server 2025 AD server support in Exchange 2019 CU14; Exchange 2016 does not support Server 2025 AD servers. Exchange SE supports both. Missing CU or low-confidence detection remains Review. Exchange 2016/2019 [ended support in October 2025](https://learn.microsoft.com/en-us/troubleshoot/exchange/administration/exchange-2019-2016-end-of-support); compatibility alone therefore does not close a lifecycle review. If a Server 2025 DC holds Schema Master before Exchange PrepareAD, the [November 2025 or later Windows cumulative update requirement](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/supportability-matrix?view=exchserver-se) needs checking. The sample Schema Master is a Server 2016 DC, so this remains contextual guidance.

Material current replication failure blocks; a recovered historical RPC event is Review. FRS SYSVOL, absent DFSR migration, or missing active SYSVOL/NETLOGON shares block. DNS self-reference alone does not fail; reachability, redundancy, zone health, and forwarders are reviewed together. Port observations distinguish required paths, role/topology expectations, and untested paths. Services are one signal, not proof of complete DC health. Post-build checks remain Not Tested until an actual new DC exists.

The sample includes eight mixed Server 2016/2019 DCs across four sites, one forest/domain, five FSMO role assignments, seven GC DCs, a maintenance DC that is unreachable, a pending reboot, a recovered replication error, DNS resolver and forwarder concerns, one local-clock source, one DC with 8 GB free, Exchange 2019 CU13, security gaps, a Not Tested NPS dependency, and one approved exception. The inventory rule also checks Microsoft's [Windows Server lifecycle dates](https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info), using the fictional organization's configurable 120-day review window for Server 2016's January 2027 extended-support end. From this same snapshot, 2022 is **Incomplete** and 2025 is **Not Ready**. The 2025 Exchange incompatibility is blocking. The approved exception never overrides a blocker. The score includes Not Tested checks at zero according to the existing generic PSI posture contract; the report explains the score and keeps the verdict prominent.

## Security, GPO, dependencies, and validation

Security topics include LDAP signing and channel binding, SMB signing, NTLM, Kerberos/RC4, TLS, audit policy, firewall, RDP/admin access, endpoint protection, PowerShell logging, event retention, time, privileged access, local options, and user rights. Rule sources can point to Microsoft guidance or a named organization policy; they do not imply blanket NIST/CIS/STIG certification. The GPO Build Standard is a **recommendation table** with setting, recommended and observed values, status, suggested generic GPO name/scope, conflict state, source, rationale, remediation, impact, and validation. It creates no GPO. Dependency records represent Exchange, Entra Connect, AD FS, PKI, LDAP applications, fixed DC targets, NPS, backup, and monitoring. Unverified applications are not marked Ready. Post-build definitions cover promotion, DNS registration, shares, replication, GC, site, time, DNS clients, logs, authentication, and backup/monitoring onboarding.

The recommended modernization sequence is to build a new server, join the domain, promote it, validate it, transition roles/services, then demote a legacy DC. This is guidance; the provider executes none of these steps.

## Live read-only collection

**This assessment performs read-only collection only.** It does not change AD, DNS, Group Policy, services, registry, DC roles, or remote systems. `-WhatIf` is not provided because the collector has no write operation. Do not execute a live run without an approved local pilot and appropriate read permissions.

Run on a Windows host with Windows PowerShell 5.1 or later, the **ActiveDirectory** module, and network access to the selected domain. Omit `-Domain` to resolve the current AD domain; provide `-Domain` to pin scope. The collector calls `Get-ADDomainController -Filter * -Server <resolved domain>` and discards DCs whose `Domain` differs. It never enumerates forest domains. Forest configuration queries are limited to metadata and, only with `-IncludeDependencyDiscovery`, directory dependency objects. DC sites, subnets, and site links are retained only for in-scope DC sites.

```powershell
powershell.exe -NoProfile -File Examples/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1 `
  -TargetOS 2025 -Domain child.example.com `
  -OutputPath C:\Temp\Reports\DCReadiness -NoBrowser
```

The command uses a timestamped run folder under `-OutputPath`; the Windows default is `C:\Temp\Reports\DCReadiness`, and a portable module-local output path is used elsewhere. A live run writes `DCReadiness-<target>.html`, `NormalizedData.json`, `Assessment.json`, `Checks.csv`, `CollectionCoverage.json`, `CollectionCoverage.csv`, `TargetComparison-<target>.json`, and `Logs/DCReadiness.log`. The log is structured JSON despite its `.log` extension. The HTML is standalone and embeds all CSS, JS, icons, and report data. Technical error messages are kept in JSON; the HTML shows error types and collection status.

Default collection queries domain/forest metadata, DC inventory, in-scope topology, replication partners, and replication failures. Optional switches are independent:

| Switch | Read-only evidence |
| --- | --- |
| `-IncludeRemoteChecks` | CIM OS, local disk, service state, DNS client settings, shares; `w32tm /query /source`; DNS Server forwarder/zone inventory when its module is available |
| `-IncludePortChecks` | Sequential collector-host-to-DC **TCP** checks for 53, 88, 135, 389, 445, 464, 636, 3268, 3269, 5722 with a 750 ms connect wait |
| `-IncludeSecurityChecks` | Selected read-only remote registry DWORD values for LDAP signing, LDAP channel binding, NTLM compatibility, SMB signing; other effective-policy topics remain Not Tested |
| `-IncludeDependencyDiscovery` | AD configuration discovery for Exchange server objects and Enterprise CA directory objects; exact Exchange CU remains unknown unless independently verified |

Port 123 is UDP and is not tested by the TCP probe. Dynamic RPC is not a fixed port. A successful TCP connection proves neither authentication nor DNS/AD functional health. Remote CIM access and DNS Server tools may be blocked or unavailable; those failures are recorded, not interpreted as DC failure. Absent registry values mean **Not Configured**, not automatically insecure. Registry observations are not equivalent to effective GPO state. Optional security checks remain Not Tested in the readiness rule pack until validated effective-state logic exists. The GPO Build Standard is recommendation-only.

## Coverage and failure semantics

Every collector result has `CollectorId`, `Name`, `Category`, `Scope`, `Status`, start/end time, duration, requested/succeeded flags, expected/collected counts, coverage percent, error code/message, and notes. Statuses are `Collected`, `Partial`, `Failed`, `NotSupported`, `NotRequested`, and `NotTested`. A successful replication failure query returning zero records is distinct from a failed query. Per-DC query failures do not stop other DCs. Missing mandatory domain resolution, AD module, or domain-scoped DC inventory stops collection.

The **Collection Coverage** view and Overview show evidence coverage separately from readiness score and decision. Coverage is completed requested observations divided by expected requested observations; optional collectors left off are shown as Not Requested but excluded from that denominator. Known unimplemented evidence sources, such as DFSR migration state, resolver reachability, forwarder reachability, zone health, PDC source reachability, reboot state, and provider-supplied application dependency inventory, are explicitly **Not Tested** and lower coverage. The sample fixture is labeled fictional and reports fixture collection coverage; it is not a live confidence claim.

The rule evaluator requires its supporting collector statuses before interpreting evidence. For example, failed DNS collection never produces a Healthy forwarder check; missing disk data never becomes zero free space; failed replication queries never become no failures. Rules without complete evidence return Not Tested with a reason. Readiness score remains the existing PSI assessment score and does not use the coverage percentage as a multiplier or verdict override.

## Known limits and pilot sequence

This release does not run dcdiag/repadmin, all-to-all probes, UDP DNS/NTP probes, DFSR migration-state reads, reliable DNS zone health checks, effective GPO/RSoP, reboot detection, forwarder reachability, or full Exchange CU mapping. AD FS, Entra Connect, hard-coded LDAP/DC references, application dependencies, backup, monitoring, and load-balancer paths require owner input. Enterprise CA discovery observes directory objects only and cannot establish CA service health. No automatic forest-wide assessment is implemented. Live collection has only mocked automated validation so far; it has **not** been run against production AD.

Pilot in this order: run sample mode, run the fictional mocked adapter validation, run a basic AD-only live collection in a permitted test domain, review scope and Collection Coverage, enable remote checks, then enable security or network checks separately. Compare the sidecars and report before considering scheduled use. Exact Exchange builds, supported OS matrices, and local thresholds require human review before change decisions.

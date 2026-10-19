# Active Directory Health evidence foundation (11.14)

This provider layer organizes observations for future rules. It produces **no Health verdict, score, finding, threshold or check**. `New-PSIADHealthEvidenceModel -Snapshot $Snapshot` consumes the same normalized snapshot as DC Inventory and both DC Readiness versions. It never recollects or changes that snapshot. The function is provider-private; the generic PSInsightHTML module remains technology-neutral.

## Collection and projection

`Collect-PSIADSnapshot -Profile Core` keeps remote work off. `Operational` enables existing remote OS, disk, service, share, time and DNS observations. `Health` includes Operational and explicitly adds per-DC CPU (`Win32_Processor`), Windows feature inventory (`Win32_ServerFeature`), and bounded event queries (`Get-WinEvent`, up to 100 records per log in a configurable 1–168 hour window, default 72). `Full` includes Health. `-IncludeHealthEvidence` adds those queries to another profile. These are read-only queries and remain optional. The event logs queried are Directory Service, DFS Replication, DNS Server and System; a missing log can be a partial query, rather than a zero-event conclusion. The collector uses neither local ServerManager nor a second Health collector.

`-BackupInput` accepts explicit provider records with an in-scope `DC`, typed `LastSuccessfulSystemStateBackup` (`[datetime]` or `$null`), named `Source`, optional typed `EvidenceTimestamp`, `Confidence` (`High`, `Medium`, `Low`), and `CollectionState`. It does not discover a backup product. Without input, per-DC backup evidence is `NotRequested`. Provider input is identified as such, and its confidence is retained.

Every observation has `Type`, `DC` (or domain scope), `Domain`, `Collector`, `Timestamp`, `CollectionState`, `CollectionMethod`, `Confidence`, `ErrorClass`, `EmptyResult`, and `Value`. `Value` is a typed object, scalar or array appropriate to the evidence type. The state vocabulary is `Collected`, `Partial`, `Failed`, `NotSupported`, `NotRequested`, `NotTested`. A successful empty query keeps `Collected` and sets `EmptyResult`; a failure or unsupported query keeps its own state. Error classes use structured exception and error-category data where available: `AccessDenied`, `HostUnreachable`, `CommandUnavailable`, `RpcUnavailable`, `WinRMUnavailable`, `Timeout`, `Unsupported`, `Unknown`. Sample observations identify fictional provenance; a direct successful live query is high confidence, partial evidence is low confidence, and unavailable evidence has no confidence. Provider-input confidence is explicit, never inferred from a backup date.

The normalized snapshot retains site-link query state separately from site-link rows, per-DC CPU, total/free/used memory, system disk total/free/percent, service detail, feature inventory, DNS zones and per-query DNS states, replication metadata and failure records, event summaries and per-log query states, and backup input. The projected observations distinguish DFSR service, SYSVOL share, NETLOGON share, and DFSR migration state. Time source, PDC role, source reachability and unmeasured offset remain separate facts. TCP 135 is only a TCP probe and never proof of the dynamic RPC range.

Event observations include DC, log, provider, event ID, level, timestamp, summary (truncated to 240 characters), category and query window. Full XML and full message payloads are not captured by this default model. Categories are metadata only; they do not imply severity. The validation report at `Examples/ActiveDirectory/HealthEvidence/Invoke-PSIADHealthEvidence.ps1` uses PSI application views and tables. It labels itself **Evidence Foundation — No Health Verdict**. Its fictional sample can be generated without an AD environment.

## Evidence support matrix

| Evidence | Current support | Boundary |
| --- | --- | --- |
| DC identity, site and domain | Collected from directory | Directory presence is not proof of remote reachability |
| Remote reachability / query state | Partial | Successful CIM query proves that query path; other paths may differ |
| AD DS, Netlogon, DFSR, DNS, KDC, W32Time services | Optional CIM | State and start mode where returned; no service health rule |
| SYSVOL and NETLOGON shares | Optional CIM | Share presence distinct from DFSR state |
| DFSR migration state | Fictional fixture only / live NotTested | No live migration query yet |
| DFSR replicated-folder state | NotTested | No safe source implemented |
| Replication partners, failures and last success | Directory query | Inbound metadata and separate failure query states; no outbound completeness claim |
| DNS client resolvers, forwarders, zones | Optional CIM / DnsServer | Per-query DNS states; zone health itself NotTested |
| Resolver / forwarder reachability | Fictional fixture only / live NotTested | No independent probe yet |
| Time source | Optional `w32tm` | Offset and source type NotTested; PDC identity separate |
| PDC source reachability | Fictional fixture only / live NotTested | No independent NTP probe yet |
| CPU, memory, disk, uptime | Optional CIM | Observed facts only; no thresholds |
| Installed Windows roles/features | Optional `Win32_ServerFeature` | NotSupported if unavailable; feature distinct from service |
| Sites, subnets, site links | Directory query | Site-link state retained even when result is empty |
| Backup recency | Provider input only | No automatic product discovery or freshness rule |
| Event summaries | Optional bounded event-log query | Four logs, up to 100 per log; partial query states retained |
| Pending reboot | Fictional fixture / live NotTested | No remote-registry dependency imposed |
| TCP connectivity | Optional TCP connect | No dynamic RPC range inference |
| Dependency discovery | Optional directory objects / provider input | Does not prove application health |

For fictional sample coverage, `HealthCollectionResults` demonstrates collected, partial, failed, unsupported and not-requested states. The Health projection uses the existing `Get-PSIADCollectionCoverage` engine on this illustrative subset; the readiness snapshot's established 100% fictional fixture coverage remains unchanged. Live Health coverage uses the normal full `CollectionResults`. Neither percentage is a health score.

## Remaining work boundary

Future Health rules may consume these records and define reviewed thresholds. They must distinguish query gaps from successful empty results and may need additional read-only collectors for DFSR migration/folder state, independent DNS and time probes, reliable pending reboot detection, and backup product integrations. This milestone deliberately stops before that rule layer.

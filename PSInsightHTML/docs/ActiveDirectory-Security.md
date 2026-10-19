# Active Directory Security assessment (11.16)

Milestone 11.17 expands the shared provider's typed, attributable Security evidence without changing the 29-rule pack or its severities. See [Security evidence sources and limits](ActiveDirectory-SecurityEvidence.md) for the collection contract, support matrix, confidence model, and unresolved gaps.

This provider-owned assessment interprets the **same normalized snapshot** used by DC Inventory, Readiness 2022/2025 and Health. It performs no collection or remediation. Security asks whether observed directory configuration reduces identity, authentication and directory attack risk. Health covers current operational condition; Readiness covers target-version change risk; Inventory is factual. This is not a compliance certification or a complete Microsoft Security Baseline assessment.

## Contract, score and verdict

`Providers/ActiveDirectory/Rules/Security/SecurityRules.psd1` defines 29 versioned rules across Authentication, Kerberos, NTLM, LDAP, SMB, TLS / Schannel, Privileged Access, DC Hardening, Audit / Logging, Protocol Exposure, Credential Protection and Identity Configuration. Every rule declares ID, title, category, scope/applicability, evidence type, secure/review/critical values or threshold, weight, non-destructive recommendation, validation, source and version. The evaluator maps Secure → Ready, Review → Review, Critical → Blocked, unavailable → NotTested and out-of-scope DNS-only checks → NotApplicable in the existing assessment engine. Generic weighted scoring is unchanged. Any Blocked check or open critical finding overrides a high score. Generic decision maps to Secure, Review, Critical or Incomplete.

`Thresholds.psd1` holds provider-defined defaults and `Test-PSIADSecurity -ThresholdOverrides @{ ... }` accepts known positive numeric keys. These values are **review parameters, not an organizational baseline**: privileged inactivity 90 days, privileged password age 365 days, KRBTGT password age 365 days and Security event-log capacity 1024 MB. The first two are reserved for future richer account observations; no account age is inferred from the current shared snapshot. Score boundaries are 90/75. Rules use explicit observations and do not infer full control coverage from a selected registry value.

Security evidence availability is the fraction of Security rule observations with a collected, attributable fact. The shared snapshot's collector coverage is displayed separately. Neither coverage metric is a Security score. `New-PSIADSecurityEvidenceModel` retains per-DC selected registry values already read by the shared Security collector. The older aggregate `SecurityValues` strings cannot safely identify which DC supplied a value, so the assessment does not use them as effective policy. A partial registry value can flag a weak indicator for **Review**; a favorable registry value remains **NotTested** until effective policy is known. A failed, unsupported, unrequested, untested or insufficient partial observation remains NotTested. Missing evidence never becomes Secure.

## Rule matrix

`PDR` means **provider-defined security recommendation**. No rule has a verified CIS, STIG or NIST mapping. `NT` means NotTested for absent/insufficient evidence; `NA` means NotApplicable when a role exclusion is explicit. Values in the Secure/Review/Critical columns are classifications of the required evidence type, not claims about uncollected controls.

| Rule ID | Category | Required evidence | Secure | Review | Critical | Missing | Source | Configurable parameter | Framework mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `auth-policy` | Authentication | Effective policy | Approved | Deviation | — | NT | PDR | none | none |
| `ldap-signing` | LDAP | Effective policy | Required | Negotiated, AuditOnly | Disabled | NT | PDR | none | none |
| `ldap-channel-binding` | LDAP | Effective policy | Required | WhenSupported | Disabled | NT | PDR | none | none |
| `ldaps-capability` | LDAP | Certificate inspection | Valid | Expiring | Invalid | NT | PDR | none | none |
| `ldaps-usage` | LDAP | Completed traffic telemetry | Observed | — | — | NT | PDR | none | none |
| `ntlm-policy` | NTLM | Effective policy | NtlmV2Only | LegacyAllowed | LmAllowed | NT | PDR | none | none |
| `ntlmv1-usage` | NTLM | Completed traffic telemetry | NotObserved | — | Observed | NT | PDR | none | none |
| `kerberos-aes` | Kerberos | Effective policy | Supported | Partial | Unsupported | NT | PDR | none | none |
| `rc4-policy` | Kerberos | Effective policy | Disallowed | Permitted, DependencyRequired | — | NT | PDR | none | none |
| `rc4-usage` | Kerberos | Completed traffic telemetry | NotObserved | Observed | — | NT | PDR | none | none |
| `smb-signing` | SMB | Effective policy | Required | EnabledNotRequired | Disabled | NT | PDR | none | none |
| `tls10` | TLS / Schannel | Effective configuration | Disabled | Enabled | — | NT | PDR | none | none |
| `tls11` | TLS / Schannel | Effective configuration | Disabled | Enabled | — | NT | PDR | none | none |
| `tls12` | TLS / Schannel | Effective configuration | Enabled | Unknown | Disabled | NT | PDR | none | none |
| `privileged-members` | Privileged Access | Reviewed membership | Approved | Unexpected | — | NT | PDR | approved register | none |
| `privileged-hygiene` | Privileged Access | Reviewed account inventory | Current | Inactive, PasswordNeverExpires, StalePassword | — | NT | PDR | organization review | none |
| `krbtgt-age` | Identity Configuration | Account metadata | Below review age | At/above review age | — | NT | PDR | `KrbtgtPasswordAgeReviewDays` | none |
| `dc-options` | DC Hardening | Effective policy | Expected | Deviation | — | NT | PDR | approved policy | none |
| `audit-policy` | Audit / Logging | Effective audit policy | Complete | Partial | Disabled | NT | PDR | approved categories | none |
| `event-retention` | Audit / Logging | Event-log configuration | At/above size | Below size | — | NT | PDR | `EventRetentionReviewMB` | none |
| `powershell-logging` | Audit / Logging | Effective policy | Enabled | Partial | Disabled | NT | PDR | approved logging design | none |
| `firewall` | DC Hardening | Effective configuration | Enabled | Partial | Disabled | NT | PDR | none | none |
| `defender` | DC Hardening | Product health | Healthy | Degraded | Disabled | NT | PDR | none | none |
| `credential-guard` | Credential Protection | Effective configuration | Enabled | Disabled | — | NT | PDR | platform applicability | none |
| `lsass-protection` | Credential Protection | Effective configuration | Enabled | Disabled | — | NT | PDR | dependency review | none |
| `wdigest` | Credential Protection | Effective configuration | Disabled | — | Enabled | NT | PDR | none | none |
| `rdp` | Protocol Exposure | Effective policy | Restricted | Broad | — | NT | PDR | approved access path | none |
| `smbv1` | Protocol Exposure | Effective configuration | Disabled | — | Enabled | NT | PDR | dependency review | none |
| `dns-zone-transfer` | Protocol Exposure | Effective DNS configuration | Restricted | Broad | Unrestricted | NT; NA on non-DNS DC | PDR | approved secondary list | none |

The selected registry DWORDs currently available for live DCs are LDAP signing, LDAP channel binding, LAN Manager authentication level and SMB server signing. Their interpretation follows the relevant Microsoft documentation, but the **assessment recommendation and severity are provider-defined**. Registry state alone does not prove effective GPO, active traffic or client compatibility. Microsoft references for the setting semantics: [LDAP signing](https://learn.microsoft.com/en-us/troubleshoot/windows-server/identity/enable-ldap-signing-in-windows-server), [LDAP channel binding](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/ldap-channel-binding), and [SMB signing](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/overview-server-message-block-signing). The report does not claim full baseline alignment.

## Findings, context and presentation

Non-secure check instances produce attributable findings with affected resource, observed and expected state, evidence IDs, risk-oriented recommendation and validation method. Recommendations call for dependency validation before changing LDAP, NTLM, RC4, TLS, SMB or credentials. Existing generic exceptions remain visible and do not erase an observation or score. Per-DC state precedence is Critical, then Review, then required NotTested, then Secure. A DC with no findings and unavailable evidence is **NotChecked**, not Secure. The fictional sample includes a Secure DC, a Review DC, a Critical DC with observed NTLMv1, and unverified DCs. Domain-scoped privileged membership and KRBTGT checks are separate from per-DC checks.

The Security application uses the existing Overview, assessment posture, category tables, controller explorer, topology/tree, checks, findings, resources, evidence, coverage and optional exception views. Topology DC nodes carry Security state; replication edges remain neutral operational context. Inventory presentation is unchanged. Search, command palette, theme switching and print projection use existing generic application behavior. Print includes score, Security evidence coverage, categories, findings, checks, resources and evidence. No external assets are needed.

## Usage and limitations

Generate the fictional sample with `Examples/ActiveDirectory/Security/Invoke-PSIADSecurity.ps1 -UseSampleData -NoBrowser`. The default output is `Reports/Security/ADSecurity-Sample.html`. For a supplied shared snapshot, pass `-Snapshot`; assessment itself does not recollect. The mocked-live command adapter is for tests only; no production AD was queried for this milestone.

Live evidence gaps remain explicit: resultant GPO resolution; full privileged-group/account analysis; KRBTGT account metadata; directory ACLs; complete audit-policy and log retention; actual LDAPS, NTLMv1 and RC4 traffic; TLS negotiation; firewall exposure; endpoint protection health; effective credential-protection and interactive-logon rights. A certificate does not prove LDAPS usage, a registry value does not prove effective policy, and a quiet or failed event query does not prove absence of legacy authentication. These require future reusable read-only evidence sources, not optimistic inference. This assessment does not implement Compliance, an Assessment Suite, production testing or remediation.

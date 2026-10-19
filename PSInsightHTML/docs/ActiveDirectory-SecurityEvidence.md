# Active Directory Security evidence (11.17)

The shared AD provider collects a single domain-scoped snapshot. Security interprets that snapshot; it does not recollect or change the directory. The Security profile requests selected registry observations, one optional read-only remoting batch per DC, domain privileged membership, DC-container GPO links, and the existing DNS query. It does not request Health service, disk, share, and time checks by default. Failed remoting leaves CIM registry and directory observations available with explicit states.

## Contract and confidence

`SecurityCollectionResults` preserves selected registry values. `SecurityRuntimeResults` contains per-DC typed facts; `SecurityTelemetry` contains bounded parsed events; `PrivilegedEvidence` contains groups, direct and nested paths, account metadata, and KRBTGT metadata; `GpoIntent` contains links and inheritance flags only. The normalized snapshot retains these fields. The Security evidence model projects one observation per existing rule and scope and records source type, timestamp, query window, collection state, confidence, and error class. The unchanged 29-rule pack interprets those observations.

Collected means observed, not secure. Partial, Failed, NotSupported, and NotRequested cannot yield secure conclusions. High confidence denotes direct runtime, directory, or event facts; Medium denotes configuration whose effective state is uncertain; Low denotes intent or inference; ProviderInput marks reviewed fictional sample facts. GPO links never establish effective policy. Selected LDAP/NTLM DWORDs remain partial even when strong. A bounded event query with no matching event never proves zero NTLMv1, RC4, or LDAPS use.

| Evidence area | Source | Scope | State/confidence | Consuming rules | Limit |
| --- | --- | --- | --- | --- | --- |
| LDAP signing/channel binding, LAN Manager level | Selected registry DWORD via CIM | DC | Partial/Medium | `ldap-signing`, `ldap-channel-binding`, `ntlm-policy` | Resultant policy and client behavior unknown. |
| SMB server/client signing, SMBv1 | `Get-SmbServerConfiguration`, `Get-SmbClientConfiguration` | DC | Collected/High or unavailable | `smb-signing`, `smbv1` | Active server settings; not a connection capture. |
| TLS 1.0/1.1/1.2 client and server | Read-only Schannel registry values | DC | Partial/Medium | `tls10`, `tls11`, `tls12` | No negotiated protocol evidence. |
| Firewall profiles | `Get-NetFirewallProfile -PolicyStore ActiveStore` | DC | Collected/High or unavailable | `firewall` | Profile settings do not prove exposure. No rule dump. |
| Microsoft Defender | `Get-MpComputerStatus` | DC | Collected/High or NotSupported | `defender` | Unavailable Defender does not prove missing third-party protection. |
| Credential Guard | `Win32_DeviceGuard.SecurityServicesConfigured/Running` | DC | Collected/High or NotSupported | `credential-guard` | Running is separate from configured. |
| LSASS protection, WDigest | Read-only `RunAsPPL`, `UseLogonCredential` registry values | DC | Partial/Medium | `lsass-protection`, `wdigest` | Configuration only; no process or credential inspection. |
| Advanced Audit Policy | `auditpol /get /category:* /r` | DC | Partial/High | `audit-policy` | Subcategories retained; required baseline not defined. |
| Security event-log size | `Get-WinEvent -ListLog Security` | DC | Collected/High | `event-retention` | Size does not prove forwarding or duration. |
| NTLMv1 | Security event 4624 parsed XML | DC | Collected/High only on observed v1 | `ntlmv1-usage` | 300 events/DC and 72 hours by default; no hits remains NotTested. Event 4776 has unknown version. |
| Kerberos AES/RC4 | Security event 4769 ticket encryption type | DC | Collected/High only on observed RC4 | `rc4-usage` | A ticket does not prove account encryption capability. |
| LDAPS certificate | LocalMachine My store metadata | DC | Partial/Medium | `ldaps-capability` | Chain, EKU, hostname, and negotiated bind not fully validated; no private key export. |
| LDAPS usage | No default diagnostic enablement | DC | NotTested | `ldaps-usage` | Certificate presence is not traffic usage. |
| Privileged groups and nested paths | SID-based AD group/member queries | Assessed domain; forest-root groups only when root assessed | Collected/High or Partial | `privileged-members` (review still required) | Membership does not establish approval; unresolved groups are retained. |
| Privileged account metadata | Selected `Get-ADUser` properties | Domain | Collected/High or Partial | `privileged-hygiene` (review still required) | LastLogonTimestamp may lag; no secrets or owner decision. |
| KRBTGT metadata | `Get-ADUser krbtgt` | Assessed domain | Collected/High | `krbtgt-age` | Age uses typed PasswordLastSet and configurable threshold. |
| DC GPO links | `Get-ADOrganizationalUnit` for observed DC containers | Assessed domain | Collected/Low | None directly | Intent only; no precedence, security filtering, or effective result claim. |
| DNS zone transfers | Existing `Get-DnsServerZone` query | DC | Collected/Medium only with recognized mode for every primary zone | `dns-zone-transfer` | No transfer probe; unknown or failed zone query stays NotTested. |

The event parser retains a small allowlist of account, client, service, timestamp, version, event ID and query window. The report does not print raw event messages. Forest-root groups are marked `ForestRoot`; no other domain's DCs are included. No ACL, DCSync, AdminSDHolder, certificate-template, AD CS attack path, LAPS, gMSA, trust, or delegation assessment is included.

The optional runtime batch uses one PowerShell remoting invocation per DC. The older registry collector uses four CIM calls per DC. Privileged group traversal requires one member query per visited group and selected user metadata queries; this may dominate collection time in large domains. Live behavior needs authorized Windows PowerShell 5.1 validation. The fixture performs no AD queries.

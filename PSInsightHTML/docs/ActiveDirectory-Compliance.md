# Active Directory selected control mapping

## Milestone 11.19: applicability and two pinned framework slices

The provider now evaluates two independently versioned selected mapping packs
from `FrameworkRegistry.psd1`: Microsoft Windows Server 2025 Domain Controller
(Azure Policy reference, `FutureTarget`) and NIST SP 800-53 Revision 5.1
(`CurrentState`). The [NIST official Rev. 5.1 catalog](https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf)
publishes the selected SC-8, AU-12 and SC-7 references. NIST was selected
because its official versioned catalog is publicly accessible, its broad
controls can be cited with short paraphrases, and current PSI evidence can
support cautious **partial** relationships. This does not establish that an
organization adopted those controls or selected specific parameters. CIS and
DISA packs are deferred until their exact version, terms and mapping scope
can be reviewed. The Microsoft pack remains in `SelectedControls.psd1` to
preserve the existing loader path; the second pack is in
`NIST/SP800-53-Rev5.1.psd1`.

`Get-PSIADControlMappings -All` reads the registry and both packs. Stable
identity combines framework ID, version, control ID and mapping ID; one PSI
rule may appear in both packs. The crosswalk means **shared PSI observation**,
not equivalence between external controls. No new collector or rule engine is
involved. One normalized snapshot feeds Inventory, Readiness 2022/2025,
Health, Security and both compliance projections.

### Technical applicability

The evaluator checks framework mode, then control/resource role, OS family and
version, then mapped-check completeness and outcomes. `Applicable` requires
the selected technical scope to match. A known nonmatching role or OS is
`NotApplicable`. Missing OS or required version is `Unknown` and yields
`NotTested`, never N/A. `ContextOnly` marks an explicitly future-target or
informational mapping; its source observations remain linked but do not create
current Fail or Pass. On the fictional 2016/2019 estate all Microsoft 2025
controls are context only. The NIST slice has no Windows release requirement,
so those DCs are technically applicable, subject to unknown organizational
selection. Explicit AD Domain Services feature evidence takes precedence over
role inference; otherwise domain controller membership in the normalized
snapshot establishes the role. A mapping can additionally require the explicit
DNS role fact or an installed feature. Missing role/feature facts yield
`Unknown`; an explicitly absent role/feature yields `NotApplicable`. No
Windows roles are inferred from services. Pack and control requirements are
both enforced; a control cannot broaden its parent framework scope.

Per-resource outcomes are aggregated from **applicable resources only** in
the order Fail, Review, PartiallyAssessed, NotTested, Pass. If none are
applicable, Unknown wins over ContextOnly, which wins over NotApplicable.
Direct mappings can Pass only with sufficient Ready evidence; Partial
mappings cannot Pass, and Supporting relationships never determine status.
Evidence completeness counts only checks on technically applicable resources.
When none apply, the percentage is unavailable rather than zero. It is not a
pass rate. The framework comparison reports selected controls,
applicable/context-only counts and evidence completeness separately; there is
no whole-catalog percentage or blended compliance score.

The report includes comparison, control and resource registers, future-target
context, PSI-rule crosswalk, evidence, coverage and per-control detail.
Framework, status, applicability, mapping type, resource and control ID filters
use the existing table engine. Search and print use the existing application
shell. The print cover and registers identify the selected scope and
non-certification limit. The standalone file has no external runtime assets.

Milestone 11.18 established the first selected mapping. Milestone 11.19 adds
applicability and a second framework without collecting evidence or evaluating
a second set of PSI rules. The example is a **selected control mapping**,
not a certification or complete framework assessment. Unmapped controls are not
assumed compliant, and missing evidence remains unknown.

## Scope and version

The first pack uses selected setting identifiers in the Microsoft Windows
Server 2025 Domain Controller security baseline, as published in the
[Microsoft Azure Policy reference](https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025)
and the [Windows Server 2025 OSConfig baseline guide](https://learn.microsoft.com/en-us/windows-server/security/osconfig/osconfig-how-to-configure-security-baselines).
The pack is pinned to `2025 Domain Controller (Azure Policy reference)`.
The sample contains older fictional server versions. Their Microsoft 2025
mapping outcomes are explicitly `ContextOnly`.

The Microsoft pack has seven relationships and six distinct selected controls;
the NIST pack has four relationships and three selected controls. No full
catalog is bundled, so framework coverage percentage is unavailable.

## Contract

`SelectedControls.psd1` defines `Framework`, `FrameworkVersion`,
`CatalogControlCount`, and mappings with `ControlId`, short `ControlTitle` and
`ControlDescription`, `SourceRuleIds`, `EvidenceRequirements`, `Applicability`,
`MappingType`, `MappingConfidence`, `Notes`, and `Reference`. An optional
`MappingId` identifies a supporting relationship to the same external control.
Descriptions are paraphrased; benchmark text is not reproduced.

`Test-PSIADCompliance` accepts the **same normalized snapshot** and existing
Security and optional Health assessment results. It rejects results from a
different snapshot and does not mutate any input. Control records link by ID
to the source checks, findings, evidence, and resources. The original rule
evaluators remain authoritative.

## Mapping and outcome semantics

`Direct` means the mapped PSI rule addresses the selected setting directly.
`Partial` means it observes only part of what the setting requires. `Supporting`
adds context to another mapping and never determines the outcome by itself.
The domain-wide result aggregates applicable check results in this order:

1. Any `Blocked` check: `Fail`.
2. All missing or untested checks: `NotTested`.
3. A mix of complete and missing checks: `PartiallyAssessed`.
4. Any `Review` with complete evidence: `Review`.
5. All `Ready` checks on a `Partial` mapping: `PartiallyAssessed`.
6. All `Ready` checks on a `Direct` mapping: `Pass`.

When no check applies, the result follows the applicability precedence above.
Per-resource results retain the source evidence without altering it. An
exception is linked as review context; it cannot turn a failing result into a
pass. No remediation is executed. Existing finding guidance remains the only
recommendation source.

## Coverage metrics

- **Framework mapping coverage:** selected controls divided by a known full
  catalog count. The count is not available for this pack, so no percentage is
  shown. Unmapped controls are outside the selected slice.
- **Mapped-check evidence completeness:** check outcomes with complete
  assessment evidence (`Ready`, `Review`, or `Blocked`) divided by applicable
  mapped check outcomes. Supporting relationships are excluded from this
  denominator. Missing and partial source observations do not count as complete.
- **Health and Security scores:** remain independent provider assessment scores.
  No blended “compliance percentage” is calculated.

The print projection includes the scope and disclaimer, framework comparison,
selected control and resource registers, evidence IDs, coverage, and mapping
method. Application views use existing view, table, search, theme, and command
palette infrastructure. The HTML is standalone.

## Limits

This is a small selected slice, not a baseline audit. Exact GPO/resultant
configuration is not established for every DC. Source observations can be
absent, partial, or sample provenance. The full catalogs and unsupported
controls are not represented. ACL, PKI, and AD CS compliance are not assessed.
No production AD query was used to validate this example. Future framework
versions need reviewed mappings; keyword similarity is insufficient.

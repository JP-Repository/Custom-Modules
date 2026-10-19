# Active Directory assessment profiles

An assessment profile declares **what** a future assessment run should evaluate. Resolving a profile performs no collection or assessment. This contract belongs to the Active Directory provider; the generic PSInsightHTML report engine is unchanged.

## Format and resolution

Profiles are offline `.psd1` hashtables. Dot-source `Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1`, then call `Resolve-PSIADAssessmentProfile -Path <profile.psd1>` or pass an in-memory hashtable with `-Profile`. The resolver returns `SelectedAssessments`, `SelectedFrameworks`, `SelectedControls`, `ExcludedControls`, `TargetOS`, `ThresholdOverrides`, `Tags`, and `Metadata`, plus the profile name and description. It does not mutate the input or the mapping and threshold packs.

Supported assessment IDs: `Inventory`, `Health`, `Security`, `Readiness2022`, `Readiness2025`, `Compliance`. A profile needs at least one assessment. `Compliance` requires at least one framework; frameworks require `Compliance`.

Framework entries specify `FrameworkId`, exact pinned `Version`, and exact `Mode`. The resolver checks these against `Compliance/FrameworkRegistry.psd1` and its selected mapping packs. Currently registered pairs are `Microsoft-WindowsServer2025-DC` / `2025 Domain Controller (Azure Policy reference)` / `FutureTarget` and `NIST-SP800-53-Rev5.1` / `Revision 5.1` / `CurrentState`.

`ControlSelections` and `ControlExclusions` are arrays of `{ FrameworkId; ControlIds = @(...) }`. IDs must name primary controls in a selected pack. If no inclusion entry exists for a framework, all **currently mapped primary controls in that pack** are selected. Inclusion narrows that set; exclusion removes controls. Supporting mappings are context attached to primary controls, not selectable outcomes. `SelectedControls` and `ExcludedControls` carry stable `FrameworkId|Version|ControlId` identities. Excluded controls include both explicit exclusions and controls omitted by an inclusion list. This never implies full framework or catalog coverage.

`TargetOS` is optional and accepts `2022` or `2025`. It is context for future orchestration and does not change Readiness rules. Selecting both readiness assessments is permitted; a single `TargetOS` remains the profile's primary target context.

`ThresholdOverrides` is an optional hashtable with `Health` and/or `Security` buckets. Each bucket requires the corresponding selected assessment and uses the **exact keys** in `Rules/Health/Thresholds.psd1` or `Rules/Security/Thresholds.psd1`, excluding `Version` and `Source`. Overrides are explicit, numeric, finite, positive, and checked for score/percent bounds and existing threshold ordering. Values for counts, days, minutes, milliseconds, and MB must be whole numbers. For example, use `DiskReviewFreeGB` and `PrivilegedInactivityReviewDays`; conceptual aliases such as `DiskReviewGB` and `PrivilegedInactiveDays` are not accepted. The resolver returns only explicit overrides. It does not apply them or create new rules.

Unknown fields, assessments, frameworks, versions, modes, controls, target OS values, thresholds, duplicates, conflicts, invalid types, and invalid ranges cause a clear error. A control cannot be both included and excluded. The resolver never silently drops invalid configuration.

## Example

```powershell
$Profile = Resolve-PSIADAssessmentProfile -Profile @{
    Name = 'Example review'
    Assessments = @('Health', 'Security', 'Compliance')
    Frameworks = @(
        @{ FrameworkId = 'NIST-SP800-53-Rev5.1'; Version = 'Revision 5.1'; Mode = 'CurrentState' }
    )
    ControlSelections = @(
        @{ FrameworkId = 'NIST-SP800-53-Rev5.1'; ControlIds = @('SC-8') }
    )
    ControlExclusions = @(
        @{ FrameworkId = 'NIST-SP800-53-Rev5.1'; ControlIds = @('AU-12') }
    )
    ThresholdOverrides = @{
        Health = @{ DiskReviewFreeGB = 20 }
        Security = @{ PrivilegedInactivityReviewDays = 120 }
    }
}
```

The fictional sample profiles under `Providers/ActiveDirectory/Profiles/Samples/` are `Monthly-AD-Review.psd1`, `DC-Upgrade-2025.psd1`, and `Security-Review.psd1`. They contain no customer configuration. A future orchestration milestone can consume the resolved selection to run assessments on a shared snapshot. This milestone provides configuration and validation only.

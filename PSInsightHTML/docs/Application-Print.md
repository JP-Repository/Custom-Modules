# Application print projection

Application reports now embed a separate, static print document generated from the same report, application model, and assessment. The interactive shell remains the on-screen experience. The report Export > Print / PDF action activates the print document, opens the browser print dialog, and restores the application after printing. Browser Ctrl/Cmd+P also uses the print document. Legacy `Report` layout retains its existing print behavior.

`Export-PSIReport -EnableReportPrint $false` omits the print action and dedicated projection assets.

The print renderer is private (`ConvertTo-PSIPrintProjection`). It renders a cover, contents, executive summary, posture, scope, findings, categories, checks, resources, evidence summaries, optional exceptions, methodology, and metadata when the linked data exists. It prints the complete assessment regardless of current view, search query, table filter, or pagination. It does not print raw evidence `Data` or arbitrary resource `Properties`.

Assessment `Metadata.Print` still supports `ResourceColumns`, `IncludeEvidenceAppendix`, `IncludeChecks`, `IncludeExceptions`, and `MethodologyText`. Existing `ResourceColumns` arrays remain supported. The optional `Metadata.PrintDisplay` contract below supersedes `ResourceColumns` when present:

```powershell
Metadata = @{
    PrintDisplay = @{
        ReportIdentity = @{ Kicker = 'Fictional assessment document' }
        Resources = @{ Columns = @(
            @{ Property='Name'; Label='Resource'; Order=1 }
            @{ Property='Region'; Label='Region'; Order=2 }
            @{ Property='Status'; Label='Health'; Format='Status'; Order=3 }
        ) }
        Evidence = @{ Fields = @(
            @{ Property='Source'; Label='Observation source'; Order=1 }
            @{ Property='Summary'; Label='Summary'; Order=2 }
        ) }
        Checks = @{ Columns = @(@{ Property='Name'; Label='Check' }, @{ Property='Status'; Label='Status'; Format='Status' }) }
        Findings = @{ Fields = @(@{ Property='Summary'; Label='Observed' }, @{ Property='Recommendation'; Label='Action' }) }
    }
}
```

Each normalized field has `Property`, `Label`, `Format`, `Visible`, and `Order` (plus stable source index). `Format` accepts `Text`, `Boolean`, `DateTime`, `Number`, `Percent`, `Status`, or `List`. There is no executable formatter. `Visible=$false` omits a field. Duplicate fields, missing names, unsupported formats, and invalid ordering values are normalized or dropped; an empty result falls back to generic safe fields. Resource fields read only named core properties or provider-selected scalar values from `Resource.Properties`. Evidence fields are restricted to named safe properties and derived `Scope`, `CheckIds`, and `CollectionState`. `Evidence.Data`, arbitrary `Metadata`, and complex values never serialize into the print document. Fields with names suggesting passwords, tokens, credentials, private keys, secrets, or authentication material are rejected even if configured. Providers must still review benignly named fields before selecting them. Labels and values are HTML encoded.

Without configuration, resources print Name, Type, Status; evidence prints its identity, type, source, collection state, scope, collection time, summary, finding IDs, and check IDs. Checks and findings keep their existing default fields. Empty/null values are omitted in detail lists and render as blank table cells. A missing expected collection state displays `Not supplied`; provider-authored conceptual evidence can set `Evidence.Metadata.CollectionStateApplicability='NotApplicable'`, which displays `Not applicable`. Actual lifecycle states are displayed only when supplied as `CollectionState` with one of `Collected`, `Partial`, `Failed`, `NotSupported`, `NotRequested`, or `NotTested`. This marker never changes collection coverage or scoring. `Metadata.EvidenceCoveragePercent` and `Metadata.CollectionCounts` are displayed only when supplied; coverage is separate from readiness score.

The print stylesheet uses a light paper theme, text status labels, repeating table headers, wrapping columns, and page-break rules. Browser page-margin boxes carry the escaped report identity, target, version, and page number where supported. The same identity, metadata, and closing footer are in the document body, so missing margin-box support does not lose report content. Print background graphics are optional; status labels and borders carry meaning in grayscale. Engines may differ in `@page`, margin boxes, `break-inside`, table-header repetition, SVG, and background printing. Actual pagination and PDF links depend on the browser's print engine; A4 and Letter should be checked with the intended browser before distribution.

Local validation:

```powershell
Invoke-Pester ./Tests
./Examples/New-AdaptiveDemoReport.ps1 -NoBrowser
./Examples/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1 -TargetOS 2025 -UseSampleData -NoBrowser
```

With local Chrome available, `python3 Tests/Validate-PrintProjection.py <html> Reports/Print <name>` generates A4 and Letter PDFs. `Reports/Print/` contains generated validation artifacts and should remain untracked. Do not run the DC Readiness example against a live directory for print validation.

Milestone 11.10 validation used fictional Adaptive Demo and DC Readiness data under `Reports/PrintHardening/`. Chrome generated A4 and Letter PDFs with background graphics disabled. A PDFKit page audit found no blank pages; representative cover, summary, category, check, finding, resource, evidence, and methodology pages were captured as PNGs. Evidence pages were also reviewed in grayscale; status labels and borders remained readable. Safari opened the local HTML, but automated WebKit print inspection was unavailable because Safari's Allow remote automation setting was disabled. Firefox was not installed. These untested engines should be reviewed before relying on exact pagination or margin-box output in them.

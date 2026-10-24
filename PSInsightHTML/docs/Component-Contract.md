# PSInsightHTML Component Contract (as implemented)

Scope: the exact object shapes built by `Public\*.ps1` and how `Private\ConvertTo-PSIHtml.ps1` and the
other renderers consume them. Source of truth is the PowerShell source in this folder (module manifest
`PSInsightHTML.psd1` reports `ModuleVersion = '0.11.2'`). File references are `file:line`. Nothing here is a
proposal; where behaviour looks surprising it is listed in section 9.

Conventions used below

- "PS object" = `[pscustomobject]`; "List" = `System.Collections.Generic.List[object]`; "hashtable" = PowerShell
  `@{}` (case-insensitive keys, unordered unless `[ordered]`).
- Property lookup in the renderer is almost always via `Get-PSIProperty`, which is **case-insensitive** for
  dictionaries and PS objects and returns a default when missing (`Private\Get-PSIProperty.ps1:17-30`).
  Table cell lookup uses `Get-PSITableValue` with the same case-insensitive semantics
  (`Private\Get-PSITableValue.ps1:17-32`). A JS renderer reading JSON is case-sensitive; see 9.
- "Id pattern" = `^[A-Za-z][A-Za-z0-9_-]*$` (used for views, explorers, tables, model records, etc.).
- Canonical status = one of `Healthy, Warning, Critical, Informational, Neutral, Unknown, NotChecked` (section 4).

---

## 1. Report object

Created by `New-PSIReport` (`Public\New-PSIReport.ps1:57-75`).

| Property | Type | Default / source | Notes |
|---|---|---|---|
| `Title` | string | mandatory, non-empty | HTML `<title>`, `<h1>` (Report layout) |
| `Subtitle` | string | `''` | |
| `Theme` | string | `'Light'` | `Light`/`Dark`/`Auto`; re-validated at render (`ConvertTo-PSIHtml.ps1:24-27`). Browser `localStorage['psi-report-theme']` overrides it at runtime (`psi-interactions.js:21-26`). |
| `GeneratedOn` | DateTime | `Get-Date` | rendered `yyyy-MM-dd HH:mm:ss zzz` (`ConvertTo-PSIHtml.ps1:23`) |
| `ModuleVersion` | string | `$script:PSIModuleVersion` | from manifest (`PSInsightHTML.psm1:3-6`); see 9 (stale bundle hard-codes `0.10.0`) |
| `Sections` | List of Section | empty | flat, ordered list of **all** sections (also those inside views) |
| `Assessments` | List of AssessmentEntry | empty | filled by `Add-PSIAssessment` |
| `Findings` | List of Finding (legacy, `New-PSIFinding` shape) | empty | filled by `Add-PSIFinding` and `Add-PSIAssessment` |

Added **only** with `-Layout Application` (`New-PSIReport.ps1:67-74`):

| Property | Type | Default | Notes |
|---|---|---|---|
| `Layout` | string | `'Application'` | absent means `Report` (renderer default, `ConvertTo-PSIHtml.ps1:28`) |
| `NavigationGroups` | object[] | `@()` | manual nav (section 2.6); cannot be combined with Views |
| `Navigation` | string | `'Sidebar'` | `Sidebar` or `FluentExplorer` |
| `Density` | string | `'Comfortable'` | `Comfortable` or `Compact`. `FluentExplorer`+`Compact` = "compact fluent" mode, which changes table cell rendering and adds workspace tabs |
| `Views` | List of View | empty | multi-view workspace when Count > 0 |
| `ActiveViewId` | string | `''` | set by `Add-PSIView` to the last view added; `Add-PSISection` attaches new sections to that view |

Added later by other commands (all `Add-Member` NoteProperties):

| Property | Added by | Type |
|---|---|---|
| `ApplicationModel` | `Set-PSIApplicationModel` | ApplicationModel (6.2) |
| `ApplicationAssessment` | `Set-PSIApplicationAssessment` | ApplicationAssessment (6.3), posture resolved against the model |
| `ResourceExplorer` | `Add-PSIResourceExplorer` | `{Id, Title, Nodes[], SelectedId}` (6.6) |
| `Inspector` | `Add-PSIInspector` | `{Id, Title, Items[]}` (6.7) |
| `PrintDisplay` | not created by any public command; read only by print projection when there is no ApplicationAssessment (`ConvertTo-PSIPrintProjection.ps1:44`) | dictionary |

Validation rules: `Report` layout rejects NavigationGroups and non-default Navigation/Density
(`New-PSIReport.ps1:50-55`, `ConvertTo-PSIHtml.ps1:33-38`). `Export-PSIReport` requires at least one section
(`Export-PSIReport.ps1:35-38`). Table IDs must be unique report-wide, case-insensitive (`Assert-PSIReportIds.ps1`).

---

## 2. Structural objects

### 2.1 Section (`Add-PSISection.ps1:50-67`)

| Property | Type | When present |
|---|---|---|
| `Title` | string | always |
| `Rows` | List of Row | always |
| `AssessmentId` | string | section created on an Assessment, or added via `Add-PSIAssessment` |
| `AssessmentName` | string | same as above |
| `ViewId` | string | section created while `Report.ActiveViewId` is non-empty |
| `IsOverview` | bool `$true` | only the section created by `Add-PSIReportOverview` |

If `ActiveViewId` is set, the **same** section object is added to both `Report.Sections` and `View.Sections`
(`Add-PSISection.ps1:59-67`).

DOM id is positional: `psi-section-<index in Report.Sections>` (`ConvertTo-PSIHtml.ps1:131`). KPI `ScrollTo`
actions and navigation target these ids.

### 2.2 Row (`Add-PSIRow.ps1:61-64`)

| Property | Type | Default |
|---|---|---|
| `Columns` | int 1-12 | 12 |
| `Components` | List of Component | empty |

The CSS grid is **always 12 tracks** (`psi-theme.css:173`). `Columns` is emitted as `--psi-row-columns` and
acts as the default span for row-wide components (Text, Status, Alert, Recommendation, Finding, Chart, Table
fallback; `psi-theme.css:185,216,221,230,275,348`). For KPI and Insight it is also the numerator of the auto
span `floor(Columns / count-of-that-type-in-row)` (`ConvertTo-PSIHtml.ps1:180-185,401`).

### 2.3 Component envelope (`New-PSIComponent.ps1:12-15`)

`{ Type: string, Properties: hashtable }`. Every component is appended to the **last row of the last section**
(`Add-PSIComponentToLastRow.ps1`, `Get-PSILastRow.ps1`). Unknown `Type` values are silently skipped by the
renderer's `switch` (`ConvertTo-PSIHtml.ps1:208-779`).

Component Types produced: `Text, KeyValue, KPI, Sparkline, EmptyState, Insight, Finding, Status, Alert,
Recommendation, Table, Chart, AssessmentOverview, Explorer, Tree, Topology, RelationshipExplorer`.

Before the switch the renderer computes a status for **every** component from `Properties.Status`
(`Resolve-PSIStatus -AllowInvalid`, default `Unknown`) and a class suffix (`ConvertTo-PSIHtml.ps1:189-196`).

### 2.4 View (`Add-PSIView.ps1:84-96`)

| Property | Type | Default | Notes |
|---|---|---|---|
| `Id` | string | mandatory, Id pattern | unique (case-insensitive); DOM `psi-view-<Id>` |
| `Title` | string | mandatory | |
| `Subtitle` | string | `''` | shown in command bar when view active |
| `Icon` | string | `'Document'` | must be a known icon (strict) |
| `Group` | string | `'Workspace'` | nav group label; groups in first-seen order |
| `Badge` | string | `''` | nav badge |
| `TabCount` | int? | `$null` | only rendered as tab count in compact fluent tabs (`ConvertTo-PSIApplicationShell.ps1:142-143`) |
| `Disabled` | bool | false | nav item rendered as non-interactive span |
| `Sections` | List of Section | empty | must be non-empty at render |
| `Commands` | List `{Label, Icon, TargetView}` | empty | command-bar buttons shown only while this view is active |
| `State` | hashtable `{Initial: bool}` | `{Initial=$false}` | at most one initial; initial cannot be disabled |

Rules (`Add-PSIView.ps1:51-70`, `Resolve-PSIApplicationNavigation.ps1:48-93`): requires Application layout; not
combinable with NavigationGroups; the first view must precede any section; view sections must be contiguous
and in the same order as `Report.Sections` with matching `ViewId`; every report section must belong to a
view; command targets must exist (case-sensitive). Initial view = `State.Initial`, else the first enabled
nav item (`Resolve-PSIApplicationNavigation.ps1:150`, `ConvertTo-PSIApplicationShell.ps1:124-128`). Non-initial
views render with `hidden`.

### 2.5 Assessment (legacy composition, `New-PSIAssessment.ps1:49-60`)

PS object with TypeName `PSInsightHTML.Assessment` inserted at position 0.

| Property | Type | Default |
|---|---|---|
| `Id` | string | `psi-assessment-<guid N>` when omitted |
| `Name` | string | mandatory |
| `Title` | string | `Name` when empty |
| `Provider` | string | `''` |
| `Description` | string | `''` |
| `Metadata` | hashtable | `@{}` |
| `Sections` | List of Section | empty |
| `Findings` | List of Finding | empty |

An Assessment accepts `Add-PSISection`/`Add-PSIRow`/`Add-PSI*` exactly like a report. Sections created on it
get `AssessmentId`/`AssessmentName` (`Add-PSISection.ps1:54-57`).

`Add-PSIAssessment` (`Public\Add-PSIAssessment.ps1:41-75`):
1. rejects duplicate assessment Id (case-insensitive) and table-id collisions before mutating;
2. stamps `AssessmentId`/`AssessmentName` on sections that lack them (throws if a section already belongs to
   another assessment);
3. appends the **same** section objects to `Report.Sections` and each finding to `Report.Findings`;
4. appends an AssessmentEntry:

```
{ Id, Name, Title, Provider, Description, Assessment: <full Assessment object>, SectionCount, FindingCount }
```

It does **not** set `ViewId`, so it is incompatible with multi-view reports (see 9).

Report-layout navigation uses these fields: when `Report.Assessments.Count > 0`, an "assessment nav" is
rendered with an `Overview` link for `IsOverview` sections and one link per distinct `AssessmentId` (pointing
to that assessment's first section), plus a collapsible "All sections" nav (`ConvertTo-PSIHtml.ps1:133-149,873-893`).
Section elements carry `data-psi-overview="true"` or `data-psi-assessment-key="<AssessmentId>"`.

Summaries (no HTML):
- `Get-PSIFindingSummary` -> `{Total, Critical, Warning, Healthy, Informational, Neutral, Unknown, NotChecked}`
  counting `Resolve-PSIStatus(finding.Status)`.
- `Resolve-PSIOverallStatus`: `Neutral` if Total=0, else first status with count>0 in order
  `Critical, Warning, Unknown, NotChecked, Informational, Healthy, Neutral` (`Resolve-PSIOverallStatus.ps1`).
- `Get-PSIAssessmentSummary` -> `{Id, Name, Title, Provider, SectionCount, FindingCount, Critical, Warning,
  Healthy, Informational, Neutral, Unknown, NotChecked, OverallStatus}`.
- `Get-PSIReportSummary` -> `{OverallStatus, FindingSummary, FindingCount, AssessmentCount, SectionCount,
  TableCount, AssessmentSummaries[]}`.

### 2.6 Report Overview (`Add-PSIReportOverview.ps1`)

Builds ordinary components (no special type) in a section titled `Report Overview` with `IsOverview=$true`,
then moves that section to index 0 (`:110-111`). Content:
1. `Status` = report overall status, label `Overall assessment`.
2. KPIs `Critical`, `Warning`, `Informational` (finding counts, icons `critical`/`warning`/`info`) and
   `Assessments` (count, `Neutral`, icon `dashboard`), Span 3.
3. Text `Assessment Overview` (Large); per assessment a KPI with `Value = OverallStatus`,
   `Subtitle = "<n> finding(s)|No structured findings · <SectionCount> sections"`, `Action = {Type='ScrollTo';
   Target='psi-section-<index after the overview is moved>'}` (`:63-75`).
4. With `-IncludeTopFindings`: findings ordered by status rank (`Critical, Warning, Unknown, NotChecked,
   Informational, Healthy, Neutral`), up to `MaxFindings` (default 10), each a KPI (`Value = status`, Span 4) with
   `ScrollTo` to the finding card's DOM anchor matched by object reference (`:93-106`).
Throws if an overview already exists.

### 2.7 Application navigation (`Resolve-PSIApplicationNavigation.ps1`)

Output: List of `{Label, Items: List of {Id, Label, Target, Icon, Badge, Disabled, Selected}}`.

Source precedence:
1. **Views present** -> one group per `View.Group`; item `Id = View.Id`, `Target = "psi-view-<Id>"`,
   `Selected = View.State.Initial` (`:48-97`).
2. **`NavigationGroups` supplied** -> raw `{Label, Items:[{Id, Label, Target, Icon='Document', Badge='',
   Disabled=$false, Selected=$false}]}`; enabled items must target `psi-section-<n>` of an existing section
   (`:117-136`).
3. **Neither** -> single group `Report`, one item per section `{Id="section-<i>", Target="psi-section-<i>",
   Icon = 'NavigationHome' for i=0 else 'Document', Selected = i==0}` (`:98-106`).

Validation: item Id pattern; unique `psi-app-item-<Id>`; label required; icons strict; disabled cannot be
selected; at most one selected; at least one enabled; if none selected the first enabled is selected
(`:111-150`). The function also reserves and checks ids for tables (`<id>`, `<id>-data`), finding anchors,
explorers (`<id>`, `<id>-search`, `<id>-item-<n>`, `<id>-detail-<n>`), relationship components, views
(`psi-view-<id>`) and shell ids (`:6-44`).

In Application layout each section `<h2>` gets the icon of the nav item that targets it, or in multi-view the
icon of its view (`ConvertTo-PSIHtml.ps1:96-114,151-156`).

---

## 3. Component reference

Defaults below are the cmdlet defaults; the "Renderer" column describes `ConvertTo-PSIHtml.ps1` behaviour.
"Span" means `--psi-component-span` on a 12-track grid.

### 3.1 Text (`Add-PSIText.ps1:37-40`; render `ConvertTo-PSIHtml.ps1:218-227`)

| Key | Type | Default | Allowed | Renderer |
|---|---|---|---|---|
| `Text` | string | mandatory | | HTML-encoded, plain text |
| `Size` | string | `Normal` | `Small, Normal, Large` | class `psi-text-<size>`; invalid -> Normal |

No span; spans `--psi-row-columns`.

### 3.2 KeyValue (`Add-PSIKeyValue.ps1:41-45`; render `:228-247`)

| Key | Type | Default | Renderer |
|---|---|---|---|
| `Title` | string | mandatory | `<h3>` |
| `Data` | IDictionary | mandatory | iterates `.Keys` in dictionary order (use `[ordered]` for stable order); value `null` -> em dash, string/ValueType -> `[string]`, else compact JSON depth 5 |
| `Span` | int 1-12 | 6 | throws outside 1-12 |

### 3.3 KPI (`Add-PSIKPI.ps1:96-108`; render `:248-345`)

| Key | Type | Default | Notes |
|---|---|---|---|
| `Title` | string | mandatory | |
| `Value` | any (nullable) | mandatory | null -> em dash; string/ValueType -> `[string]`; else compact JSON |
| `Subtitle` | string | `''` | shown if non-blank |
| `Status` | canonical status | `Unknown` | class `psi-status-<suffix>`, `data-status` |
| `VisualTone` | string | `Status` | `Status` or `Informational`; Informational adds class `psi-tone-informational` without changing Status |
| `Span` | int 1-12 | 3 | renderer falls back to `floor(Row.Columns / KPIs in row)` only if Span is absent (never via cmdlet) |
| `Icon` | string | `''` | non-strict icon lookup: unknown names fall back to `dashboard` |
| `Trend` | string | `''` | shown if non-blank |
| `Action` | dictionary/PS object | `@{}` | see below |
| `DrillDown` | any | `$null` | records for legacy record dialog |
| `Filter` | hashtable | `@{}` | KPI -> table filter, see below |

Interactivity (renderer `:266-321`):
- **Action** is "generic" when `Type` is `ScrollTo` or `FilterTable` (case-insensitive) and `Target` is non-blank;
  for `FilterTable` it additionally needs a non-blank `Property` and a scalar `Value`. Generic actions are
  re-serialized as `{Type:'ScrollTo'|'FilterTable', Target, Property?, Value?}`; any other Action is serialized
  verbatim. Always emitted as `data-action` JSON.
- **Filter** (validated `Add-PSIKPI.ps1:85-94`): requires non-blank `Table` and `Property`, plus `Value` or
  `Values`. Emitted verbatim as `data-psi-filter-action` JSON.
- **DrillDown** is active when `@(DrillDown)` is non-empty and its first element is non-null; emitted as
  `data-psi-drilldown data-psi-records="<ConvertTo-Json -Depth 10>" data-psi-detail-title`.
- If any of the three is active the card is a `<button class="psi-kpi-card psi-kpi-clickable">` with a hint
  (`View details` for drilldown/filter, `Filter table` for FilterTable action, `Go to section` for ScrollTo);
  otherwise an `<article>`.

Client semantics (`psi-interactions.js:282-314`):
- `data-psi-filter-action` click dispatches `psi:apply-filter` with `{tableId: Table|tableId,
  property: Property|property, value: Value|value, values: Values|values, source:'kpi'}`.
- `data-action` is only handled on KPI buttons **without** filter-action or drilldown. `ScrollTo` ->
  `scrollIntoView` of element `Target`; `FilterTable` -> requires element `Target` with `data-psi-table="true"`
  and a string/number/boolean `Value`, dispatches `psi:apply-filter {tableId:Target, property, value,
  source:'kpi-action'}`.
- `data-psi-drilldown` opens the legacy dialog (7.2). A KPI with both Filter and DrillDown fires **both**.

Table response to `psi:apply-filter` (`psi-table.js:299-330`), for the table whose DOM id equals `tableId`:
1. `detail.conditions` array present -> replaces the table's external conditions (used by evidence "Apply").
2. else if a filter control has `data-psi-filter-property === detail.property` (case-sensitive): clears
   external conditions, selects `detail.values` (MultiSelect) or the first of `values`/`value` (Select).
3. else if `detail.property` names a column (case-insensitive) and `detail.value` is defined: sets a single
   external condition `{Property, Operator:'Equals', Value}`.
4. otherwise ignored. In all applied cases page resets to 1 and the table scrolls into view; in multi-view the
   containing view is activated first (`psi-application.js:127-133`).

### 3.4 Sparkline (`Add-PSISparkline.ps1:39-42`; render `:346-371`)

| Key | Type | Default | Validation |
|---|---|---|---|
| `Values` | double[] | mandatory | 2-120 finite numbers (invariant parse; bool/null rejected) |
| `Label` | string | `''` | |
| `CurrentValue` | any | `$null` | null -> last value |
| `Status` | canonical | `Info` -> `Informational` | class from `Get-PSIStatusPresentation` (`informational`, `not-checked`, ...) |
| `Minimum`/`Maximum` | double? | `$null` | finite, Min < Max, must include all values |
| `Span` | int 1-12 | 3 | |

Geometry: viewBox `0 0 100 34`, `x = 100*i/(n-1)`, `y = 30 - 26*(v-lo)/(hi-lo)` with clamping; `lo/hi` = data
min/max unless Minimum/Maximum; if `hi <= lo` then `hi = lo+1`. Aria label includes `Range: lo to hi`.

### 3.5 EmptyState (`Add-PSIEmptyState.ps1:17-20`; render `:372-387`)

| Key | Type | Default | Notes |
|---|---|---|---|
| `Title` | string | mandatory | |
| `Explanation` | string | mandatory | |
| `Icon` | string | `Document` | strict icon |
| `ActionLabel` | string | `''` | must be supplied together with TargetView |
| `TargetView` | string | `''` | `''` or Id pattern; at render must be an existing view (case-sensitive) in Application layout, else throws |

Button `data-psi-empty-target` -> `activateView` (multi-view only, `psi-application.js:121-123`).

### 3.6 Insight (`Add-PSIInsight.ps1:85-95`; render `:388-426`)

| Key | Type | Default | Notes |
|---|---|---|---|
| `Title` | string | mandatory | |
| `Value` | any | mandatory | same formatting as KPI |
| `Description` | string | `''` | also used as dialog description |
| `Status` | canonical | `Info` -> `Informational` | |
| `Icon` | string | `''` | non-strict |
| `Filter` | hashtable | `@{}` | when non-empty must contain non-blank `Table` and a `Conditions` collection (may be empty = all rows); each condition needs `Property` and an evidence operator (5.2) |
| `EvidenceColumns` | string[] | `@()` | dialog columns |
| `ExportColumns` | string[] | `@()` | dialog export columns |
| `ColumnLabels` | hashtable | `@{}` | dialog header/export labels |

No Span key; span = `floor(Row.Columns / Insights in row)`. When Filter is non-empty, renders a button with
`data-psi-insight=<EvidenceDefinition JSON>` (5.3) built **without** `useVisibleColumns`; see 9 for the
consequence when EvidenceColumns is empty. Unlike Finding, a missing table is not detected server-side.

### 3.7 Finding card (`Add-PSIFinding.ps1:39-58`; render `:427-493`)

Input is a Finding object (section 6.1). Component Properties:

| Key | Type | Notes |
|---|---|---|
| `Id` | string | `ConvertTo-PSIFindingId` (sanitized; generated `psi-finding-<guid>` when blank) |
| `Title` | string | required non-empty |
| `Status` | canonical | |
| `Category`, `Description`, `AffectedObject`, `Impact`, `Recommendation`, `RuleId`, `Source` | string | each rendered only if non-blank |
| `EvidenceTableId` | string | normalized: `EvidenceFilter.Table` wins when set (must match if both supplied) |
| `EvidenceFilter` | hashtable | raw (5.3) |
| `EvidenceColumns` | string[] | also used as export columns |
| `FindingReference` | object | reference to the original finding (used to resolve ScrollTo anchors) |

`Add-PSIFinding` also appends the original finding to `Report.Findings` (or `Assessment.Findings`).

Rendering: `<article class="psi-finding-card" id="<anchor>" data-psi-finding-card data-psi-affected-object
data-psi-finding-status>`; status badge; category; title; description; `<dl>` with Affected object / Impact;
Recommendation block; footer with evidence button, `Rule:` and `Source:`. The DOM anchor is the finding Id
de-duplicated against section ids, table ids, filter ids and earlier anchors by suffixing `-2`, `-3`, ...
(`Get-PSIFindingAnchors.ps1:29-45`). Evidence definition is rebuilt with `useVisibleColumns = true`; if its
`tableId` is not a table in the report a warning is written and the evidence button omitted (`:446-449`).
In Application layout a Fluent severity icon is prefixed (Healthy -> SeveritySuccess, Warning ->
SeverityWarning, Critical -> SeverityError, other -> SeverityInfo; `:198-206`).

### 3.8 Status (`Add-PSIStatus.ps1:40-44`; render `:494-509`)

`Status` (canonical, mandatory), `Label` (`''`), `Message` (`''`). Renders status text, optional label and message;
Application layout uses the Fluent severity icon, Report layout a `psi-status-indicator` dot.

### 3.9 Alert (`Add-PSIAlert.ps1:55-62`; render `:510-537`)

| Key | Type | Default | Renderer |
|---|---|---|---|
| `Status` | canonical | mandatory | |
| `Title` | string | mandatory | |
| `Message` | string | mandatory | |
| `Timestamp` | any | `$null` | `[string]` cast inside `<time>` (no ISO formatting) |
| `Details` | any | `$null` | string or **primitive** -> text; anything else (incl. DateTime) -> compact JSON; inside `<details>` |
| `Action` | string | `''` | "Suggested action:" line |

### 3.10 Recommendation (`Add-PSIRecommendation.ps1:47-52`; render `:538-550`)

`Status` (default `Info` -> `Informational`), `Title`, `Description` (mandatory), `ActionText` (`''`, "Suggested action:").

### 3.11 Table (`Add-PSITable.ps1:194-214`; render `:551-758`)

| Key | Type | Default | Validation / renderer |
|---|---|---|---|
| `Title` | string | mandatory | |
| `Span` | int 1-12 | 12 | |
| `Data` | object[] | mandatory (may be empty) | dictionaries or PS objects |
| `Columns` | string[] | explicit list, else union of keys/properties in first-seen order (`Get-PSITableColumnNames.ps1`; NoteProperty/Property/AliasProperty/CodeProperty) | duplicates/blanks rejected; empty -> single header `Results` |
| `ColumnLabels` | hashtable | `@{}` | header text only; `ContainsKey` lookup |
| `Filters` | object[] | `@()` | `Add-PSIFilter` objects; property must be a column; unique per property |
| `Conditions` | object[] | `@()` | `New-PSICondition`-shaped (5.1) |
| `Id` | string | `psi-table-<guid N>` when blank | Id pattern; unique report-wide; DOM `<Id>` and `<Id>-data` |
| `PageSize` | int 1-500 | 10 | |
| `EnableSearch` | bool | true | row text search box |
| `EnableSorting` | bool | true | header sort buttons |
| `EnablePagination` | bool | true | |
| `EmptyMessage` | string | `No records match your filters.` | if Data is empty and message is the default it becomes `No data available.` (`:565`) |
| `NullValueText` | string | em dash (U+2014) | rendered for `$null` cells (class `psi-null-value`) |
| `EnableExport` | bool | true | |
| `ExportColumns` | string[] | all columns | must be visible columns (case-insensitive) |
| `ExportFormats` | string[] | `Csv, Xlsx, Print` | subset; >=1 when export enabled; toolbar order is always Csv, Xlsx, Print |
| `ExportFileName` | string | `''` | |
| `WorksheetName` | string | `''` | |

Filter definition (`Add-PSIFilter.ps1:67-72`): `{Property, Label (default Property), Type: 'Select'|'MultiSelect',
Values: string[]}`; values non-null, non-blank, unique case-insensitive. Select gets an `All` option. More than
2 filters are wrapped in a collapsed `<details>` "Filters (n)" (`:594-601`). An "Active filters" chip row
is rendered when filters exist.

Cell rendering per row (`:658-741`):
1. Row condition: the **first** `Scope='Row'` condition that matches -> `<tr class="psi-row-status-<suffix>">`.
2. Per column, the **first** `Scope='Cell'` condition whose `Property` equals the column (case-insensitive) and
   matches -> class `psi-cell-status-<suffix>`; the cell shows plain text (no auto badge).
3. `$null` -> `NullValueText` with class `psi-null-value`.
4. Value text = `[string]` for strings/ValueTypes, else compact JSON depth 5.
5. Without an explicit cell status, a value whose text is a status renders as a badge
   `<span class="psi-status-badge psi-status-<suffix>">`:
   - normal mode: `Resolve-PSIStatus -AllowInvalid` and the badge text is the **canonical** status
     (e.g. `info` -> `Informational`);
   - compact fluent: `Get-PSIStatusPresentation` (broader vocabulary incl. Ready/Review/Blocked/NotTested/NA),
     badge text is the original trimmed text plus a 12px Fluent icon.
6. Numeric CLR types get class `psi-numeric-cell`. Compact fluent adds `title` = cell text.

Export config emitted as `data-psi-export-config = {columns, labels: ColumnLabels, formats, fileName,
worksheetName}` (`:575-582`).

### 3.12 Chart (`Add-PSIChart.ps1:104-118`; render `ConvertTo-PSIChartMarkup.ps1`, wrapper `ConvertTo-PSIHtml.ps1:759-778`)

| Key | Type | Default | Notes |
|---|---|---|---|
| `Title` | string | mandatory | |
| `ChartType` | string | `Bar` | `Bar, Line, Doughnut, Pie` |
| `Data` | object[] | mandatory | |
| `CategoryProperty` | string | mandatory | null category -> `Not specified`; non-scalars -> JSON |
| `ValueProperty` | string | mandatory | must convert to double (invariant) or be null; otherwise **render-time** throw |
| `SeriesProperty` | string | unset (`''`) | when unset, a single series named after ValueProperty; null series value -> `Unspecified series` |
| `StatusProperty` | string | unset | point status; falls back to treating the category text as a status |
| `FilterMetadata` | hashtable | `@{}` | `{Table, Property, ValueProperty (default CategoryProperty)}` |
| `Width` | int 320-1600 | 900 | SVG viewBox width |
| `Height` | int 180-900 | 320 | SVG viewBox height |
| `ShowLegend` | bool | true | |
| `ShowLabels` | bool | false | pie: percentage; bar/line: value |
| `EmptyMessage` | string | `No chart data is available.` | |

Aggregation: categories in first-seen order; duplicate category within a series are **summed**
(`:145-157`); nulls counted (`NullValueCount`) and omitted. Colors: canonical status ->
`var(--psi-status-<suffix>)`, else palette `var(--psi-chart-1..8)` by series index (bar/line) or slice index
(pie). Pie/Doughnut aggregate all series, reject negatives, treat total <= 0 as empty; doughnut inner radius
= 0.58 x outer. Bar/Line y-range always includes 0; 5 grid ticks; category labels truncated at 18 chars. Card
summary text `"<n> points; <m> null values omitted"`. No Span key.

FilterMetadata semantics (`:36-77`): for each category, the stringified value of `ValueProperty` from the data
rows becomes the filter value; categories whose rows disagree (ordinal) or whose value is null get **no**
filter. Each filterable mark gets `class="psi-chart-filter-point" role="button" tabindex="0"
data-psi-chart-filter='{"tableId":Table,"property":Property,"value":"<string>"}'`, and the SVG role becomes
`group`. Click or Enter/Space dispatches `psi:apply-filter {tableId, property, value, source:'chart'}`
(`psi-interactions.js:316-334`), handled as in 3.3.

### 3.13 AssessmentOverview (`Add-PSIAssessmentOverview.ps1`; render `ConvertTo-PSIAssessmentOverviewHtml.ps1`)

Requires `Report.ApplicationAssessment`. Properties: `Assessment` (reference to ApplicationAssessment),
`Model` (ApplicationModel), `CheckViewId` (default `checks`), `FindingViewId` (default `findings`).

Rendered: hero with `AssessmentType`, `Name`, `Description`, `Target`, `Profile`; decision label =
`Decision` split on camel case and upper-cased (`READY WITH REVIEW`); first two `Reasons`; score gauge
(`--psi-posture-score` clamped 0-100, text `N/A` when Score null); optional coverage tile from
`Metadata.EvidenceCoveragePercent`. Count tiles: `Blockers = Counts.Blockers + Counts.CriticalFindings`,
`Review`, `Ready`, `Not tested`. Category buttons (`data-psi-category-target=<CheckViewId>`,
`data-psi-category-id`) with score, status, per-status counts from `ScoreExplanation.CategoryScores`.
"Top blockers": up to 5 checks with `Status='Blocked'` or (`IsBlocking` and `Review`) -> cross-view to
CheckViewId. "Priority findings": up to 5 model findings in `Assessment.FindingIds` with Status not in
`Resolved, AcceptedRisk, NotApplicable`, ordered Critical, Warning, other -> cross-view to FindingViewId.
Also Recommendations, Scope, counts of linked resources/evidence and not-applicable checks.

### 3.14 Explorer (`Add-PSIExplorer.ps1:63-75`; render `ConvertTo-PSIExplorerHtml.ps1`)

Requires Application layout with at least one view.

| Key | Type | Default | Notes |
|---|---|---|---|
| `Id` | string | mandatory, Id pattern | DOM `<Id>`, `<Id>-search`, `<Id>-item-<n>`, `<Id>-detail-<n>` |
| `Title` | string | mandatory | |
| `Data` | object[] | mandatory | |
| `TitleProperty` | string | mandatory | blank -> `(unnamed)` |
| `SubtitleProperty` | string | `''` | |
| `StatusProperty` | string | `''` | |
| `DetailProperties` | string[] | `@()` | generic detail list; default = keys/properties of `Data[0]` |
| `ColumnLabels` | hashtable | `@{}` | generic detail labels; default label = camel-case split |
| `EmptyMessage` | string | `No records available.` | |
| `EntityType` | string | `''` | `Finding, Resource, Evidence, Check, Category, Exception` |
| `Model` | ApplicationModel or null | set when EntityType set | requires `Set-PSIApplicationModel` |
| `LinkViews` | hashtable | `@{Finding='findings'; Resource='resources'; Evidence='evidence'; Check='checks'}` | replaced wholesale when supplied; Finding/Resource/Evidence (and Check for Category/Exception) must be valid ids |
| `Assessment` | ApplicationAssessment or null | set for Check/Category/Exception | requires `Set-PSIApplicationAssessment` |
| `FilterProperties` | string[] | `@()` | per-property `<select>` filters |

Badge status per item: Check/Category -> `Resolve-PSIAssessmentStatus` (Ready->Healthy, Review->Warning,
Blocked->Critical, NotTested->NotChecked, NotApplicable->Neutral, Unknown->Unknown; throws otherwise);
Exception -> Approved->Informational, Pending->Warning, Expired->Critical, Revoked->Neutral; others ->
`Resolve-PSIStatus -AllowInvalid` (no badge if not a status). Badge text is the raw value for
Check/Category/Exception and the canonical status otherwise (`ConvertTo-PSIExplorerHtml.ps1:39-48`).

Entity explorers add `data-psi-entity-id = Record.Id` (plus `data-psi-category-id` for Check). Each
FilterProperty adds `data-psi-filter-<lowercased name>="<value>"` to items; the select options are distinct
non-blank values, sorted. Detail panels: Finding/Resource/Evidence -> `ConvertTo-PSIIntelligenceDetailHtml`;
Check/Category -> `ConvertTo-PSIAssessmentDetailHtml`; Exception -> `ConvertTo-PSIAssessmentExceptionHtml`;
otherwise a `<dl>` of DetailProperties (null/blank -> em dash). Detail views link other records with
`<button data-psi-cross-view="<LinkViews[kind]>" data-psi-cross-id="<id>">` (`ConvertTo-PSIIntelligenceLinksHtml.ps1`).
First item is selected; others hidden.

Detail content per kind (fields read):
- Finding: `Title, Severity (badge; Info -> informational class), Status, Category, Summary,
  AffectedResourceIds (-> Resource view), ReadinessImpact ("Observed impact"), Recommendation.ExpectedState,
  EvidenceIds (-> Evidence view), Recommendation.Action/Rationale, Validation.Method/ExpectedResult,
  Relationships (ids -> "Type: Source -> Target")`.
- Resource: `Name, Type, Status (canonical badge; throws on invalid), Description, Properties (sorted keys),
  FindingIds, EvidenceIds, RelationshipIds (-> the other endpoint resource)`.
- Evidence: `Title, Type, Source, CollectedAt (yyyy-MM-dd HH:mm), Summary, Data (<pre>, JSON depth 8 unless
  string), ResourceIds, FindingIds`.
- Check: `Name, Status (raw text, canonical class), Weight, Description, Category name, IsBlocking,
  ObservedState, ExpectedState, ResourceIds, FindingIds, EvidenceIds, Recommendation.Action,
  Validation.Method/ExpectedResult, Frameworks`.
- Category: `Name, Icon, Status, Weight, Description, Score, CheckIds (-> LinkViews.Check)`.
- Exception: `Title, Status, Description, Reason, Owner, ApprovedBy, ApprovedAt, ExpiresAt` ("Expires within
  seven days" when Approved and `GeneratedAt < ExpiresAt <= GeneratedAt+7d`), `CheckId, FindingId, ResourceIds`.

In multi-view reports with a model, `Assert-PSIApplicationLinks` requires that every LinkViews target actually
used by data exists and contains an Explorer of the matching EntityType (`Assert-PSIApplicationLinks.ps1`).

### 3.15 Tree / Topology / RelationshipExplorer (`Add-PSITree.ps1`, `Add-PSITopology.ps1`, `Add-PSIRelationshipExplorer.ps1` -> `Private\Add-PSIRelationshipComponent.ps1`)

Requires Application layout with views and an ApplicationModel. Component Properties
(`Add-PSIRelationshipComponent.ps1:29-31`):

| Key | Type | Default |
|---|---|---|
| `Id` | string (Id pattern, unique) | mandatory |
| `Title` | string | mandatory |
| `Presentation` | `{Nodes[], Edges[], Diagnostics[]}` | from `Resolve-PSIRelationshipPresentation` at **add time** |
| `LinkViews` | hashtable | `@{Resource='resources'; Finding='findings'; Evidence='evidence'}` |
| `MaxNodes` | int 1-500 | 100 (only Topology exposes it) |
| `FilterProperties` | string[] | `@()` (only Topology exposes it; each must be in DetailProperties and match `^[A-Za-z][A-Za-z0-9_]{0,63}$`) |

Node spec input (optional `-Nodes`; default = every model resource): `NodeId|Id, ResourceId (default NodeId),
Label, NodeType, Status, Icon, Description, ParentId, SortOrder (int >= 0), IsExternal, EvidenceOnly`.
Nodes without a model resource are dropped unless `IsExternal` and `EvidenceOnly`.

Normalized node (`Resolve-PSIRelationshipPresentation.ps1:63-68`): `{Id, ResourceId ('' if external), ParentId,
Name, Type, Status (canonical, default Unknown), Icon (strict, fallback ResourceServer / Relationship for
external), Description, SortOrder, External, EvidenceOnly, Details:[{Label, Value}], Findings:[{Id, Label}],
Evidence:[{Id, Label}]}`. Details come from `Resource.Properties[DetailProperty]`, skipping names matching
`password|secret|token|credential|private.?key|auth|bearer`, dictionaries, nulls and blanks; arrays joined with
`, `; label camel-case split. Missing parents and self-parents become roots; cycles are broken; each repair
adds a Diagnostics string. Nodes sorted by `SortOrder, Name`.

Edge spec input (default = `Model.Relationships`): `Id, SourceId|SourceResourceId, TargetId|TargetResourceId,
Type (default 'related-to'), Label (default Type), Direction (Directed|Bidirectional, default Directed),
Status (canonical, default Unknown), Category, Description (fallback Impact), IsExternal, EvidenceOnly,
FindingIds, EvidenceIds`. External evidence-only endpoints auto-create nodes `{Type='External endpoint',
Icon='Relationship', SortOrder=9999}`. `Severity` and `DisplayWeight` are not used by the presentation.

Markup: JSON `{Nodes, Edges, LinkViews, Diagnostics}` in `<script type="application/json" data-psi-rel-data>`
with `& < > U+2028 U+2029` escaped as `\uXXXX`; `<template data-psi-rel-icon>` per icon; filter selects for
node type, status (+ detail filters for FilterProperties), relationship type, category; Tree renders nested
`role="tree"` list server-side; Topology renders an empty SVG filled by JS; all modes render a relationship
list. `data-psi-rel-mode` = `Tree | Topology | Explorer`, `data-psi-rel-max` = MaxNodes.

---

## 4. Status model

Canonical values and alias (`PSInsightHTML.psm1:7-16`): `Healthy, Warning, Critical, Informational, Neutral,
Unknown, NotChecked`; alias `Info -> Informational`. `Resolve-PSIStatus` trims, matches case-insensitively,
returns the canonical spelling, throws on anything else unless `-AllowInvalid` (returns `$null`)
(`Resolve-PSIStatus.ps1`). The same contract is injected into the page as `window.PSIStatus.normalize`
and `classSuffix` (`ConvertTo-PSIHtml.ps1:805-826`).

Class suffix: lower-case canonical, except `NotChecked -> not-checked`. Used as `psi-status-<suffix>`,
`psi-row-status-<suffix>`, `psi-cell-status-<suffix>`.

Other vocabularies that map onto presentation:

| Mapper | Input -> output |
|---|---|
| `Get-PSIStatusPresentation` (`Get-PSIStatusPresentation.ps1`) | healthy, ready -> class same, icon SeveritySuccess; warning, review -> SeverityWarning; critical, blocked -> SeverityError; info, informational, unknown, neutral -> SeverityInfo; notchecked -> `not-checked`, nottested -> `not-tested`, notsupported -> `not-supported`, na -> `na` (all SeverityInfo). Keys are whitespace-trimmed lower-case, so `Not Tested` (with space) is not recognized. Used by Sparkline, compact-fluent table cells, shell Resource Explorer. |
| App severity icon (`ConvertTo-PSIHtml.ps1:198-206`) | Healthy/Warning/Critical -> Success/Warning/Error; anything else -> SeverityInfo (Finding, Status, Alert, Recommendation in Application layout) |
| `Resolve-PSIAssessmentStatus` | Ready->Healthy, Review->Warning, Blocked->Critical, NotTested->NotChecked, NotApplicable->Neutral, Unknown->Unknown |
| Exception status (Explorer) | Approved->Informational, Pending->Warning, Expired->Critical, Revoked->Neutral |
| Category tile class (AssessmentOverview) | Ready->healthy, Review->warning, Blocked->critical, NotTested->not-checked, other->neutral |
| Assessment decision -> OverallStatus | Ready->Healthy, ReadyWithReview/ReviewRequired->Warning, NotReady->Critical, Incomplete->NotChecked, else Unknown |
| Global search badge (`psi-search.js:103-109`) | regex: critical/blocked->critical, warning/review/pending->warning, ready/healthy/resolved/approved->healthy, not tested/unknown/not checked->not-checked, else `info` |
| Resource workspace JS tones (`psi-resource-workspace.js:32-42`) | healthy/ready, warning/review, critical/blocked, else info; class `psi-status-<raw lower-case>` |
| Relationships JS label | `NotChecked` displayed as `Not Tested` (`psi-relationships.js:18`) |

Ranking order used for findings: `Critical, Warning, Unknown, NotChecked, Informational, Healthy, Neutral`
(overall status, overview top findings, findings explorer).

### Icons (`Get-PSIIcon.ps1`)

Two sets, looked up with case-insensitive hashtable keys:
- Fluent (file-backed SVG, `Regular`/`Filled` variants): `NavigationHome, NavigationSearch, Menu, AppSettings,
  ThemeLight, ThemeDark, Document, AppChevron, AppClose, SeverityWarning, SeverityError, SeveritySuccess,
  SeverityInfo, ResourceServer, SecurityShield, Relationship, Rules, Export`.
- Legacy stroke icons: `dashboard, server, domain, replication, security, certificate, users, cloud, database,
  network, warning, critical, info, healthy, settings, search, arrow, close, theme/light, theme/dark, file,
  print, chevron`.
`-Strict` (views, nav items, view commands, EmptyState, Category, Resource Explorer nodes, relationship
nodes) throws on unknown names; non-strict (KPI, Insight, detail headings) falls back to `dashboard`.
Legacy names pass "strict" checks even where Fluent Regular/Filled variants are requested.

---

## 5. Filtering semantics (two separate operator sets)

### 5.1 Table presentation conditions (server-side, PowerShell)

Shape (`New-PSICondition.ps1:61-67`): `{Property, Operator, Value, Status (canonical), Scope: 'Cell'|'Row' (default Cell)}`.
Operators: `Equals, NotEquals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual, Contains, Match,
IsNull, IsNotNull`. `Value` is required except for IsNull/IsNotNull; `Match` patterns are validated with
`IgnoreCase` at creation. Only affects CSS classes; never filters rows.

Evaluation (`Test-PSICondition.ps1`, `Compare-PSIConditionValues.ps1`); `Actual` is the raw CLR value from the
record (case-insensitive property lookup), not the rendered text:

| Operator | Behaviour |
|---|---|
| `IsNull` / `IsNotNull` | `$null` test only; empty string is not null |
| `Contains` | false if Actual is null or a non-string enumerable; otherwise ordinal **case-insensitive** substring of `[string]` values. Because of PowerShell `-and/-or` left-to-right precedence (`:17`), a null `Value` with a string Actual is **not** rejected and matches (`IndexOf('')=0`) |
| `Match` | null either side -> false; `[regex]::IsMatch(Actual, Value, IgnoreCase)`; invalid pattern -> false |
| any comparison with a null side | `Equals` true iff both null; `NotEquals` true iff exactly one null; others false |
| `Equals`..`LessThanOrEqual` | `Compare-PSIConditionValues`, in order: (1) if either side is bool: other side must be bool or a string parseable by `bool.TryParse` (`True`/`False`, case-insensitive), compare false<true; (2) if both `[string]` forms parse as `decimal` with `NumberStyles.Float` + InvariantCulture (no thousands separators) -> numeric compare; (3) if both are DateTime/DateTimeOffset/string and both parse as `DateTimeOffset` (invariant, AllowWhiteSpaces, AssumeUniversal) -> UTC compare; (4) if both strings -> `OrdinalIgnoreCase` compare; (5) otherwise incomparable -> **every** operator (including NotEquals) returns false |

No status-alias normalization: `Equals 'Info'` does not match `Informational`. First matching condition per
row (Row scope) and per column (Cell scope) wins.

### 5.2 Evidence / interactive filter conditions (client-side, `psi-table.js:9-38`)

Operator set: `Equals (default), NotEquals, GreaterThanOrEqual, LessThan, IsEmpty, IsNotEmpty, Contains, In`
(validated in `Resolve-PSIEvidenceDefinition.ps1:49` and `Add-PSIInsight.ps1:77`). Condition keys accepted:
`Property|property`, `Operator|operator`, `Value|value`, `Values|values`.

`value` is the **rendered cell text** read from the DOM (`textContent.trim()`), or `null` for
`psi-null-value` cells (`psi-table.js:63-73`); `text = value ?? ''`.

| Operator | Behaviour |
|---|---|
| `Equals` (also any unrecognised operator) | `equalValue(text, expected)`: if both `PSIStatus.normalize` to a canonical status compare canonical (so `Info` == `Informational`); else `String(a).toLocaleLowerCase() === String(b).toLocaleLowerCase()`. `expected` null/undefined becomes `'null'`/`'undefined'` |
| `NotEquals` | `!equalValue` |
| `In` | any of `Values` passes `equalValue` |
| `IsEmpty` / `IsNotEmpty` | `text.trim() === ''` / `!== ''` (null counts as empty) |
| `GreaterThanOrEqual` / `LessThan` | `text !== ''` and both `Number(text)` and `Number(expected)` finite; numeric compare. `Number('1,234')` is NaN; `Number(null)` is 0 |
| `Contains` | case-insensitive substring of `String(expected)` |

All conditions are AND-ed. There is no `GreaterThan`, `LessThanOrEqual`, `Match` or `IsNull` in this set.

Table UI filter controls use a separate, simpler test: lower-cased exact match of the cell text against the
selected option values, null never matches (`psi-table.js:207-218`). Row search is a lower-case substring of
the whole row `textContent`.

### 5.3 Evidence definition (`Resolve-PSIEvidenceDefinition.ps1`)

Input filter forms accepted for `New-PSIFinding -EvidenceFilter` / Insight `-Filter`:
- `@{ Table='t'; Conditions=@(@{Property; Operator; Value|Values}, ...) }`
- `@{ Table='t'; Property='p'; Operator='Equals'; Value=v }` (shorthand; `Operator='In'` uses `Values`)
- `@{ Table='t' }` (no conditions = all records)
`Table` and `EvidenceTableId` must agree when both are given; a filter without any table throws.

Output JSON (embedded as `data-psi-insight`):
```
{ "tableId": string, "conditions": [ {Property, Operator, Value|Values}... ],
  "evidenceColumns": string[], "exportColumns": string[], "labels": {}, "useVisibleColumns": bool }
```
Finding: `evidenceColumns = exportColumns = EvidenceColumns`, `labels = {}`, `useVisibleColumns = true`.
Insight: `evidenceColumns = EvidenceColumns`, `exportColumns = ExportColumns`, `labels = ColumnLabels`,
`useVisibleColumns = false`.

### 5.4 Summary of the filter-carrying shapes

| Producer | Attribute | JSON keys |
|---|---|---|
| KPI `-Filter` | `data-psi-filter-action` | verbatim: `Table, Property, Value` or `Values` (JS also accepts `tableId, property, value, values`) |
| KPI `-Action` FilterTable | `data-action` | `Type, Target, Property, Value` |
| Chart `FilterMetadata` | `data-psi-chart-filter` | `tableId, property, value` (string) |
| Finding evidence / Insight | `data-psi-insight` | evidence definition (5.3) |
| Event `psi:apply-filter` | `detail` | `tableId, property, value, values, conditions, source` |

---

## 6. Finding and Application model shapes

### 6.1 Legacy report Finding (`New-PSIFinding.ps1:45-59`)

`{Id (sanitized, generated when blank), Title (mandatory), Status (canonical, mandatory), Category,
Description, AffectedObject, Impact, Recommendation (string), RuleId, Source, EvidenceTableId, EvidenceFilter
(hashtable), EvidenceColumns (string[])}`. All strings default `''`. `Add-PSIFinding` accepts any object with
these properties (looked up case-insensitively).

### 6.2 Application model records (`New-PSIContractObject.ps1`)

All four constructors take a hashtable; unknown keys throw; `Id` must match the Id pattern; list fields
default `@()` with nulls removed; `Metadata`/`Properties` default `@{}`; other missing fields `$null`. Output
is a PS object with fields in the order below.

| Kind (cmdlet) | Fields (required in bold) | Field rules |
|---|---|---|
| Finding (`New-PSIApplicationFinding`) | **Id, Title, Severity, Status**, Summary, Category, Subcategory, ReadinessImpact, Frameworks[], AffectedResourceIds[], EvidenceIds[], Recommendation{}, Validation{}, Owner, RemediationState, Relationships[] (relationship ids), Tags[], Metadata{} | Severity in `Critical, Warning, Info, Healthy, Unknown`; Status in `Open, Acknowledged, Resolved, AcceptedRisk, NotApplicable, NotTested`; Recommendation keys subset of `Summary, Rationale, Priority, Action, ExpectedState, ChangeImpact, RequiresRestart, RequiresReboot, Validation, References, AutomationHint`; Validation keys subset of `Method, Description, ExpectedResult, Command, EvidenceRequired, Status` |
| Resource (`New-PSIResource`) | **Id, Name, Type, Status**, Description, Properties{}, FindingIds[], EvidenceIds[], RelationshipIds[], Tags[], Metadata{} | Status must resolve as a canonical status but is **stored as supplied** (not canonicalized) |
| Evidence (`New-PSIEvidenceRecord`) | **Id, Title, Type, Source**, CollectedAt, Summary, Data, FindingIds[], ResourceIds[], Tags[], Metadata{} | CollectedAt must be DateTime when present |
| Relationship (`New-PSIRelationship`) | **Id, SourceResourceId, TargetResourceId, Type**, Direction, Status, Impact, FindingIds[], EvidenceIds[], Label, Severity, Category, Description, IsExternal, EvidenceOnly, DisplayWeight, Metadata{} | Direction `Directed` (default, written back into the input hashtable) or `Bidirectional`; Status/Severity canonical if present; DisplayWeight a ValueType >= 0; IsExternal requires EvidenceOnly |

`New-PSIApplicationModel -Findings -Resources -Evidence -Relationships` (`New-PSIApplicationModel.ps1`) returns
`{Findings[], Resources[], Evidence[], Relationships[], Summary}` after `Assert-PSIApplicationModel`
(unique ids per kind, case-insensitive; all cross references resolvable:
Finding.AffectedResourceIds/EvidenceIds/Relationships, Resource.FindingIds/EvidenceIds/RelationshipIds,
Evidence.FindingIds/ResourceIds, Relationship.Source/TargetResourceId/FindingIds/EvidenceIds; an external
evidence-only relationship may have one unknown endpoint if the other is known).

`Summary`:
```
{ FindingsBySeverity: {<value>: count}, FindingsByCategory: {...}, FindingsByStatus: {...},
  ResourcesByStatus: {<raw status>: count},
  ResourcesWithCriticalFindings: int   # distinct AffectedResourceIds of Severity=Critical findings (any Status)
  EvidenceCount: int }
```
`Set-PSIApplicationModel` re-asserts but does not recompute Summary.

### 6.3 Application assessment (`New-PSIApplicationAssessment.ps1`, `New-PSIAssessmentContractObject.ps1`)

Definition keys allowed: `Id, Name, Description, AssessmentType, Target, Profile, Scope, GeneratedAt,
Categories, Checks, FindingIds, ResourceIds, EvidenceIds, Recommendations, Exceptions, Metadata,
ReadyScoreMinimum (default 90), ReviewScoreMinimum (default 75)`; computed fields are rejected.
Required non-empty: `Id, Name, AssessmentType, Target, Profile`; `GeneratedAt` DateTime (default now);
thresholds `0 <= Review <= Ready <= 100`; at least one category and one check (`Assert-PSIApplicationAssessment.ps1`).

Output object:
```
{ Id, Name, Description, AssessmentType, Target, Profile, Scope, GeneratedAt,
  OverallStatus, Score, Decision,                # computed
  Categories[], Checks[], FindingIds[], ResourceIds[], EvidenceIds[], Recommendations[] (strings),
  Exceptions[], Metadata{}, Thresholds {Ready, Review}, ScoreExplanation }   # computed
```
Metadata keys read by renderers: `EvidenceCoveragePercent`, `Print`, `PrintDisplay`, `CollectionCounts`.

| Kind | Fields (required in bold) | Rules |
|---|---|---|
| Category (`New-PSIAssessmentCategory`) | **Id, Name**, Description, Icon (default `Document`, strict), Weight (default 1.0, > 0, finite), Status, Score, CheckIds[], FindingIds[], ResourceIds[], Metadata{} | Score/Status may not be supplied; they are written by the posture engine |
| Check (`New-PSIAssessmentCheck`) | **Id, Name, CategoryId, Status**, Description, Severity, Weight (default 1.0), IsBlocking (default false), ObservedState, ExpectedState, FindingIds[], ResourceIds[], EvidenceIds[], Recommendation{}, Validation{}, Frameworks[], Tags[], Metadata{} | Status in `Ready, Review, Blocked, NotTested, NotApplicable, Unknown`; Severity in finding severity set; nested dict keys as for Finding |
| Exception (definition hashtables in `Exceptions`) | **Id, Title, Reason, Status**, Description, CheckId, FindingId, ResourceIds[], Owner, ApprovedBy, ApprovedAt, ExpiresAt, Metadata{} | Status in `Approved, Pending, Expired, Revoked`; dates DateTime; Approved requires ApprovedBy+ApprovedAt; ExpiresAt > ApprovedAt |

Consistency rules: each check belongs to exactly one category, and `Category.CheckIds` must agree with
`Check.CategoryId`; with a model, every id reference must resolve and check-level Finding/Resource/Evidence
ids must also appear in the assessment-level lists.

### 6.4 Posture computation (`Resolve-PSIAssessmentPosture.ps1`)

Runs in `New-PSIApplicationAssessment` (no model), `Set-PSIApplicationAssessment` (with model) and again at
render (`ConvertTo-PSIHtml.ps1:52-54`). It **mutates** `Category.Score`, `Category.Status`, and the assessment's
`Score, Decision, OverallStatus, ScoreExplanation`.

- Check points: Ready 100, Review 50, Blocked 0, NotTested 0, Unknown 0; NotApplicable excluded.
- Category score = `round( sum(w_check * points) / sum(w_check), 1 )` over applicable checks of the category
  (`CategoryId -ieq Category.Id`); `null` when no applicable checks.
- Overall score = `round( sum(w_cat * categoryScore) / sum(w_cat), 1 )` over categories with non-null
  (already rounded) scores; `null` when none. `[math]::Round` is .NET banker's rounding (MidpointRounding.ToEven).
- Category status precedence: Blocked > NotTested > Unknown > Review > Ready > NotApplicable.
- Counts: per check status totals, `Blockers` = checks with `IsBlocking` and status Review or Blocked,
  `CriticalFindings` = model findings in `Assessment.FindingIds` with Severity Critical and Status not
  Resolved/AcceptedRisk/NotApplicable (0 when no model).
- Decision: `NotReady` if Blockers>0 or CriticalFindings>0 or Blocked>0; else `Incomplete` if NotTested>0;
  else `Unknown` if Unknown>0 or Score null; else `Ready` if Score >= Ready threshold and Review==0; else
  `ReadyWithReview` if Score >= Review threshold; else `ReviewRequired`.
- Exceptions never change the posture.
- `ScoreExplanation`:
```
{ CategoryScores: [ {Id, Name, Score, Weight, Status, CheckCount, ApplicableCheckWeight,
                     Counts {Ready, Review, Blocked, NotTested, NotApplicable, Unknown},
                     WeightedContribution (round(w*score, 2) or null)} ],
  Counts {Ready, Review, Blocked, NotTested, NotApplicable, Unknown, Blockers, CriticalFindings},
  Reasons: string[] (fixed English sentences in the order blockers, critical findings, blocked,
                     not tested, unknown, review, not applicable; or "All applicable checks are ready."),
  CheckPoints {Ready=100, Review=50, Blocked=0, NotTested=0, Unknown=0, NotApplicable='Excluded'},
  CategoryFormula: string, Thresholds, ExcludedCategoryCount }
```

### 6.5 Global search index (`Get-PSIApplicationSearchIndex.ps1`)

Built only for multi-view reports (`ConvertTo-PSIApplicationShell.ps1:87-112`), embedded as
`<script type="application/json" id="psi-global-search-index">` with the same `\uXXXX` escaping. Items:
```
{ Id, EntityType: 'View'|'Check'|'Finding'|'Resource'|'Evidence'|'Exception', Title, Subtitle, Keywords,
  Status, Severity, ViewId, TargetId, Category, Icon }
```
- One `View` item per view (`Category = Group`, `Keywords = ''`).
- One item per record of each Explorer whose EntityType is in the list above (Category explorers are not
  indexed), de-duplicated by `EntityType:Id` (first view wins). Title from `TitleProperty` (`(unnamed)`),
  Subtitle from `SubtitleProperty`, Category = record `Category` (Check: category name; Resource/Evidence
  fallback `Type`), Keywords = first 8 Tags + description (Check/Resource/Exception `Description`, others
  `Summary`, truncated to 180 chars). Icons: Check `Rules`, Finding `SeverityWarning`, Resource
  `ResourceServer`, Evidence `Document`, Exception `SeverityInfo`.

### 6.6 Shell Resource Explorer (`Add-PSIResourceExplorer.ps1`)

Requires Application + FluentExplorer; one per report. Node input keys: `Id` (Id pattern, unique), `Label`
(required), `ParentId`, `Icon` (default `ResourceServer`, strict), `Target` (view id; checked against Views at
render), `Count` (int >= 0 or null), `Metadata` (dictionary), `Status` (canonical, default Unknown),
`Selectable` (default true), `Expandable` (default false), `Type` (default `Resource`). Normalized node adds
`Depth` (0-based, max 32); `Expandable` is forced true when the node has children; parents must exist; cycles
throw. `SelectedId` defaults to the first selectable node.

### 6.7 Context Inspector (`Add-PSIInspector.ps1`)

Requires the Resource Explorer; one per report; Id must differ from the explorer Id. Each item:
```
{ Id, ResourceId (must be an explorer node; unique), Title, Subtitle, Status (canonical, default Unknown),
  Properties: [{Label, Value(string)}]   # from a dictionary
  Metadata:   [{Label, Value(string)}]   # from a dictionary; shown as header tags
  Sections:   [{Id (Id pattern, not 'Properties', unique), Title (default Id),
                Blocks: [{Title, Text, Status (free text), ResourceId, TargetView, ActionLabel}]}],
  Breadcrumb: string[], Actions: [{Label, TargetView, ResourceId}] }
```
Serialized as a JSON object keyed by `ResourceId` into `<script id="psi-resource-data">`
(`ConvertTo-PSIResourceWorkspace.ps1:82-85`).

---

## 7. Client interactions to preserve

### 7.1 Theme
Buttons `[data-psi-theme=Light|Dark|Auto]` set `html[data-theme]`, update `aria-pressed`, the
`[data-psi-theme-value]`/`[data-psi-theme-footer]` labels, and persist to `localStorage['psi-report-theme']`;
the stored value overrides `Report.Theme` on load (`psi-interactions.js:4-29`).

### 7.2 Evidence dialog (`psi-interactions.js:336-575`)
Opened by any `[data-psi-insight]` (Insight buttons, Finding "View Evidence"):
1. dataset = all records of the referenced table (`PSIDataEngine.getRecords(tableId)`), built from the
   rendered DOM: values are cell text, null cells null (`psi-table.js:59-74`).
2. records = dataset filtered by `definition.conditions` + the table's current external conditions + its
   current filter-control selections (as `In` conditions) + its current search text (row text contains).
   The description gets "Evidence also reflects the inventory filters and search already in use." when any
   of those contributed.
3. columns = `evidenceColumns` if non-empty, else the table's visible columns when `useVisibleColumns`;
   export columns = `exportColumns` if non-empty, else the same columns when `useVisibleColumns`. Both are
   filtered to names that exist (case-sensitive) in the dataset.
4. Dialog features: search across displayed columns; auto-generated Equals filter selects for every column
   with 2-24 distinct values; header click sort (numeric when both finite, else locale/numeric compare);
   page size 25; status-looking cells rendered as badges via `PSIStatus.normalize`; "Apply these filters to
   inventory" (visible only when the definition has conditions) dispatches `psi:apply-filter {tableId,
   conditions: definition + table-context + dialog selections, source:'insight'}`; CSV/XLSX/Print export of
   the filtered records (export toolbar hidden when there are no export columns); Escape, backdrop click,
   focus trap, focus restored to the trigger.
Legacy KPI DrillDown mode: records parsed from `data-psi-records`; columns = union of object keys (or `Value`
for scalars); no filters, export or apply.

### 7.3 Table (`psi-table.js`)
Search (whole-row text), select/multiselect filters with removable chips and "Clear all", external
conditions shown as chips (`<Property> <Operator> <Value>`), sorting by cell text (numeric after stripping
whitespace, `,`, `%`, `$`, GBP and EUR signs), pagination with "Showing a-b of n results", `psi:apply-filter`
handling (3.3), registration in `window.PSIDataEngine` (`datasets`, `matches`, `valueOf`, `getRecords`,
`getContext`) which the evidence dialog depends on.

### 7.4 Export (`psi-export.js`)
`window.PSIExport.attachToolbar(toolbar, provider)` with menu keyboard support. Table export uses the current
filtered + sorted result set across all pages, values from DOM text.
- CSV: UTF-8 BOM, CRLF, every field quoted, header from labels; values starting (after whitespace/BOM) with
  `= + - @` or with tab/CR/LF are prefixed with `'`.
- XLSX: minimal stored (uncompressed) ZIP with one sheet; numbers written as numeric cells when they match
  `^-?(0|[1-9]\d*)(\.\d+)?$` with at most 15 digits; booleans only for real booleans; inline strings
  otherwise; frozen header row, autofilter, column widths 14-36; sheet name sanitized, max 31 chars,
  default = context title.
- File name: `safeName(ExportFileName)` or `safeName(<first h1 text>)_safeName(<context title>)`, then
  `_YYYYMMDD-HHMM.csv|xlsx` (local time).
- Print: table print toggles `psi-print-table`/`psi-print-target`/`psi-print-section` and marks all matched
  rows; evidence print uses `psi-print-evidence`; report print uses `window.PSIPrint.print()` (Application
  layout print projection, `psi-print.js`, `ConvertTo-PSIPrintProjection.ps1`) or `window.print()`.

### 7.5 Findings explorer by AffectedObject (`psi-interactions.js:137-280`)
Per `.psi-section` with at least 2 finding cards and at least 2 distinct non-blank `data-psi-affected-object`
values: inserts a "Affected object" select before the first finding row. Groups by exact value (blank ->
`Unspecified`), sorted by best status rank, then card count desc, then label. Options `"<label> (<n>)"` plus a
final `All findings (<n>)`; the **first group is selected initially**, not "All". Hides non-matching cards,
hides rows that only contain hidden finding cards, shows "Showing x of y findings" and per-status counts,
and dispatches `psi:layout-change`.

### 7.6 Report-layout navigation (`psi-interactions.js:31-135`)
Scroll-spy on section links (`aria-current="location"`) and assessment links (`overview` or AssessmentId),
horizontal auto-reveal of the active link, `--psi-navigation-offset` CSS variable.

### 7.7 Application shell (`psi-application.js`)
- Mobile drawer (<= 900px) with scrim, Escape and focus trap.
- Non-multi-view: anchor links with scroll-spy.
- Multi-view: `activateView(id)` shows one `[data-psi-app-view]`, updates nav `aria-current="page"`,
  workspace tabs (arrow/Home/End keys), command-bar title/subtitle/context title, per-view command buttons,
  "Find in view" button (focuses the active view's explorer/table search), scrolls to top.
  `window.PSIApplication = {activateView, selectEntity(viewId, entityType, entityId)}`.
- Explorer: search on item text, exact-match property filters, roving selection with arrow/Home/End,
  `psiSelectEntity(id)` (clears search and filters), `psiFilterCategory(id)` (needs a `CategoryId` filter).
- `[data-psi-cross-view][data-psi-cross-id]` click -> activate view and select the entity; category tiles
  -> activate the check view and filter its Check explorer by category.

### 7.8 Global search / command palette (`psi-search.js`)
Ctrl/Cmd+K opens; `>` prefix or "Commands" mode switches to commands (Go to view, Theme Light/Dark/Auto,
Open Export, Find in Current View, Clear Current Filters). Scoring: all words must occur in
title/id/keywords/subtitle/category/status/severity/type; exact title 120, title prefix 95, id 90, title
contains 75, all words in title 65, keywords contain 55, else 35; +3 for critical/blocked, +2 for
warning/review; empty query lists views only; max 20 results grouped by type. Choosing a result calls
`activateView` or `selectEntity`.

### 7.9 Resource Explorer and Inspector (`psi-resource-workspace.js`)
Tree with expand/collapse, label search that reveals ancestors, keyboard navigation, selection renders the
workspace header (breadcrumb, title, subtitle, status, tags from Metadata, action buttons) and the
inspector (tabs: `Properties` + item Sections, blocks with optional action buttons that select a resource
and/or open a view). Selecting a node with `Target` opens that view. Listens for `psi:relationship-select`
`{resourceId}` to sync selection. Collapsible panes (Resources/Inspector restore buttons).

### 7.10 Relationship components (`psi-relationships.js`)
Search and filters (type, status, detail filters, edge type, category); Tree keeps ancestors of matches
visible; Topology draws a layered SVG layout (layers from `Category='Containment'` edges when present, else
all edges; 5 nodes per column; over `MaxNodes` matches shows a limit message instead of the graph) with
zoom in/out/fit/reset; node/edge detail panel with links through `LinkViews` to Finding/Evidence/Resource
explorers (`selectEntity`) and optional `Check`/`Replication` views (activates the view and searches for the
node name); dispatches `psi:relationship-select {origin, nodeId, resourceId}`.

---

## 8. Data passing between server and client (current HTML)

| Data | Where |
|---|---|
| Status contract | inline script defining `window.PSIStatus` |
| Table records | rendered `<tr>` cells only (no JSON); read back from DOM |
| Table export config | `data-psi-export-config` |
| KPI action / filter / drilldown | `data-action`, `data-psi-filter-action`, `data-psi-records` |
| Chart filter | `data-psi-chart-filter` per SVG mark |
| Evidence definitions | `data-psi-insight` |
| Relationship presentation | `script[data-psi-rel-data]` |
| Search index | `script#psi-global-search-index` |
| Inspector items | `script#psi-resource-data` |
| Icons for JS | `<template data-psi-rel-icon>`, `data-psi-search-icon`, `data-psi-resource-status-icon` |
| Fluent icon licence | `template#psi-fluent-icon-attribution` |

Scripts are included conditionally: `psi-table.js` only when a Table exists; `psi-export.js` when a Table,
an evidence button/Insight, or report print exists; relationship script only with relationship components;
search script only in multi-view; print script only with `EnableReportPrint` in Application layout.

---

## 9. Inconsistencies, legacy aliases and gotchas

1. **Stale bundle / hard-coded versions.** `PSInsightHTML.Bundle.ps1:6670` hard-codes `ModuleVersion =
   '0.10.0'` and lists 94 sources; the manifest says `0.11.2`. The psm1 loads the bundle only if its
   fingerprint matches (`PSInsightHTML.psm1:80-93`). README, `docs/Known-Limitations.md`,
   `docs/Release-Validation.md:42` and checked-in example HTML still say 0.10.0.
2. **JSON serialization of the report object** (for a JSON-based renderer):
   - heavy duplication by reference: sections appear in `Report.Sections`, `View.Sections` and
     `Report.Assessments[].Assessment.Sections`; findings in `Report.Findings`, `Assessment.Findings` and
     each Finding component's `FindingReference`; Explorer/AssessmentOverview components embed the whole
     `Model` and `Assessment`; Tree/Topology embed a precomputed `Presentation`.
   - `ConvertTo-Json` default depth is 2; the existing renderer uses depths 3-12 for embedded fragments.
   - Windows PowerShell 5.1 serializes DateTime as `"\/Date(<ms>)\/"` (affects `GeneratedOn`, `GeneratedAt`,
     `CollectedAt`, exception dates, and already-embedded fragments such as KPI DrillDown records).
   - hashtable key order is not preserved unless `[ordered]` was used (KeyValue `Data`, Inspector
     `Properties`/`Metadata`, `ColumnLabels`).
   - PowerShell lookups are case-insensitive; JS is not. Example: a KPI Filter with key `table` passes
     validation (`$Filter.ContainsKey('Table')`) but the client only reads `Table`/`tableId`
     (`psi-interactions.js:286`).
3. **Two operator vocabularies** (5.1 vs 5.2) with different names (`IsNull` vs `IsEmpty`, `Match` only
   server-side, `In` only client-side), different inputs (raw CLR value vs rendered text) and different
   status handling (no alias normalization vs canonical-status equality).
4. **Rendered text is the data.** Client filtering, evidence and export read cell text, so status
   canonicalization (`info` -> `Informational` in normal mode), JSON-stringified complex values,
   `[string]` DateTime formatting and `NullValueText` all flow into evidence matching and CSV/XLSX output.
   Compact fluent mode keeps the original status text instead.
5. **Insight without EvidenceColumns shows no columns.** Insight definitions use `useVisibleColumns=false`
   (`ConvertTo-PSIHtml.ps1:408-411`) and the dialog only falls back to visible columns when that flag is set
   (`psi-interactions.js:492-503`). Evidence column names must match table column names case-sensitively.
6. **Evidence includes the table's live state** (filters, external conditions, search), not just the
   definition's conditions.
7. **Five filter payload shapes** (5.4) with different key casing (`Table/Property/Value` vs
   `tableId/property/value`). KPI `Values` only takes effect on a matching filter control; with no control the
   fallback needs a scalar `value` (`psi-table.js:309-320`). Filter-control matching on `property` is
   case-sensitive, column fallback is case-insensitive.
8. **KPI with both Filter and DrillDown** triggers both the table filter and the drilldown dialog. KPI
   `data-action` is ignored when either is present.
9. **Span inconsistencies.** KPI default 3, KeyValue 6, Table 12, Sparkline 3; Insight has no Span (auto from
   row); Chart, Text, Status, Alert, Recommendation, Finding, Explorer, AssessmentOverview and relationship
   components have none and use the row's `Columns`. `Row.Columns` is not a grid column count.
10. **Status vocabularies.** Canonical statuses vs finding `Severity` (`Info`, not `Informational`) vs finding
    `Status` (`Open`...) vs check status (`Ready`...) vs exception status vs decision values. Class names differ
    for the same meaning: `informational` (canonical) vs `info` (`Get-PSIStatusPresentation`, search badges);
    `not-checked` vs `not-tested`. `ConvertTo-PSIResourceWorkspace.ps1:47` and `psi-resource-workspace.js:31`
    use `psi-status-<raw lower-case>` so `NotChecked` yields `psi-status-notchecked`. Resource/Relationship
    model records keep the status text as supplied (aliases and casing are not canonicalized).
11. **Two Recommendation shapes.** Legacy `New-PSIFinding.Recommendation` is a string; application finding and
    check `Recommendation` is a dictionary.
12. **Icon sets.** Fluent role names and legacy stroke names coexist; strictness differs per component; KPI
    icons silently fall back to `dashboard`; the overview uses legacy names (`critical`, `warning`, `info`,
    `dashboard`).
13. **Cross-view links pick the first entity explorer** in the target view regardless of entity type
    (`psi-application.js:238`), whereas global search uses `selectEntity` with the type. Category tiles only
    filter when the Check explorer has `FilterProperties` containing `CategoryId` (`psi-application.js:192-200`).
14. **Relationship JS knows `Check` and `Replication` LinkViews** (`psi-relationships.js:27-31,115-123`) that
    the cmdlet defaults do not include and do not validate; `Category='Containment'` drives topology layout.
15. **Multi-view incompatibilities.** `Add-PSIAssessment` adds sections without `ViewId`, and
    `Add-PSIReportOverview` moves its section to index 0; both break the "sections contiguous per view"
    check in `Resolve-PSIApplicationNavigation.ps1:70-85`.
16. **Posture details.** Overall score averages already-rounded category scores; .NET banker's rounding;
    the overview "Blockers" tile counts only blocking checks + critical findings, while "Top blockers" lists
    any `Blocked` check. `ResourcesWithCriticalFindings` ignores finding Status whereas `CriticalFindings`
    excludes resolved/accepted/not-applicable. Posture is recomputed (and mutated in place) at every render.
17. **Server condition edge cases.** `Contains` with a null Value matches every non-null string (operator
    precedence, `Test-PSICondition.ps1:17`); incomparable values make `NotEquals` false.
18. **Finding evidence vs Insight evidence.** A Finding with a missing evidence table drops the button with a
    warning; an Insight with a missing table still renders a clickable card, which opens an empty dialog (or does
    nothing when the report has no tables, because `window.PSIDataEngine` comes from `psi-table.js`).
19. **Findings explorer** defaults to the first affected-object group rather than "All findings", so some
    findings are hidden on load.
20. **Export filename** uses the first `<h1>` text, which in multi-view is the active view title, not the
    report title.
21. **`Get-PSIStatusPresentation` keys** are lower-cased with spaces kept, so `Not Tested` and `N/A` are not
    recognized, while `NotTested` and `NA` are.
22. **Alert `Details`** uses `IsPrimitive` (DateTime and decimal become JSON), while every other value
    formatter uses `IsValueType`.

# Architecture

## Generic framework

The root `Public/`, `Private/`, and `Assets/` directories implement the presentation engine. Public commands create or extend generic PowerShell objects. Private helpers validate those objects, resolve status and evidence definitions, render HTML, and embed local CSS and JavaScript. The manifest explicitly lists exported commands; the loader imports private helpers before public commands. No technology-specific collector belongs in the generic renderer.

The object structure is `Report → Sections → Rows → Components`. A report also holds composed assessment metadata and findings. A component has a `Type` and a properties hashtable. Component commands mutate the current report or assessment and return the same object, allowing pipeline composition. `Export-PSIReport` is the file-writing boundary.

## Assessment layer

`New-PSIAssessment` creates an assessment with its own sections and findings. `Add-PSIAssessment` validates IDs and appends those sections and findings to a report. Compose an assessment before adding it to a report; treat it as immutable afterward. Summary commands derive counts and overall status. `Add-PSIReportOverview` builds the overview from that derived summary without copying evidence records.

## Findings and evidence

`New-PSIFinding` defines a structured status, explanation, optional recommendation, and optional reference to a table ID, filter, and columns. `Add-PSIFinding` adds the finding to the assessment or report and renders a card. A finding's evidence action resolves against an existing table dataset; the shared evidence dialog applies its filter and supports search, sorting, pagination, and export. KPI and insight drill-downs use the same interaction layer. DOM IDs and evidence references are validated before output.

## Conditional formatting

`New-PSICondition` declares a property, comparison, status, and Cell or Row scope. Tables evaluate rules in order and use the first matching rule for the relevant cell or row. This changes presentation only. Provider-specific thresholds and interpretations must be calculated in the provider layer before calling the generic component commands.

## Renderer and interactions

`Private/ConvertTo-PSIHtml.ps1` traverses the report object and emits semantic HTML for each component type. `Assets/CSS/psi-theme.css` defines Light, Dark, Auto, and print tokens; `Assets/CSS/PSInsightHTML.css` supplies component layout and visual rules. Browser behavior is vanilla JavaScript under `Assets/JavaScript/`: theme choice, navigation, table controls, chart-point filtering, evidence dialog, and export. The renderer embeds these assets directly into the HTML. Inline SVG charts and icons require no external file, CDN, or `fetch()` call.

## Provider layer

`Providers/<Provider>/<Report>/` contains capability metadata, one exported public entry point, and private data preparation and report composition. Provider implementations are loaded when their command runs, not at generic module import. The current Active Directory providers use fictional sample data; User Inventory can also read a supplied workbook. Provider-specific rules, thresholds, source fields, and collection dependencies stay here. See [ProviderArchitecture.md](ProviderArchitecture.md) for the directory contract.

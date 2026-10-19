# Application search and commands

Multi-view `Application` reports include a global search control in the command bar. Click **Search assessment**, or press **Ctrl+K** (Windows/Linux) or **Cmd+K** (macOS). The separate **Find in view** control focuses the active view's table or collection search when one exists.

Global search covers registered views and rendered Check, Finding, Resource, Evidence, and Exception explorers. It ranks exact titles first, then title prefixes, exact IDs, title tokens, keywords, and descriptive context. Status and severity remain visible in results. Results are capped at 20 with a count when more matches exist. Selecting an entity switches views and selects its existing explorer record; selecting a view switches to it directly. The search stays in memory and never reloads the report.

The index is generated once during export from the application views and explorer records. It contains IDs, display titles, short subtitles, category, status, severity, tags, and a short approved description or summary. Raw evidence `Data`, resource `Properties`, arbitrary `Metadata`, and nested action payloads are not indexed. Report authors remain responsible for deciding which records and display fields belong in the report. The index is embedded in the standalone HTML, so any indexed value is visible to a reader who has the file. Search history is not stored.

Use the **Commands** tab, or type `>` in the search field, to find generic actions. The command registry is built from available views plus theme, export, and active-view search actions. **Find in Current View** appears only when the active view has a search input; **Clear Current Filters** appears only while a local filter or search is active. Commands do not execute remediation.

Use **Up** and **Down** to change the active result, **Enter** to open it, and **Escape** to close the dialog and return focus to the invoking control. The palette is a labeled dialog with a combobox and listbox; mouse and touch selection also work. It uses the report's Light, Dark, and Auto tokens and fits narrow screens.

This feature is limited to multi-view Application reports. Legacy Report layout and single-document Application layout keep their existing navigation. Search does not inspect unrendered records, hidden fields, or full raw evidence payloads. It is substring/token matching rather than fuzzy matching; no network request or external library is used.

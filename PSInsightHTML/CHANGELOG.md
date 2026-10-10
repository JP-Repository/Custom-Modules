# Changelog

## 0.10.0

- Added sticky generic report section navigation with active-section tracking, accessible current-location state, dynamic anchor offsets, and composed-assessment navigation support.
- Refined KPI interaction feedback with a restrained lift, keyboard focus treatment, pointer-aware hover behavior, reduced-motion support, and static print output.
- Added severity-aware Finding recommendation treatments using the existing canonical status tokens and print-readable borders.
- Added a generic client-side Findings Explorer based on `Finding.AffectedObject`, including priority-based defaults, counts, status summaries, `Unspecified` and `All findings` options, independent section controls, accessible native selection, and complete print output.
- Preserved the existing public command surface, Finding schema, standalone HTML model, and no-JavaScript fallback.

## 0.9.1

- Made executable PowerShell source and embedded CSS/JavaScript runtime assets ASCII-safe for Windows PowerShell 5.1 decoding.
- Preserved rendered Unicode symbols through HTML entities, runtime character construction, and JavaScript/CSS escapes.
- Added source-compatibility regression tests and Windows PowerShell 5.1 release-validation guidance.

## 0.9.0

- Generic report, section, row, and component model with assessment composition and a derived report overview.
- Responsive Light, Dark, Auto, and print visual system with sticky assessment navigation.
- Searchable, sortable, filterable, paginated tables with CSV, XLSX, and print actions; declarative conditional formatting.
- Inline SVG bar, line, doughnut, and pie charts with supported chart-driven filtering.
- Structured findings, reusable evidence references, and a shared investigation dialog.
- Fictional Active Directory sample providers for User Inventory, DNS, Replication, Sites and Subnets, Groups, and Group Policy.
- Standalone HTML with embedded CSS, JavaScript, SVG icons, and no CDN dependency.

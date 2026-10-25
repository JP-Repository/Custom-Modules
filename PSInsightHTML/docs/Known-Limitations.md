# Known limitations

- Tables are DOM-backed. Large datasets increase standalone HTML size, browser memory use, initial rendering time, and client-side filter/sort cost. The 5,000-row sample is a scale demonstration, not a guarantee for arbitrary dataset sizes.
- Assessment objects share their section and finding objects with the composed report. Treat an assessment as immutable after `Add-PSIAssessment`.
- Automated visual browser inspection is not available in every development environment. Pester and HTML structure checks do not establish visual correctness across browsers, screen sizes, or print dialogs.
- Six exported integrated Active Directory provider commands remain sample/workbook workflows. The exported `Invoke-PSIADCompleteOverview` pilot command reuses the shared read-only collector for DC inventory, readiness, health, security, compliance, DNS, replication, and topology, and runs separate scoped queries for GPOs, OUs, groups, users, and computers. Live results still require a Windows pilot and domain-specific review; additional provider families remain future work.
- Historical and month-over-month comparison is future work. Current reports represent a single generated snapshot.
- Excel workbook input depends on the provider's expected worksheet and source schema. The supplied local sample workbook is intentionally excluded from Git. A fresh checkout therefore cannot run the User Inventory sample example or its workbook-dependent tests until that workbook is supplied locally.
- The manifest declares PowerShell 5.1 compatibility, but validation on a native Windows PowerShell 5.1 runtime still requires a Windows test environment.

# Provider architecture

PSInsightHTML's root `Public/`, `Private/`, and `Assets/` directories are the technology-neutral report engine. Provider-specific source interpretation, fictional data, thresholds, and report composition live under `Providers/<Provider>/<Report>/`.

Each integrated report has:

- `Report.psd1`: small, PowerShell 5.1-compatible capability metadata.
- `Public/New-*.ps1`: the exported report command and its input contract.
- `Private/Report.ps1`: the existing report composition, invoked only when the command runs.
- `Private/*.Provider.ps1`: internal data preparation and sample-data helpers.

The module loader loads root private functions, root public functions, and only `Providers/*/*/Public/*.ps1`. It does not import provider implementations or optional technology modules at module import time. The manifest explicitly lists exported commands. Adding another provider uses the same directory convention; no provider-specific loader branch is needed.

`Get-PSIReportCatalog` reads `Providers/*/*/Report.psd1` and returns objects. Metadata declares `Id`, `Provider`, `Name`, `Description`, `Category`, `Command`, `Status`, the three support flags, and `MinimumPowerShellVersion`. The catalog does not load report data. A metadata command must resolve to an exported function.

Provider commands require explicit `-UseSampleData` and accept `-Path` for output. They can also accept report-specific options such as `-Theme`, thresholds, and `-NoBrowser`. User Inventory additionally accepts `-WorkbookPath` instead of `-UseSampleData`; that workbook must contain the existing `AD_User_Accounts` worksheet and source columns consumed by its provider. The default sample workbook is local under `Examples/Data/` and is intentionally excluded from Git. The other five reports do not yet accept supplied datasets. No command silently collects live data, and `-Live` is not implemented.

The existing scripts under `Examples/` remain executable usage examples with their original parameter names. They import the module and call integrated public commands. Provider implementations are not duplicated there. Future live collection should be added within an individual provider, with dependency checks at invocation time; it must not make the generic module import depend on RSAT or another technology module.

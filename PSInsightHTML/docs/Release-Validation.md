# Release validation

Run the complete automated suite from the module directory in PowerShell 7:

```powershell
Set-Location C:\path\to\Custom-Modules\PSInsightHTML
Invoke-Pester -Path .\Tests
```

Windows PowerShell 5.1 runtime validation must run on Windows. From a Windows PowerShell 5.1 console, parse every executable module file before importing:

```powershell
$ModuleRoot = 'C:\path\to\Custom-Modules\PSInsightHTML'
$ParseErrors = @()
Get-ChildItem -LiteralPath $ModuleRoot -Recurse -File |
    Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' } |
    ForEach-Object {
        $Tokens = $null
        $Errors = $null
        [void] [System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref] $Tokens,
            [ref] $Errors
        )
        $ParseErrors += $Errors
    }
if ($ParseErrors.Count -gt 0) {
    $ParseErrors | Format-List
    throw "Windows PowerShell parsing failed for $($ParseErrors.Count) source location(s)."
}
```

Then import the manifest and verify the release version and public surface:

```powershell
$ManifestPath = Join-Path $ModuleRoot 'PSInsightHTML.psd1'
Import-Module -Name $ManifestPath -Force -ErrorAction Stop
$Module = Get-Module PSInsightHTML
$Commands = @(Get-Command -Module PSInsightHTML -CommandType Function)
$Module.Version.ToString()
$Commands.Count
if ($Module.Version.ToString() -ne '0.10.0') { throw 'Unexpected module version.' }
if ($Commands.Count -ne 30) { throw 'Unexpected exported command count.' }
```

Generate a standalone sample without opening a browser:

```powershell
$OutputPath = Join-Path $env:TEMP 'PSInsightHTML-WinPS51-Demo.html'
& (Join-Path $ModuleRoot 'Examples\New-DemoReport.ps1') `
    -OutputPath $OutputPath `
    -NoBrowser
if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw 'Sample report generation failed.'
}
```

When Pester 5 is installed on the Windows validation host, run the compatibility test and then the complete suite:

```powershell
Set-Location $ModuleRoot
Invoke-Pester -Path .\Tests\PSInsightHTML.WinPS51Compatibility.Tests.ps1
Invoke-Pester -Path .\Tests
```

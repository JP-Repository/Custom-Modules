<#
.SYNOPSIS
    Regenerates PSInsightHTML.Bundle.ps1, the fast-load bundle of all module sources.

.DESCRIPTION
    Development keeps one function per file under Private/, Public/ and
    Providers/<Provider>/<Report>/Public/. Loading ~95 separate script files is slow
    on hosts where endpoint protection scans each file as it is opened (~90 ms per
    file), so the loader prefers this single generated file when its fingerprint
    matches the current sources. Run this script after changing any source file.
    The bundle is generated output: never edit it by hand.

.EXAMPLE
    ./Build/Build-PSInsightHTML.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Path $PSScriptRoot -Parent
$BundlePath = Join-Path -Path $Root -ChildPath 'PSInsightHTML.Bundle.ps1'

# Reuse the loader's own source-set logic so build and import can never disagree.
$Loader = [System.IO.File]::ReadAllText((Join-Path -Path $Root -ChildPath 'PSInsightHTML.psm1'))
$Start = $Loader.IndexOf('function Get-PSIModuleSourceSet')
$End = $Loader.IndexOf('$SourceSet = Get-PSIModuleSourceSet')
if ($Start -lt 0 -or $End -lt $Start) { throw 'Could not locate Get-PSIModuleSourceSet in PSInsightHTML.psm1.' }
. ([scriptblock]::Create($Loader.Substring($Start, $End - $Start)))

$SourceSet = Get-PSIModuleSourceSet -Root $Root
$Builder = [System.Text.StringBuilder]::new()
[void] $Builder.AppendLine('# PSInsightHTML generated bundle - DO NOT EDIT. Regenerate with Build/Build-PSInsightHTML.ps1.')
[void] $Builder.AppendLine('# Fingerprint: ' + $SourceSet.Fingerprint)
[void] $Builder.AppendLine('# Sources: ' + $SourceSet.Files.Count)
foreach ($File in $SourceSet.Files) {
    $Text = [System.IO.File]::ReadAllText($File.FullName)
    $Tokens = $null; $Errors = $null
    [void] [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref] $Tokens, [ref] $Errors)
    if ($Errors.Count -gt 0) { throw "Parse error in $($File.FullName): $($Errors[0].Message) (line $($Errors[0].Extent.StartLineNumber))" }
    [void] $Builder.AppendLine('')
    [void] $Builder.AppendLine('#region ' + $File.FullName.Substring($Root.Length + 1))
    [void] $Builder.AppendLine($Text.TrimEnd())
    [void] $Builder.AppendLine('#endregion')
}

# ASCII-only keeps Windows PowerShell 5.1 decoding independent of BOM handling,
# matching the policy for the individual source files.
$Output = $Builder.ToString()
if ($Output.ToCharArray() | Where-Object { [int] $_ -gt 127 } | Select-Object -First 1) {
    throw 'Bundle contains non-ASCII characters; source files must stay ASCII-safe.'
}
[System.IO.File]::WriteAllText($BundlePath, $Output, [System.Text.Encoding]::ASCII)
[pscustomobject]@{
    Bundle      = $BundlePath
    Sources     = $SourceSet.Files.Count
    Commands    = $SourceSet.PublicFunctions.Count
    SizeKB      = [math]::Round((Get-Item -LiteralPath $BundlePath).Length / 1KB, 1)
    Fingerprint = $SourceSet.Fingerprint.Substring(0, 12)
}

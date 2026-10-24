$script:ModuleRoot = $PSScriptRoot
# Single source of truth for the version stamped into reports: the manifest.
$script:PSIModuleVersion = [string] $ExecutionContext.SessionState.Module.Version
if ([string]::IsNullOrWhiteSpace($script:PSIModuleVersion) -or $script:PSIModuleVersion -eq '0.0') {
    $script:PSIModuleVersion = [string] (Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'PSInsightHTML.psd1')).ModuleVersion
}
$script:PSIStatusValues = @(
    'Healthy'
    'Warning'
    'Critical'
    'Informational'
    'Neutral'
    'Unknown'
    'NotChecked'
)
$script:PSIStatusAliases = @{ Info = 'Informational' }

function Get-PSIModuleSourceSet {
    # Ordered source files plus the public command names they define. Private
    # helpers load before public commands; provider commands load from one
    # controlled Public directory per report (provider implementations stay
    # private and are dot-sourced lazily when their command runs).
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Root)

    $Files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $Public = [System.Collections.Generic.List[string]]::new()
    foreach ($DirectoryName in @('Private', 'Public')) {
        $ScriptDirectory = Join-Path -Path $Root -ChildPath $DirectoryName
        if (-not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) { continue }
        try {
            $ScriptFiles = Get-ChildItem -LiteralPath $ScriptDirectory -File -ErrorAction Stop |
                Where-Object { $_.Extension -ieq '.ps1' } | Sort-Object -Property Name
        }
        catch { throw "Failed to enumerate PowerShell scripts in '$ScriptDirectory': $($_.Exception.Message)" }
        foreach ($ScriptFile in $ScriptFiles) {
            $Files.Add($ScriptFile)
            if ($DirectoryName -eq 'Public') { $Public.Add($ScriptFile.BaseName) }
        }
    }
    $ProvidersRoot = Join-Path -Path $Root -ChildPath 'Providers'
    if (Test-Path -LiteralPath $ProvidersRoot -PathType Container) {
        foreach ($ProviderDirectory in @(Get-ChildItem -LiteralPath $ProvidersRoot -Directory -ErrorAction Stop | Sort-Object Name)) {
            foreach ($ReportDirectory in @(Get-ChildItem -LiteralPath $ProviderDirectory.FullName -Directory -ErrorAction Stop | Sort-Object Name)) {
                $ProviderPublicDirectory = Join-Path -Path $ReportDirectory.FullName -ChildPath 'Public'
                if (-not (Test-Path -LiteralPath $ProviderPublicDirectory -PathType Container)) { continue }
                foreach ($ScriptFile in @(Get-ChildItem -LiteralPath $ProviderPublicDirectory -File -ErrorAction Stop |
                    Where-Object { $_.Extension -ieq '.ps1' } | Sort-Object Name)) {
                    if ($Public.Contains($ScriptFile.BaseName)) {
                        throw "Public function '$($ScriptFile.BaseName)' is defined more than once."
                    }
                    $Files.Add($ScriptFile)
                    $Public.Add($ScriptFile.BaseName)
                }
            }
        }
    }

    # Fingerprint from file metadata only: reading metadata does not open the
    # files, so it avoids the per-file antivirus scan that dominates load time.
    $Builder = [System.Text.StringBuilder]::new()
    foreach ($File in $Files) {
        [void] $Builder.Append($File.FullName.Substring($Root.Length)).Append('|').Append($File.Length).Append('|').Append($File.LastWriteTimeUtc.Ticks).Append(';')
    }
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try { $Hash = ([System.BitConverter]::ToString($Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Builder.ToString())))).Replace('-', '') }
    finally { $Sha.Dispose() }

    [pscustomobject]@{ Files = $Files.ToArray(); PublicFunctions = $Public.ToArray(); Fingerprint = $Hash }
}

$SourceSet = Get-PSIModuleSourceSet -Root $ModuleRoot

# Load order of preference:
#   1. PSInsightHTML.Bundle.ps1 when it was built from exactly these sources
#      (one file open instead of ~95; endpoint scanning costs ~90 ms per file).
#   2. The individual sources, compiled as one script block.
#   3. Per-file dot-sourcing, so a load error names the failing file.
# Set PSINSIGHTHTML_LOADPERFILE=1 to force option 3 while debugging.
$BundlePath = Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.Bundle.ps1'
$Loaded = $false
$LoadPerFile = $env:PSINSIGHTHTML_LOADPERFILE -eq '1'
if (-not $LoadPerFile -and (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
    $BundleText = [System.IO.File]::ReadAllText($BundlePath)
    $Expected = '# Fingerprint: ' + $SourceSet.Fingerprint
    if ($BundleText.StartsWith('# PSInsightHTML generated bundle') -and $BundleText.Contains($Expected)) {
        try { . ([scriptblock]::Create($BundleText)); $Loaded = $true }
        catch { Write-Warning "PSInsightHTML bundle failed to load ($($_.Exception.Message)); loading source files." }
    }
    else {
        Write-Warning 'PSInsightHTML.Bundle.ps1 is out of date with the source files; loading sources (slower). Run Build/Build-PSInsightHTML.ps1 to refresh it.'
    }
}
if (-not $Loaded -and -not $LoadPerFile) {
    try {
        $Combined = [System.Text.StringBuilder]::new()
        foreach ($ScriptFile in $SourceSet.Files) { [void] $Combined.AppendLine([System.IO.File]::ReadAllText($ScriptFile.FullName)) }
        . ([scriptblock]::Create($Combined.ToString()))
        $Loaded = $true
    }
    catch { $LoadPerFile = $true }
}
if (-not $Loaded) {
    foreach ($ScriptFile in $SourceSet.Files) {
        try { . $ScriptFile.FullName }
        catch { throw "Failed to load module script '$($ScriptFile.FullName)': $($_.Exception.Message)" }
    }
}

Export-ModuleMember -Function $SourceSet.PublicFunctions

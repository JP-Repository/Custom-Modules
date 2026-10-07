$script:ModuleRoot = $PSScriptRoot
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
$PublicFunctionNames = [System.Collections.Generic.List[string]]::new()

foreach ($DirectoryName in @('Private', 'Public')) {
    $ScriptDirectory = Join-Path -Path $ModuleRoot -ChildPath $DirectoryName

    if (-not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) {
        continue
    }

    try {
        $ScriptFiles = Get-ChildItem -LiteralPath $ScriptDirectory -File -ErrorAction Stop |
            Where-Object { $_.Extension -ieq '.ps1' } |
            Sort-Object -Property Name
    }
    catch {
        throw "Failed to enumerate PowerShell scripts in '$ScriptDirectory': $($_.Exception.Message)"
    }

    foreach ($ScriptFile in $ScriptFiles) {
        try {
            . $ScriptFile.FullName
            if ($DirectoryName -eq 'Public') {
                $PublicFunctionNames.Add($ScriptFile.BaseName)
            }
        }
        catch {
            throw "Failed to load module script '$($ScriptFile.FullName)': $($_.Exception.Message)"
        }
    }
}

# Provider report commands are loaded from one controlled Public directory per
# report. Provider implementation scripts remain private and are invoked lazily.
$ProvidersRoot = Join-Path -Path $ModuleRoot -ChildPath 'Providers'
if (Test-Path -LiteralPath $ProvidersRoot -PathType Container) {
    foreach ($ProviderDirectory in @(Get-ChildItem -LiteralPath $ProvidersRoot -Directory -ErrorAction Stop | Sort-Object Name)) {
        foreach ($ReportDirectory in @(Get-ChildItem -LiteralPath $ProviderDirectory.FullName -Directory -ErrorAction Stop | Sort-Object Name)) {
            $ProviderPublicDirectory = Join-Path -Path $ReportDirectory.FullName -ChildPath 'Public'
            if (-not (Test-Path -LiteralPath $ProviderPublicDirectory -PathType Container)) { continue }
            foreach ($ScriptFile in @(Get-ChildItem -LiteralPath $ProviderPublicDirectory -File -ErrorAction Stop |
                Where-Object { $_.Extension -ieq '.ps1' } | Sort-Object Name)) {
                try {
                    if ($PublicFunctionNames.Contains($ScriptFile.BaseName)) {
                        throw "Public function '$($ScriptFile.BaseName)' is defined more than once."
                    }
                    . $ScriptFile.FullName
                    $PublicFunctionNames.Add($ScriptFile.BaseName)
                }
                catch {
                    throw "Failed to load provider command '$($ScriptFile.FullName)': $($_.Exception.Message)"
                }
            }
        }
    }
}

Export-ModuleMember -Function $PublicFunctionNames.ToArray()

$script:ModuleRoot = $PSScriptRoot
$script:PSIEmailModuleVersion = '0.1.0'
$script:PSIEmailStatusValues = @('Neutral', 'Informational', 'Healthy', 'Warning', 'Critical')
$PublicFunctionNames = [System.Collections.Generic.List[string]]::new()

foreach ($DirectoryName in @('Private', 'Public')) {
    $ScriptDirectory = Join-Path -Path $script:ModuleRoot -ChildPath $DirectoryName
    if (-not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) { continue }

    foreach ($ScriptFile in @(Get-ChildItem -LiteralPath $ScriptDirectory -File -ErrorAction Stop |
        Where-Object { $_.Extension -ieq '.ps1' } | Sort-Object -Property Name)) {
        try {
            . $ScriptFile.FullName
            if ($DirectoryName -eq 'Public') { $PublicFunctionNames.Add($ScriptFile.BaseName) }
        }
        catch {
            throw "Failed to load module script '$($ScriptFile.FullName)': $($_.Exception.Message)"
        }
    }
}

$ExpectedFunctions = @(
    'New-PSIEmail', 'Send-PSIEmailGraph', 'Send-PSIEmailSmtp', 'Add-PSIEmailSection', 'Add-PSIEmailRow', 'Add-PSIEmailText',
    'Add-PSIEmailKPI', 'Add-PSIEmailKeyValue', 'Add-PSIEmailAlert', 'Add-PSIEmailBanner',
    'Add-PSIEmailAttachment', 'Add-PSIEmailInlineResource', 'Add-PSIEmailTable',
    'Add-PSIEmailDivider', 'ConvertTo-PSIEmailHtml', 'Export-PSIEmailPreview'
)
foreach ($FunctionName in $ExpectedFunctions) {
    if (-not $PublicFunctionNames.Contains($FunctionName)) {
        throw "Expected public function '$FunctionName' was not loaded."
    }
}

Export-ModuleMember -Function $ExpectedFunctions

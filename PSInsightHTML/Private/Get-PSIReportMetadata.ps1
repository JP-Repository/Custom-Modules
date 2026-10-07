function Get-PSIReportMetadata {
    [CmdletBinding()]
    param()

    $ProvidersRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers'
    if (-not (Test-Path -LiteralPath $ProvidersRoot -PathType Container)) { return }

    $RequiredKeys = @(
        'Id', 'Provider', 'Name', 'Description', 'Category', 'Command', 'Status',
        'SupportsSampleData', 'SupportsProvidedData', 'SupportsLiveCollection',
        'MinimumPowerShellVersion'
    )
    $SeenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ProviderDirectory in @(Get-ChildItem -LiteralPath $ProvidersRoot -Directory -ErrorAction Stop | Sort-Object Name)) {
        foreach ($ReportDirectory in @(Get-ChildItem -LiteralPath $ProviderDirectory.FullName -Directory -ErrorAction Stop | Sort-Object Name)) {
            $MetadataPath = Join-Path -Path $ReportDirectory.FullName -ChildPath 'Report.psd1'
            if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { continue }
            try { $Metadata = Import-PowerShellDataFile -LiteralPath $MetadataPath -ErrorAction Stop }
            catch { throw "Cannot read report metadata '$MetadataPath': $($_.Exception.Message)" }
            foreach ($Key in $RequiredKeys) {
                if (-not $Metadata.ContainsKey($Key) -or $null -eq $Metadata[$Key]) {
                    throw "Report metadata '$MetadataPath' is missing '$Key'."
                }
            }
            foreach ($Key in @('Id','Provider','Name','Description','Category','Command','Status','MinimumPowerShellVersion')) {
                if ([string]::IsNullOrWhiteSpace([string] $Metadata[$Key])) {
                    throw "Report metadata '$MetadataPath' has an empty '$Key'."
                }
            }
            if ([string] $Metadata.Provider -ne $ProviderDirectory.Name) {
                throw "Report metadata '$MetadataPath' has a Provider that differs from its directory."
            }
            if (-not $SeenIds.Add([string] $Metadata.Id)) {
                throw "Report metadata Id '$($Metadata.Id)' is duplicated."
            }
            foreach ($Key in @('SupportsSampleData','SupportsProvidedData','SupportsLiveCollection')) {
                if ($Metadata[$Key] -isnot [bool]) { throw "Report metadata '$MetadataPath' has a non-Boolean '$Key'." }
            }
            [pscustomobject][ordered]@{
                Id = [string] $Metadata.Id
                Provider = [string] $Metadata.Provider
                Name = [string] $Metadata.Name
                Description = [string] $Metadata.Description
                Category = [string] $Metadata.Category
                Command = [string] $Metadata.Command
                Status = [string] $Metadata.Status
                SupportsSampleData = [bool] $Metadata.SupportsSampleData
                SupportsProvidedData = [bool] $Metadata.SupportsProvidedData
                SupportsLiveCollection = [bool] $Metadata.SupportsLiveCollection
                MinimumPowerShellVersion = [string] $Metadata.MinimumPowerShellVersion
            }
        }
    }
}

function New-PSIADUserInventory {
    <#
    .SYNOPSIS
    Create an Active Directory User Inventory assessment.

    .DESCRIPTION
    Builds the user inventory assessment from fictional sample data or a supplied workbook. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER WorkbookPath
    Supplied workbook path; mutually exclusive with UseSampleData.

    .PARAMETER InsightThresholds
    Configurable investigation age thresholds.

    .EXAMPLE
    New-PSIADUserInventory -UseSampleData -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateNotNullOrEmpty()][string] $WorkbookPath,
    [Parameter()][datetime] $AsOfDate = (Get-Date),
    [Parameter()][hashtable] $Thresholds = @{},
    [Parameter()][hashtable] $InsightThresholds = @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 },
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if ($UseSampleData -and -not [string]::IsNullOrWhiteSpace($WorkbookPath)) {
        throw 'UseSampleData and WorkbookPath are mutually exclusive.'
    }
    if (-not $UseSampleData -and [string]::IsNullOrWhiteSpace($WorkbookPath)) {
        throw 'Specify -UseSampleData or -WorkbookPath. Live collection is not implemented.'
    }
    if ($UseSampleData) {
        $SampleWorkbook = Join-Path -Path $script:ModuleRoot -ChildPath 'Examples/Data/Active_Directory_Enterprise_User_Inventory_5000.xlsx'
        if (-not (Test-Path -LiteralPath $SampleWorkbook -PathType Leaf)) {
            throw "The local sample workbook was not found: $SampleWorkbook"
        }
    }
    elseif (-not (Test-Path -LiteralPath $WorkbookPath -PathType Leaf)) {
        throw "The supplied workbook was not found: $WorkbookPath"
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/UserInventory/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}

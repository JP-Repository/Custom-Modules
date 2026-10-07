[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $WorkbookPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [datetime] $AsOfDate = (Get-Date),

    [Parameter()]
    [hashtable] $Thresholds = @{},

    [Parameter()]
    [hashtable] $InsightThresholds = @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 },

    [Parameter()]
    [switch] $NoBrowser
)

# Backward-compatible usage example for the integrated provider command.
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force -ErrorAction Stop
$Arguments = @{}
foreach ($Key in $PSBoundParameters.Keys) {
    if ($Key -eq 'OutputPath') { $Arguments['Path'] = $PSBoundParameters[$Key] }
    else { $Arguments[$Key] = $PSBoundParameters[$Key] }
}
if (-not $PSBoundParameters.ContainsKey('WorkbookPath')) { $Arguments['UseSampleData'] = $true }
New-PSIADUserInventory @Arguments

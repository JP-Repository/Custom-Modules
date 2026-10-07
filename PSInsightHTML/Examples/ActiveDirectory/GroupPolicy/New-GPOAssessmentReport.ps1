[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [ValidateRange(100, 250)]
    [int] $GpoCount = 180,

    [Parameter()]
    [datetime] $AsOfDate = [datetime]::new(2026, 9, 27),

    [Parameter()]
    [switch] $NoBrowser
)

# Backward-compatible usage example for the integrated provider command.
$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force -ErrorAction Stop
$Arguments = @{}
foreach ($Key in $PSBoundParameters.Keys) {
    if ($Key -eq 'OutputPath') { $Arguments['Path'] = $PSBoundParameters[$Key] }
    else { $Arguments[$Key] = $PSBoundParameters[$Key] }
}
$Arguments['UseSampleData'] = $true
New-PSIADGroupPolicyAssessment @Arguments

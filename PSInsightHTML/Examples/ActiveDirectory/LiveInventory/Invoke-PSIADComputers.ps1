<# .SYNOPSIS Generate the Computers inventory using the shared read-only AD example runner. #>
[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $CollectionProfile,
    [ValidateRange(1,50000)][int] $MaxObjects = 2000,
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
& (Join-Path $PSScriptRoot 'Invoke-PSIADInventoryReport.ps1') -ReportType Computers @PSBoundParameters

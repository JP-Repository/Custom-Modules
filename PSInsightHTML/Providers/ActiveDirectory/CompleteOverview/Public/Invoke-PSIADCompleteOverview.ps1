function Invoke-PSIADCompleteOverview {
    <#
    .SYNOPSIS
        Generate the linked AD Domain Overview report set.
    .DESCRIPTION
        Uses one read-only DC snapshot and scoped directory inventory queries.
        Use -UseSampleData for a fictional, offline demonstration or -Domain for a live pilot.
    .EXAMPLE
        Invoke-PSIADCompleteOverview -UseSampleData -NoBrowser
    .EXAMPLE
        Invoke-PSIADCompleteOverview -Domain ad.example.test -CollectionProfile Full -OutputPath C:\Reports\PSInsightHTML -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [switch] $UseSampleData,
        [string] $Domain,
        [pscustomobject] $Snapshot,
        [hashtable] $CommandAdapter,
        [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $CollectionProfile = 'Full',
        [ValidateRange(1,50000)][int] $MaxObjects = 2000,
        [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
        [string] $OutputPath,
        [ValidateSet('DomainOverview','DCInventory','DCReadiness2022','DCReadiness2025','HealthEvidence','Health','Security','Compliance','DNS','Replication','SitesSubnets','GroupPolicy','OUs','Groups','Users','Computers')]
        [string[]] $Only = @(),
        [switch] $NoBrowser,
        [switch] $PassThru
    )
    & (Join-Path $script:ModuleRoot 'Examples/ActiveDirectory/Invoke-PSIADCompleteOverview.ps1') @PSBoundParameters
}

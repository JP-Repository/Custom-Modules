[CmdletBinding()]
param(
    [Parameter()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'
$GenerationTimer = [System.Diagnostics.Stopwatch]::StartNew()
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-Composed-AD-Assessment-Demo.html'
}

$Report = New-PSIReport -Title 'Active Directory Assessment Portfolio' `
    -Subtitle 'Fictional sample data | DNS, replication, topology, groups, and policy' -Theme $Theme

$Assessments = @(
    New-PSIADDNSAssessment -UseSampleData -AsAssessment -NoBrowser
    New-PSIADReplicationAssessment -UseSampleData -AsAssessment -NoBrowser
    New-PSIADSitesSubnetsAssessment -UseSampleData -AsAssessment -NoBrowser
    New-PSIADGroupAssessment -UseSampleData -AsAssessment -NoBrowser
    New-PSIADGroupPolicyAssessment -UseSampleData -AsAssessment -NoBrowser
)

function Get-SampleEvidenceTable {
    param([pscustomobject] $Assessment, [string] $Id)
    foreach ($Section in $Assessment.Sections) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -eq 'Table' -and $Component.Properties.Id -eq $Id) { return $Component }
            }
        }
    }
    throw "Sample evidence table '$Id' was not found."
}

# These demonstration findings reflect existing fictional provider states. They
# reference the provider tables; no evidence rows are copied into the overview.
$DnsServers = (Get-SampleEvidenceTable -Assessment $Assessments[0] -Id 'dns-servers').Properties.Data
$ExternalResolverCount = @($DnsServers | Where-Object HasPublicResolver -eq 'Yes').Count
$null = $Assessments[0] | Add-PSISection -Title 'Structured Findings' | Add-PSIRow |
    Add-PSIFinding -Finding (New-PSIFinding -Title 'External sample resolvers observed' -Status Informational `
        -Description ("$ExternalResolverCount fictional DNS server rows list an external sample resolver; review their intended configuration.") `
        -Source 'Fictional DNS sample' -EvidenceTableId 'dns-servers' `
        -EvidenceFilter @{ Property = 'HasPublicResolver'; Operator = 'Equals'; Value = 'Yes' })

$Relationships = (Get-SampleEvidenceTable -Assessment $Assessments[1] -Id 'replication-relationships').Properties.Data
$CriticalReplicationCount = @($Relationships | Where-Object ReplicationState -eq 'Critical').Count
$WarningReplicationCount = @($Relationships | Where-Object ReplicationState -eq 'Warning').Count
$null = $Assessments[1] | Add-PSISection -Title 'Structured Findings' | Add-PSIRow |
    Add-PSIFinding -Finding (New-PSIFinding -Title 'Critical replication relationships' -Status Critical `
        -Description ("$CriticalReplicationCount fictional relationship rows have provider-defined Critical state.") `
        -Source 'Fictional replication sample' -EvidenceTableId 'replication-relationships' `
        -EvidenceFilter @{ Property = 'ReplicationState'; Operator = 'Equals'; Value = 'Critical' }) |
    Add-PSIFinding -Finding (New-PSIFinding -Title 'Warning replication relationships' -Status Warning `
        -Description ("$WarningReplicationCount fictional relationship rows have provider-defined Warning state.") `
        -Source 'Fictional replication sample' -EvidenceTableId 'replication-relationships' `
        -EvidenceFilter @{ Property = 'ReplicationState'; Operator = 'Equals'; Value = 'Warning' })

$Overlaps = (Get-SampleEvidenceTable -Assessment $Assessments[2] -Id 'ss-overlaps').Properties.Data
$CrossSiteCount = @($Overlaps | Where-Object CrossSite -eq 'Yes').Count
$null = $Assessments[2] | Add-PSISection -Title 'Structured Findings' | Add-PSIRow |
    Add-PSIFinding -Finding (New-PSIFinding -Title 'Cross-site subnet overlap candidates' -Status Informational `
        -Description ("$CrossSiteCount fictional overlap pairs span different sites; overlap alone is not a defect.") `
        -Source 'Fictional topology sample' -EvidenceTableId 'ss-overlaps' `
        -EvidenceFilter @{ Property = 'CrossSite'; Operator = 'Equals'; Value = 'Yes' })

foreach ($Assessment in $Assessments) {
    $null = $Report | Add-PSIAssessment -Assessment $Assessment
}
$null = $Report | Add-PSIReportOverview -IncludeTopFindings -MaxFindings 10

$OutputFile = Export-PSIReport -Report $Report -Path $OutputPath
$GenerationTimer.Stop()
$Summary = Get-PSIReportSummary -Report $Report
$EvidenceActionCount = [regex]::Matches([System.IO.File]::ReadAllText($OutputFile.FullName), 'data-psi-insight=').Count
Write-Host ('Composed {0} fictional assessments into {1} sections.' -f $Summary.AssessmentCount, $Summary.SectionCount)
Write-Host ('Generation: {0:N2}s; size: {1:N0} bytes; tables: {2}; findings: {3}; evidence actions: {4}.' -f `
    $GenerationTimer.Elapsed.TotalSeconds, $OutputFile.Length, $Summary.TableCount, $Summary.FindingCount, $EvidenceActionCount)
Write-Host "Generated report: $($OutputFile.FullName)"

if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') {
            Start-Process -FilePath $OutputFile.FullName -ErrorAction Stop
        }
        elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
            $OpenProcess = Start-Process -FilePath 'open' -ArgumentList @($OutputFile.FullName) -Wait -PassThru -ErrorAction Stop
            if ($OpenProcess.ExitCode -ne 0) { throw "macOS open exited with code $($OpenProcess.ExitCode)." }
        }
        else {
            Start-Process -FilePath 'xdg-open' -ArgumentList @($OutputFile.FullName) -ErrorAction Stop
        }
    }
    catch { Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)" }
}
$OutputFile

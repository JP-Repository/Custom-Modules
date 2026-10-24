<#
.SYNOPSIS
    Verifies that the Fluent renderer's JSON model carries the same table data as the report object.

.DESCRIPTION
    For every Table component, compares row count and the number of non-null cells per column between
    the source records and the projected model, and checks that list-valued fields are JSON arrays.
    Returns one row per table; any row with Ok = False is a projection defect.

.EXAMPLE
    $assessment = New-PSIADDNSAssessment -UseSampleData -AsAssessment
    ./Build/Test-PSIFluentParity.ps1 -Report $assessment
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][pscustomobject] $Report)

$Module = Get-Module PSInsightHTML
if (-not $Module) { throw 'Import PSInsightHTML first.' }
$Json = & $Module { param($R) ConvertTo-Json -InputObject (ConvertTo-PSIFluentModel -Report $R) -Depth 24 -Compress } $Report
$Model = $Json | ConvertFrom-Json

$Index = 0
foreach ($Section in $Report.Sections) {
    foreach ($Row in $Section.Rows) {
        foreach ($Component in $Row.Components) {
            if ($Component.Type -ne 'Table') { continue }
            $Id = [string] $Component.Properties.Id
            $Projected = $null
            foreach ($S in $Model.sections) { foreach ($MR in $S.rows) { foreach ($Item in @($MR.items)) { if ($Item.t -eq 'Table' -and $Item.id -eq $Id) { $Projected = $Item } } } }
            $Source = @($Component.Properties.Data | Where-Object { $null -ne $_ })
            $Columns = @($Projected.columns)
            $Mismatch = [System.Collections.Generic.List[string]]::new()
            for ($C = 0; $C -lt $Columns.Count; $C++) {
                $Expected = @($Source | Where-Object {
                    $V = if ($_ -is [System.Collections.IDictionary]) { $_[$Columns[$C]] } else { $P = $_.PSObject.Properties[$Columns[$C]]; if ($P) { $P.Value } }
                    $null -ne $V }).Count
                $Actual = @($Projected.rows | Where-Object { $null -ne @($_)[$C] }).Count
                if ($Expected -ne $Actual) { $Mismatch.Add("$($Columns[$C]): source $Expected, model $Actual") }
            }
            $ArrayIssues = @()
            if ($Projected.columns -isnot [array]) { $ArrayIssues += 'columns not an array' }
            if ($Projected.export.columns -isnot [array]) { $ArrayIssues += 'export.columns not an array' }
            [pscustomobject]@{
                Table   = $Id
                Rows    = '{0} / {1}' -f $Source.Count, @($Projected.rows).Count
                Columns = $Columns.Count
                Ok      = ($Source.Count -eq @($Projected.rows).Count) -and $Mismatch.Count -eq 0 -and $ArrayIssues.Count -eq 0
                Issues  = (@($Mismatch) + $ArrayIssues) -join '; '
            }
            $Index++
        }
    }
}

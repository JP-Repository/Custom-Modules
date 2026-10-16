function Assert-PSIApplicationLinks {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    foreach ($View in $Report.Views) {
        foreach ($Section in $View.Sections) {
            foreach ($Row in $Section.Rows) {
                foreach ($Component in $Row.Components) {
                    if ($Component.Type -ne 'Explorer' -or -not $Component.Properties.EntityType) { continue }
                    $Properties = $Component.Properties
                    $RequiredKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Checks = switch ([string] $Properties.EntityType) {
                        Finding { @(@('AffectedResourceIds','Resource'),@('EvidenceIds','Evidence')) }
                        Resource { @(@('FindingIds','Finding'),@('EvidenceIds','Evidence'),@('RelationshipIds','Resource')) }
                        Evidence { @(@('ResourceIds','Resource'),@('FindingIds','Finding')) }
                        Check { @(@('FindingIds','Finding'),@('ResourceIds','Resource'),@('EvidenceIds','Evidence')) }
                        Category { @(@('CheckIds','Check')) }
                        Exception { @(@('CheckId','Check'),@('FindingId','Finding'),@('ResourceIds','Resource')) }
                    }
                    foreach ($Record in @($Properties.Data)) {
                        foreach ($Check in $Checks) {
                            $Values = @(Get-PSIProperty -InputObject $Record -Name $Check[0] -DefaultValue @())
                            if (@($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }).Count -gt 0) {
                                [void] $RequiredKinds.Add([string] $Check[1])
                            }
                        }
                    }
                    foreach ($Kind in $RequiredKinds) {
                        $TargetId = [string] $Properties.LinkViews[$Kind]
                        $TargetView = @($Report.Views | Where-Object { $_.Id -ieq $TargetId })[0]
                        if ($null -eq $TargetView) { throw "Explorer '$($Properties.Id)' links to missing $Kind view '$TargetId'." }
                        $HasTargetExplorer = $false
                        foreach ($TargetSection in $TargetView.Sections) {
                            foreach ($TargetRow in $TargetSection.Rows) {
                                foreach ($TargetComponent in $TargetRow.Components) {
                                    if ($TargetComponent.Type -eq 'Explorer' -and $TargetComponent.Properties.EntityType -eq $Kind) { $HasTargetExplorer = $true }
                                }
                            }
                        }
                        if (-not $HasTargetExplorer) { throw "Explorer '$($Properties.Id)' links to view '$TargetId' without a $Kind explorer." }
                    }
                }
            }
        }
    }
    $true
}

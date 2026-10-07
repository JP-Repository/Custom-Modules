function Get-PSIFindingAnchors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable] $Sections
    )

    $SectionList = @($Sections)
    $UsedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($FixedId in @('psi-dialog-title', 'psi-dialog-description', 'psi-dialog-summary')) { [void] $UsedIds.Add($FixedId) }
    for ($SectionIndex = 0; $SectionIndex -lt $SectionList.Count; $SectionIndex++) {
        [void] $UsedIds.Add("psi-section-$SectionIndex")
        foreach ($Row in $SectionList[$SectionIndex].Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -ne 'Table') { continue }
                $TableId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ([string]::IsNullOrWhiteSpace($TableId)) { continue }
                [void] $UsedIds.Add($TableId)
                [void] $UsedIds.Add("$TableId-data")
                $Filters = @((Get-PSIProperty -InputObject $Component.Properties -Name 'Filters'))
                for ($FilterIndex = 0; $FilterIndex -lt $Filters.Count; $FilterIndex++) {
                    [void] $UsedIds.Add("$TableId-filter-$FilterIndex")
                    [void] $UsedIds.Add("psi-filter-help-$TableId-filter-$FilterIndex")
                }
            }
        }
    }

    $Anchors = [System.Collections.Generic.List[object]]::new()
    foreach ($Section in $SectionList) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -ne 'Finding') { continue }
                $BaseId = ConvertTo-PSIFindingId -Id ([string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id'))
                $DomId = $BaseId
                $Suffix = 2
                while (-not $UsedIds.Add($DomId)) {
                    $DomId = '{0}-{1}' -f $BaseId, $Suffix
                    $Suffix++
                }
                $Anchors.Add([pscustomobject]@{
                    Id = $DomId
                    FindingReference = Get-PSIProperty -InputObject $Component.Properties -Name 'FindingReference'
                })
            }
        }
    }
    ,$Anchors
}

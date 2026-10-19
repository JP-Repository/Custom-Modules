function Resolve-PSIApplicationNavigation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    $Sections = $Report.Sections
    $UsedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @('psi-app-navigation', 'psi-app-nav-toggle', 'psi-app-main', 'psi-app-command',
        'psi-fluent-icon-attribution', 'psi-dialog-title', 'psi-dialog-description', 'psi-dialog-summary')) {
        [void] $UsedIds.Add($Id)
    }
    for ($Index = 0; $Index -lt $Sections.Count; $Index++) { [void] $UsedIds.Add("psi-section-$Index") }
    foreach ($TableId in (Assert-PSIReportIds -Sections $Sections)) {
        if (-not $UsedIds.Add([string] $TableId) -or -not $UsedIds.Add("$TableId-data")) {
            throw "Application layout ID '$TableId' conflicts with a generated section or shell ID."
        }
    }
    foreach ($Anchor in (Get-PSIFindingAnchors -Sections $Sections)) {
        if (-not $UsedIds.Add([string] $Anchor.Id)) { throw "Application layout ID '$($Anchor.Id)' is duplicated." }
    }
    foreach ($Section in $Sections) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -in @('Tree','Topology','RelationshipExplorer')) {
                    $PresentationId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                    if ($PresentationId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or -not $UsedIds.Add($PresentationId)) {
                        throw "Relationship presentation ID '$PresentationId' is invalid or duplicated."
                    }
                }
                if ($Component.Type -ne 'Explorer') { continue }
                $ExplorerId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ($ExplorerId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or
                    -not $UsedIds.Add($ExplorerId) -or -not $UsedIds.Add("$ExplorerId-search")) {
                    throw "Application explorer ID '$ExplorerId' is invalid or duplicated."
                }
                $ExplorerData = Get-PSIProperty -InputObject $Component.Properties -Name 'Data' -DefaultValue @()
                for ($Index = 0; $Index -lt $ExplorerData.Count; $Index++) {
                    if (-not $UsedIds.Add("$ExplorerId-detail-$Index") -or -not $UsedIds.Add("$ExplorerId-item-$Index")) {
                        throw "Application explorer item ID '$ExplorerId-item-$Index' is duplicated."
                    }
                }
            }
        }
    }

    $RawGroups = Get-PSIProperty -InputObject $Report -Name 'NavigationGroups' -DefaultValue @()
    $Views = Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()
    $IsMultiView = $null -ne $Views -and $Views.Count -gt 0
    if ($IsMultiView) {
        if ($RawGroups.Count -gt 0) { throw 'NavigationGroups and application Views cannot be combined.' }
        $ViewIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $InitialCount = 0
        $ExpectedSections = 0
        $GroupMap = [ordered]@{}
        foreach ($View in $Views) {
            $Id = [string] (Get-PSIProperty -InputObject $View -Name 'Id')
            $Title = [string] (Get-PSIProperty -InputObject $View -Name 'Title')
            $Group = [string] (Get-PSIProperty -InputObject $View -Name 'Group' -DefaultValue 'Workspace')
            $Icon = [string] (Get-PSIProperty -InputObject $View -Name 'Icon' -DefaultValue 'Document')
            $ViewSections = Get-PSIProperty -InputObject $View -Name 'Sections'
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or -not $ViewIds.Add($Id)) {
                throw "Application view ID '$Id' is invalid or duplicated."
            }
            if (-not $UsedIds.Add("psi-view-$Id")) { throw "Application view ID '$Id' conflicts with an existing element." }
            if ([string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($Group)) {
                throw "Application view '$Id' requires a Title and Group."
            }
            if ($null -eq $ViewSections -or $ViewSections.Count -eq 0) { throw "Application view '$Id' requires at least one section." }
            [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
            [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
            foreach ($ViewSection in $ViewSections) {
                if ($ExpectedSections -ge $Sections.Count -or
                    -not [object]::ReferenceEquals($ViewSection, $Sections[$ExpectedSections]) -or
                    (Get-PSIProperty -InputObject $ViewSection -Name 'ViewId') -cne $Id) {
                    throw "Application view '$Id' has sections that do not match the report section order."
                }
                $ExpectedSections++
            }
            if ((Get-PSIProperty -InputObject $View.State -Name 'Initial' -DefaultValue $false) -eq $true) { $InitialCount++ }
            if (-not $GroupMap.Contains($Group)) { $GroupMap[$Group] = [System.Collections.Generic.List[object]]::new() }
            $GroupMap[$Group].Add(@{ Id=$Id; Label=$Title; Target="psi-view-$Id"; Icon=$Icon;
                Badge=[string] (Get-PSIProperty -InputObject $View -Name 'Badge' -DefaultValue '');
                Selected=(Get-PSIProperty -InputObject $View.State -Name 'Initial' -DefaultValue $false) -eq $true })
        }
        if ($ExpectedSections -ne $Sections.Count) { throw 'Every application section must belong to a registered view.' }
        if ($InitialCount -gt 1) { throw 'Only one application view can be initial.' }
        foreach ($View in $Views) {
            foreach ($Command in $View.Commands) {
                if (@($Views | Where-Object { $_.Id -ceq [string] $Command.TargetView }).Count -eq 0) {
                    throw "Application view '$($View.Id)' command targets missing view '$($Command.TargetView)'."
                }
            }
        }
        $RawGroups = @(
            foreach ($GroupName in $GroupMap.Keys) { @{ Label=$GroupName; Items=$GroupMap[$GroupName] } }
        )
    }
    if ($RawGroups.Count -eq 0) {
        $DefaultItems = @(
            for ($Index = 0; $Index -lt $Sections.Count; $Index++) {
                @{ Id = "section-$Index"; Label = [string] $Sections[$Index].Title; Target = "psi-section-$Index";
                    Icon = if ($Index -eq 0) { 'NavigationHome' } else { 'Document' }; Selected = $Index -eq 0 }
            }
        )
        $RawGroups = @(@{ Label = 'Report'; Items = $DefaultItems })
    }

    $Groups = [System.Collections.Generic.List[object]]::new()
    $SelectedCount = 0
    $FirstEnabled = $null
    foreach ($RawGroup in $RawGroups) {
        $GroupLabel = [string] (Get-PSIProperty -InputObject $RawGroup -Name 'Label')
        if ([string]::IsNullOrWhiteSpace($GroupLabel)) { throw 'Each application navigation group requires a Label.' }
        $RawItems = Get-PSIProperty -InputObject $RawGroup -Name 'Items' -DefaultValue @()
        if ($RawItems.Count -eq 0) { throw "Application navigation group '$GroupLabel' requires at least one item." }
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($RawItem in $RawItems) {
            $Id = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Id')
            $Label = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Label')
            $Target = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Target')
            $Icon = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Icon' -DefaultValue 'Document')
            $Badge = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Badge' -DefaultValue '')
            $Disabled = (Get-PSIProperty -InputObject $RawItem -Name 'Disabled' -DefaultValue $false) -eq $true
            $Selected = (Get-PSIProperty -InputObject $RawItem -Name 'Selected' -DefaultValue $false) -eq $true
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Application navigation item ID '$Id' is invalid." }
            if ([string]::IsNullOrWhiteSpace($Label)) { throw "Application navigation item '$Id' requires a Label." }
            if (-not $UsedIds.Add("psi-app-item-$Id")) { throw "Application navigation item ID '$Id' is duplicated or conflicts with another element." }
            if ($IsMultiView) {
                if ($Target -cne "psi-view-$Id") { throw "Application navigation item '$Id' must target its view." }
            }
            else {
                if (-not $Disabled -and $Target -notmatch '^psi-section-(\d+)$') { throw "Application navigation item '$Id' requires a section Target." }
                if ($Target -match '^psi-section-(\d+)$' -and [int] $Matches[1] -ge $Sections.Count) {
                    throw "Application navigation item '$Id' targets missing section '$Target'."
                }
            }
            if ($Disabled -and $Selected) { throw "Disabled application navigation item '$Id' cannot be selected." }
            [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
            [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
            if ($Selected) { $SelectedCount++ }
            $Item = [pscustomobject]@{ Id = $Id; Label = $Label; Target = $Target; Icon = $Icon;
                Badge = $Badge; Disabled = $Disabled; Selected = $Selected }
            if (-not $Disabled -and $null -eq $FirstEnabled) { $FirstEnabled = $Item }
            $Items.Add($Item)
        }
        $Groups.Add([pscustomobject]@{ Label = $GroupLabel; Items = $Items })
    }
    if ($SelectedCount -gt 1) { throw 'Only one application navigation item can be selected.' }
    if ($null -eq $FirstEnabled) { throw 'Application navigation requires at least one enabled item.' }
    if ($SelectedCount -eq 0) { $FirstEnabled.Selected = $true }
    ,$Groups
}

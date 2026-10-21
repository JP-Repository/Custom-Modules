function ConvertTo-PSIResourceWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Report)

    $Explorer = Get-PSIProperty $Report 'ResourceExplorer'
    $Inspector = Get-PSIProperty $Report 'Inspector'
    if ($null -eq $Explorer) { return [pscustomobject]@{ Explorer=''; Header=''; Inspector=''; Controls=''; Data=''; Script='' } }
    if ((Get-PSIProperty $Report 'Navigation') -ne 'FluentExplorer') { throw 'Shell Resource Explorer requires FluentExplorer navigation.' }

    $Nodes = @($Explorer.Nodes)
    $ById = @{}
    $Children = @{}
    foreach ($Node in $Nodes) {
        $ById[$Node.Id] = $Node
        $Parent = [string]$Node.ParentId
        if (-not $Children.ContainsKey($Parent)) { $Children[$Parent] = [System.Collections.Generic.List[object]]::new() }
        $Children[$Parent].Add($Node)
        if ($Node.Target -and @($Report.Views | Where-Object { $_.Id -eq $Node.Target }).Count -eq 0) {
            throw "Resource node '$($Node.Id)' targets missing view '$($Node.Target)'."
        }
    }
    $Tree = [System.Text.StringBuilder]::new()
    $Stack = [System.Collections.Generic.Stack[object]]::new()
    if ($Children.ContainsKey('')) {
        $Roots = @($Children[''])
        for ($Index=$Roots.Count-1; $Index -ge 0; $Index--) { $Stack.Push($Roots[$Index]) }
    }
    while ($Stack.Count -gt 0) {
        $Node = $Stack.Pop()
        $NodeId = [string]$Node.Id
        $Label = ConvertTo-PSIHtmlEncoded -Value $Node.Label
        $Type = ConvertTo-PSIHtmlEncoded -Value $Node.Type
        $Status = ConvertTo-PSIHtmlEncoded -Value $Node.Status
        $ParentId = [string]$Node.ParentId
        $Target = [string]$Node.Target
        $Selected = if ($NodeId -eq $Explorer.SelectedId) { 'true' } else { 'false' }
        $HasChildren = $Children.ContainsKey($NodeId) -and $Children[$NodeId].Count -gt 0
        $Expanded = if ($HasChildren) { ' aria-expanded="true"' } else { '' }
        $Disabled = if ($Node.Selectable) { '' } else { ' aria-disabled="true"' }
        $Regular = (Get-PSIIcon -Name $Node.Icon -Variant Regular -Size 18 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-regular"')
        $Filled = (Get-PSIIcon -Name $Node.Icon -Variant Filled -Size 18 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-filled"')
        $Chevron = if ($HasChildren) { '<span class="psi-resource-chevron" aria-hidden="true">' + (Get-PSIIcon -Name AppChevron -Size 14 -Strict) + '</span>' } else { '<span class="psi-resource-chevron" aria-hidden="true"></span>' }
        $Count = if ($null -ne $Node.Count) { '<span class="psi-resource-count">' + [int]$Node.Count + '</span>' } else { '' }
        $StatusPresentation = Get-PSIStatusPresentation -Status $Node.Status
        $StatusIconName = if ($null -ne $StatusPresentation) { $StatusPresentation.Icon } else { 'SeverityInfo' }
        $StatusIcon = Get-PSIIcon -Name $StatusIconName -Size 13 -Strict
        [void]$Tree.AppendLine("<button type=`"button`" class=`"psi-resource-node`" role=`"treeitem`" data-psi-resource-node=`"$NodeId`" data-psi-resource-parent=`"$ParentId`" data-psi-resource-target=`"$Target`" data-psi-resource-type=`"$Type`" data-psi-resource-status=`"$Status`" style=`"--psi-resource-depth:$($Node.Depth)`" aria-level=`"$($Node.Depth+1)`" aria-selected=`"$Selected`"$Expanded$Disabled tabindex=`"-1`">$Chevron<span class=`"psi-resource-icon`">$Regular$Filled</span><span class=`"psi-resource-label`">$Label</span>$Count<span class=`"psi-resource-status psi-status-$($Node.Status.ToLowerInvariant())`" title=`"Status: $Status`" aria-label=`"Status: $Status`">$StatusIcon</span></button>")
        if ($HasChildren) {
            $ChildNodes = @($Children[$NodeId])
            for ($Index=$ChildNodes.Count-1; $Index -ge 0; $Index--) { $Stack.Push($ChildNodes[$Index]) }
        }
    }
    $ExplorerTitle = ConvertTo-PSIHtmlEncoded -Value $Explorer.Title
    $SearchIcon = Get-PSIIcon -Name NavigationSearch -Size 17 -Strict
    $CloseIcon = Get-PSIIcon -Name AppClose -Size 17 -Strict
    $ExplorerMarkup = @"
    <aside class="psi-resource-explorer" id="psi-resource-explorer" data-psi-resource-explorer data-psi-explorer-id="$($Explorer.Id)" aria-label="$ExplorerTitle">
      <div class="psi-resource-explorer-head"><h2>$ExplorerTitle</h2><button type="button" data-psi-resource-collapse aria-label="Hide Resource Explorer" aria-controls="psi-resource-explorer" aria-expanded="true">$CloseIcon</button></div>
      <label class="psi-resource-search" for="psi-resource-search-input">$SearchIcon<span class="psi-sr-only">Search resources</span><input id="psi-resource-search-input" type="search" data-psi-resource-search placeholder="Find a resource" autocomplete="off"></label>
      <div class="psi-resource-tree" role="tree" aria-label="$ExplorerTitle" data-psi-resource-tree>
$($Tree.ToString())      </div>
      <p class="psi-resource-empty" data-psi-resource-empty hidden>No matching resources.</p>
    </aside>
"@
    $HeaderIcons = '<template data-psi-resource-status-icon="healthy">' + (Get-PSIIcon -Name SeveritySuccess -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="warning">' + (Get-PSIIcon -Name SeverityWarning -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="critical">' + (Get-PSIIcon -Name SeverityError -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="info">' + (Get-PSIIcon -Name SeverityInfo -Size 13 -Strict) + '</template>'
    $Header = $HeaderIcons + '<div class="psi-resource-header" id="psi-resource-header" data-psi-resource-header aria-live="polite"><span class="psi-resource-header-icon" data-psi-resource-header-icon></span><div class="psi-resource-header-copy"><p data-psi-resource-header-breadcrumb></p><h2 data-psi-resource-header-title></h2><span data-psi-resource-header-subtitle></span><div class="psi-resource-header-tags" data-psi-resource-header-tags></div></div><div class="psi-resource-header-side"><span class="psi-resource-header-status" data-psi-resource-header-status></span><div class="psi-resource-header-actions" data-psi-resource-header-actions></div></div></div>'
    $InspectorMarkup = ''
    $Data = ''
    if ($null -ne $Inspector) {
        $InspectorTitle = ConvertTo-PSIHtmlEncoded -Value $Inspector.Title
        $InspectorMarkup = @"
        <aside class="psi-context-inspector" id="psi-context-inspector" data-psi-context-inspector data-psi-inspector-id="$($Inspector.Id)" aria-label="$InspectorTitle">
          <div class="psi-context-inspector-head"><div><p>RESOURCE CONTEXT</p><h2>$InspectorTitle</h2></div><button type="button" data-psi-inspector-collapse aria-label="Hide Context Inspector" aria-controls="psi-context-inspector" aria-expanded="true">$CloseIcon</button></div>
          <div class="psi-context-inspector-identity"><strong data-psi-inspector-title></strong><span data-psi-inspector-subtitle></span><span data-psi-inspector-status></span></div>
          <div class="psi-context-inspector-tabs" role="tablist" aria-label="Resource details" data-psi-inspector-tabs></div>
          <div class="psi-context-inspector-body" data-psi-inspector-body></div>
        </aside>
"@
        $Lookup = @{}
        foreach ($Item in $Inspector.Items) { $Lookup[$Item.ResourceId] = $Item }
        $Json = (ConvertTo-Json -InputObject $Lookup -Depth 8 -Compress).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
        $Data = '<script type="application/json" id="psi-resource-data">' + $Json + '</script>'
    }
    $Controls = '<button type="button" class="psi-resource-restore" data-psi-resource-restore aria-label="Show Resource Explorer" aria-controls="psi-resource-explorer" aria-expanded="true">Resources</button>'
    if ($null -ne $Inspector) { $Controls += '<button type="button" class="psi-inspector-restore" data-psi-inspector-restore aria-label="Show Context Inspector" aria-controls="psi-context-inspector" aria-expanded="true">Inspector</button>' }
    $Script = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-resource-workspace.js') -Raw -ErrorAction Stop
    [pscustomobject]@{ Explorer=$ExplorerMarkup; Header=$Header; Inspector=$InspectorMarkup; Controls=$Controls; Data=$Data; Script=$Script }
}

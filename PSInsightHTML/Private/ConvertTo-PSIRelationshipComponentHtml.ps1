function ConvertTo-PSIRelationshipComponentHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Tree','Topology','RelationshipExplorer')][string] $Type,
          [Parameter(Mandatory)][hashtable] $Properties)

    function E($Value) { ConvertTo-PSIHtmlEncoded -Value $Value }
    function Branch($ParentId, $Level, $Children, $Counter) {
        $Output = [System.Text.StringBuilder]::new()
        if (-not $Children.ContainsKey([string] $ParentId)) { return '' }
        foreach ($Node in @($Children[$ParentId])) {
            $Counter.Value++
            $First = $Counter.Value -eq 1
            $Kids = if ($Children.ContainsKey([string] $Node.Id)) { @($Children[[string] $Node.Id]) } else { @() }
            $Expanded = if ($Kids.Count -gt 0) { ' aria-expanded="true"' } else { '' }
            $Selected = if ($First) { 'true' } else { 'false' }
            $TabIndex = if ($First) { '0' } else { '-1' }
            $Suffix = if ($Node.Status -eq 'NotChecked') { 'not-checked' } else { $Node.Status.ToLowerInvariant() }
            $External = if ($Node.External) { '<small class="psi-rel-external">External / evidence only</small>' } else { '' }
            $Icon = Get-PSIIcon -Name $Node.Icon -Size 18 -Strict
            $Label = E $Node.Name
            $NodeType = E $Node.Type
            $Id = E $Node.Id
            $Status = E $Node.Status
            $Count = if ($Kids.Count -gt 0) { '<small class="psi-rel-count">' + $Kids.Count + '</small>' } else { '' }
            [void] $Output.AppendLine("<li role=`"treeitem`" class=`"psi-rel-treeitem`" data-psi-rel-node=`"$Id`" aria-selected=`"$Selected`" aria-level=`"$Level`" tabindex=`"$TabIndex`"$Expanded><span class=`"psi-rel-tree-row`"><span class=`"psi-rel-twisty`" aria-hidden=`"true`">$([char]0x25BE)</span><span class=`"psi-rel-icon`">$Icon</span><span class=`"psi-rel-node-copy`"><strong>$Label</strong><small>$NodeType</small></span>$Count<span class=`"psi-status-badge psi-status-$Suffix`">$Status</span>$External</span>")
            if ($Kids.Count -gt 0) { [void] $Output.AppendLine('<ul role="group">' + (Branch $Node.Id ($Level+1) $Children $Counter) + '</ul>') }
            [void] $Output.AppendLine('</li>')
        }
        $Output.ToString()
    }

    $Id = [string] $Properties.Id
    $Title = E $Properties.Title
    $Presentation = $Properties.Presentation
    $Nodes = @($Presentation.Nodes)
    $Edges = @($Presentation.Edges)
    $Json = ConvertTo-Json -InputObject @{ Nodes=$Nodes; Edges=$Edges; LinkViews=$Properties.LinkViews; Diagnostics=@($Presentation.Diagnostics) } -Depth 12 -Compress
    $Json = $Json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
    $Icons = [System.Text.StringBuilder]::new()
    foreach ($IconName in @($Nodes | ForEach-Object { $_.Icon } | Sort-Object -Unique)) {
        [void] $Icons.AppendLine('<template data-psi-rel-icon="' + (E $IconName) + '">' + (Get-PSIIcon -Name $IconName -Size 20 -Strict) + '</template>')
    }
    $Types = @($Nodes | ForEach-Object { $_.Type } | Where-Object { $_ } | Sort-Object -Unique)
    $Statuses = @($Nodes | ForEach-Object { $_.Status } | Where-Object { $_ } | Sort-Object -Unique)
    $EdgeTypes = @($Edges | ForEach-Object { $_.Type } | Where-Object { $_ } | Sort-Object -Unique)
    $Categories = @($Edges | ForEach-Object { $_.Category } | Where-Object { $_ } | Sort-Object -Unique)
    $Filters = [System.Text.StringBuilder]::new()
    foreach ($Definition in @(@('type','Node type',$Types),@('status','Status',$Statuses),@('edge-type','Relationship type',$EdgeTypes),@('category','Category',$Categories))) {
        if ($Definition[2].Count -eq 0) { continue }
        $Key = $Definition[0]; $Label = $Definition[1]
        [void] $Filters.Append('<label>' + (E $Label) + '<select data-psi-rel-filter="' + $Key + '"><option value="">All</option>')
        foreach ($Value in @($Definition[2])) { $Safe = E $Value; [void] $Filters.Append('<option value="' + $Safe + '">' + $Safe + '</option>') }
        [void] $Filters.AppendLine('</select></label>')
        if ($Key -eq 'status') {
            foreach ($Property in @($Properties.FilterProperties)) {
                $DetailLabel=$Property -creplace '([a-z])([A-Z])', '$1 $2'
                $Values=@($Nodes | ForEach-Object { $_.Details } | Where-Object { $_.Label -eq $DetailLabel -and $_.Value } | ForEach-Object { $_.Value } | Sort-Object -Unique)
                if (-not $Values.Count) { continue }
                [void] $Filters.Append('<label>' + (E $DetailLabel) + '<select data-psi-rel-filter-detail="' + (E $DetailLabel) + '"><option value="">All</option>')
                foreach ($Value in $Values) { $Safe=E $Value; [void] $Filters.Append('<option value="' + $Safe + '">' + $Safe + '</option>') }
                [void] $Filters.AppendLine('</select></label>')
            }
        }
    }
    $Main = ''
    if ($Type -eq 'Tree') {
        $Children = @{}
        foreach ($Node in $Nodes) {
            $Parent = [string] $Node.ParentId
            if (-not $Children.ContainsKey($Parent)) { $Children[$Parent] = [System.Collections.Generic.List[object]]::new() }
            $Children[$Parent].Add($Node)
        }
        $Counter = [ref] 0
        $Tree = Branch '' 1 $Children $Counter
        $Main = '<div class="psi-rel-tree-scroll"><ul class="psi-rel-tree" role="tree" aria-label="' + $Title + '">' + $Tree + '</ul></div>'
    }
    elseif ($Type -eq 'Topology') {
        $Main = '<div class="psi-rel-graph-actions"><button type="button" data-psi-rel-zoom="in" aria-label="Zoom in">+</button><button type="button" data-psi-rel-zoom="out" aria-label="Zoom out">-</button><button type="button" data-psi-rel-zoom="fit">Fit</button><button type="button" data-psi-rel-zoom="reset">Reset</button></div><div class="psi-rel-viewport" tabindex="0" role="region" aria-label="Scrollable topology graph"><svg class="psi-rel-graph" data-psi-rel-svg role="group" aria-label="' + $Title + ' graph"></svg></div>'
    }
    $Links = [System.Text.StringBuilder]::new()
    foreach ($Edge in $Edges) {
        $Source = @($Nodes | Where-Object { $_.Id -eq $Edge.SourceId })[0]
        $Target = @($Nodes | Where-Object { $_.Id -eq $Edge.TargetId })[0]
        $Arrow = if ($Edge.Direction -eq 'Bidirectional') { ' &harr; ' } else { ' &rarr; ' }
        [void] $Links.AppendLine('<button type="button" class="psi-rel-edge-item" data-psi-rel-edge="' + (E $Edge.Id) + '"><strong>' + (E $Source.Name) + $Arrow + (E $Target.Name) + '</strong><span>' + (E $Edge.Label) + ' | ' + (E $Edge.Status) + '</span></button>')
    }
    $Empty = if ($Edges.Count -eq 0) { '<p class="psi-rel-empty">No relationships are available in this scope.</p>' } else { '' }
    $List = '<div class="psi-rel-relationship-list" aria-label="Relationship list"><h4>Relationships</h4><div data-psi-rel-edge-list>' + $Links.ToString() + '</div>' + $Empty + '</div>'
    $Diagnostics = if (@($Presentation.Diagnostics).Count) { '<p class="psi-rel-diagnostic" role="status">' + (E (@($Presentation.Diagnostics) -join ' ')) + '</p>' } else { '' }
    $InitialEmpty = if ($Nodes.Count -eq 0) { '<p class="psi-rel-empty">No nodes are available in this scope.</p>' } else { '' }
    $Mode = if ($Type -eq 'RelationshipExplorer') { 'Explorer' } else { $Type }
    $Max = [int] $Properties.MaxNodes
    @"
<section class="psi-rel-component psi-rel-$($Mode.ToLowerInvariant())" id="$Id" data-psi-rel-component data-psi-rel-mode="$Mode" data-psi-rel-max="$Max" aria-label="$Title">
  <header class="psi-rel-header"><div><p class="psi-app-explorer-eyebrow">Relationship workspace</p><h3>$Title</h3></div><span data-psi-rel-count>$($Nodes.Count) nodes / $($Edges.Count) relationships</span></header>
  $Diagnostics
  <div class="psi-rel-toolbar"><label>Search nodes<input type="search" data-psi-rel-search autocomplete="off" placeholder="Find a name"></label>$($Filters.ToString())</div>
  <div class="psi-rel-layout"><div class="psi-rel-main">$InitialEmpty$Main$List<p class="psi-rel-empty" data-psi-rel-filter-empty hidden>No nodes or relationships match these filters.</p></div><aside class="psi-rel-detail" data-psi-rel-detail aria-label="Selected relationship detail" aria-live="polite"><p>Select a node or relationship to inspect details.</p></aside></div>
  $($Icons.ToString())<script type="application/json" data-psi-rel-data>$Json</script>
</section>
"@
}

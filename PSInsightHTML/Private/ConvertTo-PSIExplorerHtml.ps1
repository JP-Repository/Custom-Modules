function ConvertTo-PSIExplorerHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Properties)

    $Id = [string] $Properties.Id
    if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Explorer ID '$Id' is invalid." }
    $Title = ConvertTo-PSIHtmlEncoded -Value $Properties.Title
    $Empty = ConvertTo-PSIHtmlEncoded -Value $Properties.EmptyMessage
    $Data = @($Properties.Data)
    $EntityType = [string] $Properties.EntityType
    $FilterMarkup = [System.Text.StringBuilder]::new()
    foreach ($FilterProperty in @($Properties.FilterProperties)) {
        $SafeProperty = ConvertTo-PSIHtmlEncoded -Value $FilterProperty
        $SafeLabel = ConvertTo-PSIHtmlEncoded -Value (([string] $FilterProperty) -creplace '([a-z])([A-Z])', '$1 $2')
        [void] $FilterMarkup.Append("<label>$SafeLabel<select data-psi-explorer-filter=`"$SafeProperty`"><option value=`"`">All</option>")
        $Values = @($Data | ForEach-Object { Get-PSITableValue -InputObject $_ -Name ([string] $FilterProperty) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | Sort-Object -Unique)
        foreach ($Value in $Values) {
            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $Value
            [void] $FilterMarkup.Append("<option value=`"$SafeValue`">$SafeValue</option>")
        }
        [void] $FilterMarkup.Append('</select></label>')
    }
    $Labels = $Properties.ColumnLabels
    $Details = @($Properties.DetailProperties)
    if ($Details.Count -eq 0 -and $Data.Count -gt 0) {
        if ($Data[0] -is [System.Collections.IDictionary]) { $Details = @($Data[0].Keys) }
        else { $Details = @($Data[0].PSObject.Properties.Name) }
    }
    $List = [System.Text.StringBuilder]::new()
    $Panels = [System.Text.StringBuilder]::new()
    for ($Index = 0; $Index -lt $Data.Count; $Index++) {
        $Record = $Data[$Index]
        $RawTitle = Get-PSITableValue -InputObject $Record -Name ([string] $Properties.TitleProperty)
        $RawSubtitle = if ($Properties.SubtitleProperty) { Get-PSITableValue -InputObject $Record -Name ([string] $Properties.SubtitleProperty) } else { '' }
        $RawStatus = if ($Properties.StatusProperty) { Get-PSITableValue -InputObject $Record -Name ([string] $Properties.StatusProperty) } else { '' }
        $Name = if ($null -eq $RawTitle -or [string]::IsNullOrWhiteSpace([string] $RawTitle)) { '(unnamed)' } else { [string] $RawTitle }
        $SafeName = ConvertTo-PSIHtmlEncoded -Value $Name
        $SafeSubtitle = ConvertTo-PSIHtmlEncoded -Value $RawSubtitle
        $CanonicalStatus = if ($EntityType -in @('Check','Category') -and $RawStatus) { Resolve-PSIAssessmentStatus -Status ([string] $RawStatus) }
            elseif ($EntityType -eq 'Exception' -and $RawStatus) { switch ([string] $RawStatus) { Approved { 'Informational' } Pending { 'Warning' } Expired { 'Critical' } Revoked { 'Neutral' } } }
            else { Resolve-PSIStatus -Status ([string] $RawStatus) -AllowInvalid }
        $Badge = ''
        if ($CanonicalStatus) {
            $Suffix = if ($CanonicalStatus -eq 'NotChecked') { 'not-checked' } else { $CanonicalStatus.ToLowerInvariant() }
            $SafeStatus = ConvertTo-PSIHtmlEncoded -Value $CanonicalStatus
            $DisplayStatus = if ($EntityType -in @('Check','Category','Exception')) { ConvertTo-PSIHtmlEncoded -Value $RawStatus } else { $SafeStatus }
            $Badge = "<span class=`"psi-status-badge psi-status-$Suffix`">$DisplayStatus</span>"
        }
        $Selected = if ($Index -eq 0) { ' aria-selected="true" tabindex="0"' } else { ' aria-selected="false" tabindex="-1"' }
        $EntityAttribute = if ($EntityType) { ' data-psi-entity-id="' + (ConvertTo-PSIHtmlEncoded -Value $Record.Id) + '"' } else { '' }
        if ($EntityType -eq 'Check') { $EntityAttribute += ' data-psi-category-id="' + (ConvertTo-PSIHtmlEncoded -Value $Record.CategoryId) + '"' }
        foreach ($FilterProperty in @($Properties.FilterProperties)) {
            $AttributeName = ([string] $FilterProperty).ToLowerInvariant()
            $EntityAttribute += ' data-psi-filter-' + $AttributeName + '="' + (ConvertTo-PSIHtmlEncoded -Value (Get-PSITableValue -InputObject $Record -Name ([string] $FilterProperty))) + '"'
        }
        [void] $List.AppendLine("<button type=`"button`" class=`"psi-app-explorer-item`" id=`"$Id-item-$Index`" role=`"tab`" data-psi-explorer-item=`"$Index`" aria-controls=`"$Id-detail-$Index`"$EntityAttribute$Selected><span class=`"psi-app-explorer-item-copy`"><strong>$SafeName</strong><small>$SafeSubtitle</small></span>$Badge</button>")
        $Hidden = if ($Index -eq 0) { '' } else { ' hidden' }
        [void] $Panels.AppendLine("<article class=`"psi-app-explorer-detail`" id=`"$Id-detail-$Index`" role=`"tabpanel`" aria-labelledby=`"$Id-item-$Index`" data-psi-explorer-detail=`"$Index`"$Hidden>")
        if ($EntityType -in @('Finding','Resource','Evidence')) {
            [void] $Panels.AppendLine((ConvertTo-PSIIntelligenceDetailHtml -Kind $EntityType -Record $Record -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        elseif ($EntityType -in @('Check','Category')) {
            [void] $Panels.AppendLine((ConvertTo-PSIAssessmentDetailHtml -Kind $EntityType -Record $Record -Assessment $Properties.Assessment -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        elseif ($EntityType -eq 'Exception') {
            [void] $Panels.AppendLine((ConvertTo-PSIAssessmentExceptionHtml -Record $Record -Assessment $Properties.Assessment -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        else {
            [void] $Panels.AppendLine("<p class=`"psi-app-explorer-detail-eyebrow`">Selected record</p><h4>$SafeName</h4><dl>")
            foreach ($PropertyName in $Details) {
                $Label = if ($Labels.ContainsKey($PropertyName)) { [string] $Labels[$PropertyName] } else { ([string] $PropertyName -creplace '([a-z])([A-Z])', '$1 $2') }
                $Value = Get-PSITableValue -InputObject $Record -Name ([string] $PropertyName)
                if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { $ValueText = [string] [char] 0x2014 }
                elseif ($Value -is [string] -or $Value.GetType().IsValueType) { $ValueText = [string] $Value }
                else { $ValueText = ConvertTo-Json -InputObject $Value -Depth 5 -Compress }
                $SafeLabel = ConvertTo-PSIHtmlEncoded -Value $Label
                $SafeValue = ConvertTo-PSIHtmlEncoded -Value $ValueText
                [void] $Panels.AppendLine("<div><dt>$SafeLabel</dt><dd>$SafeValue</dd></div>")
            }
            [void] $Panels.AppendLine('</dl>')
        }
        [void] $Panels.AppendLine('</article>')
    }
    $Count = $Data.Count
    $EmptyAttribute = if ($Count -eq 0) { '' } else { ' hidden' }
    @"
<section class="psi-app-explorer" id="$Id" data-psi-app-explorer data-psi-entity-type="$EntityType" aria-label="$Title">
  <header class="psi-app-explorer-header"><div><p class="psi-app-explorer-eyebrow">Collection workspace</p><h3>$Title</h3></div><span data-psi-explorer-count aria-live="polite">$Count records</span></header>
  <div class="psi-app-explorer-grid"><div class="psi-app-explorer-master"><label for="$Id-search">Search records</label><input id="$Id-search" type="search" data-psi-explorer-search autocomplete="off" placeholder="Search this collection"><div class="psi-app-explorer-filters">$($FilterMarkup.ToString())</div><div class="psi-app-explorer-list" role="tablist" aria-orientation="vertical" aria-label="$Title records">$($List.ToString())</div><p class="psi-app-explorer-empty" data-psi-explorer-empty$EmptyAttribute>$Empty</p></div><div class="psi-app-explorer-details">$($Panels.ToString())</div></div>
</section>
"@
}

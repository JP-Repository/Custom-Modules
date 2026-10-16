function ConvertTo-PSIIntelligenceDetailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Finding','Resource','Evidence')][string] $Kind,
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $TitleField = switch ($Kind) { Finding { 'Title' } Resource { 'Name' } Evidence { 'Title' } }
    $Title = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record -Name $TitleField)
    $IconName = switch ($Kind) { Finding { 'SeverityWarning' } Resource { 'ResourceServer' } Evidence { 'Document' } }
    $Icon = Get-PSIIcon -Name $IconName
    $FindingView = [string] $LinkViews.Finding
    $ResourceView = [string] $LinkViews.Resource
    $EvidenceView = [string] $LinkViews.Evidence
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">$Kind investigation</p><h4>$Title</h4></div></header>")
    if ($Kind -eq 'Finding') {
        $Severity = ConvertTo-PSIHtmlEncoded -Value $Record.Severity
        $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
        $Category = ConvertTo-PSIHtmlEncoded -Value $Record.Category
        $Summary = ConvertTo-PSIHtmlEncoded -Value $Record.Summary
        $BadgeClass = if ($Record.Severity -eq 'Info') { 'informational' } else { ([string] $Record.Severity).ToLowerInvariant() }
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span class=`"psi-status-badge psi-status-$BadgeClass`">$Severity</span><span>$Status</span><span>$Category</span></div><p class=`"psi-intelligence-summary`">$Summary</p>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Affected resources</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.AffectedResourceIds) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        [void] $B.AppendLine('</section>')
        $Expected = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name ExpectedState -DefaultValue 'Not specified')
        $Observed = ConvertTo-PSIHtmlEncoded -Value $Record.ReadinessImpact
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Observed / Expected</h5><dl><div><dt>Observed impact</dt><dd>$Observed</dd></div><div><dt>Expected state</dt><dd>$Expected</dd></div></dl></section>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View $EvidenceView -LabelProperty Title))
        [void] $B.AppendLine('</section>')
        $Action = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Action -DefaultValue 'Not specified')
        $Rationale = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Rationale -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Recommendation</h5><p>$Action</p><small>$Rationale</small></section>")
        $Method = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name Method -DefaultValue 'Not specified')
        $Result = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name ExpectedResult -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Validation</h5><p>$Method</p><small>$Result</small></section>")
        if (@($Record.Relationships).Count) {
            [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Relationships</h5>')
            foreach ($Id in @($Record.Relationships)) {
                $Relationship = @($Model.Relationships | Where-Object { $_.Id -ieq [string] $Id })[0]
                if ($null -ne $Relationship) { [void] $B.AppendLine('<p>' + (ConvertTo-PSIHtmlEncoded -Value "$($Relationship.Type): $($Relationship.SourceResourceId) -> $($Relationship.TargetResourceId)") + '</p>') }
            }
            [void] $B.AppendLine('</section>')
        }
    }
    elseif ($Kind -eq 'Resource') {
        $Type = ConvertTo-PSIHtmlEncoded -Value $Record.Type
        $Status = Resolve-PSIStatus -Status ([string] $Record.Status)
        $BadgeClass = if ($Status -eq 'NotChecked') { 'not-checked' } else { $Status.ToLowerInvariant() }
        $SafeStatus = ConvertTo-PSIHtmlEncoded -Value $Status
        $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span>$Type</span><span class=`"psi-status-badge psi-status-$BadgeClass`">$SafeStatus</span></div><p class=`"psi-intelligence-summary`">$Description</p>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Properties</h5><dl>')
        foreach ($Key in @($Record.Properties.Keys | Sort-Object)) {
            $SafeKey = ConvertTo-PSIHtmlEncoded -Value $Key
            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $Record.Properties[$Key]
            [void] $B.AppendLine("<div><dt>$SafeKey</dt><dd>$SafeValue</dd></div>")
        }
        [void] $B.AppendLine('</dl></section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View $FindingView -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View $EvidenceView -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Relationships</h5>')
        foreach ($Id in @($Record.RelationshipIds)) {
            $Relationship = @($Model.Relationships | Where-Object { $_.Id -ieq [string] $Id })[0]
            if ($null -eq $Relationship) { continue }
            $OtherId = if ($Relationship.SourceResourceId -ieq $Record.Id) { $Relationship.TargetResourceId } else { $Relationship.SourceResourceId }
            [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($OtherId) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        }
        [void] $B.AppendLine('</section>')
    }
    else {
        $Type = ConvertTo-PSIHtmlEncoded -Value $Record.Type
        $Source = ConvertTo-PSIHtmlEncoded -Value $Record.Source
        $Summary = ConvertTo-PSIHtmlEncoded -Value $Record.Summary
        $Timestamp = if ($Record.CollectedAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.CollectedAt).ToString('yyyy-MM-dd HH:mm') } else { 'Not supplied' }
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span>$Type</span><span>$Source</span><span>$Timestamp</span></div><p class=`"psi-intelligence-summary`">$Summary</p>")
        $RawData = if ($Record.Data -is [string]) { [string] $Record.Data } else { ConvertTo-Json -InputObject $Record.Data -Depth 8 }
        $SafeData = ConvertTo-PSIHtmlEncoded -Value $RawData
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Observed data</h5><pre>$SafeData</pre></section><section class=`"psi-intelligence-block`"><h5>Resources</h5>")
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View $FindingView -LabelProperty Title))
        [void] $B.AppendLine('</section>')
    }
    $B.ToString()
}

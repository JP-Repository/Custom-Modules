function ConvertTo-PSIAssessmentExceptionHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $Icon = Get-PSIIcon -Name 'SeverityInfo'
    $Title = ConvertTo-PSIHtmlEncoded -Value $Record.Title
    $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
    $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
    $Reason = ConvertTo-PSIHtmlEncoded -Value $Record.Reason
    $Owner = ConvertTo-PSIHtmlEncoded -Value $Record.Owner
    $Approver = ConvertTo-PSIHtmlEncoded -Value $Record.ApprovedBy
    $Approved = if ($Record.ApprovedAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.ApprovedAt).ToString('yyyy-MM-dd') } else { 'Not supplied' }
    $Expiry = if ($Record.ExpiresAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.ExpiresAt).ToString('yyyy-MM-dd') } else { 'Not supplied' }
    $Expiring = $Record.Status -eq 'Approved' -and $Record.ExpiresAt -and
        $Record.ExpiresAt -gt $Assessment.GeneratedAt -and $Record.ExpiresAt -le $Assessment.GeneratedAt.AddDays(7)
    $ExpiryFlag = if ($Expiring) { '<strong class="psi-assessment-blocker">Expires within seven days</strong>' } else { '' }
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">Assessment exception</p><h4>$Title</h4></div></header><div class=`"psi-intelligence-meta`"><span>$Status</span>$ExpiryFlag</div><p class=`"psi-intelligence-summary`">$Description</p><section class=`"psi-intelligence-block`"><h5>Reason and ownership</h5><dl><div><dt>Reason</dt><dd>$Reason</dd></div><div><dt>Owner</dt><dd>$Owner</dd></div><div><dt>Approved by</dt><dd>$Approver</dd></div><div><dt>Approved at</dt><dd>$Approved</dd></div><div><dt>Expires at</dt><dd>$Expiry</dd></div></dl></section>")
    [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Linked check</h5>')
    $CheckIds = if ($Record.CheckId) { @($Record.CheckId) } else { @() }
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids $CheckIds -Records $Assessment.Checks -View ([string] $LinkViews.Check) -LabelProperty Name))
    [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Linked finding</h5>')
    $FindingIds = if ($Record.FindingId) { @($Record.FindingId) } else { @() }
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids $FindingIds -Records $Model.Findings -View ([string] $LinkViews.Finding) -LabelProperty Title))
    [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Affected resources</h5>')
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View ([string] $LinkViews.Resource) -LabelProperty Name))
    [void] $B.AppendLine('</section><p class="psi-intelligence-muted">Exceptions are documented here; they do not automatically change the posture decision.</p>')
    $B.ToString()
}

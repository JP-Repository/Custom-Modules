function ConvertTo-PSIIntelligenceLinksHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Ids,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Records,
        [Parameter(Mandatory = $true)][string] $View,
        [Parameter(Mandatory = $true)][string] $LabelProperty
    )
    if ($Ids.Count -eq 0) { return '<p class="psi-intelligence-muted">None linked in this sample.</p>' }
    $Builder = [System.Text.StringBuilder]::new()
    [void] $Builder.Append('<div class="psi-intelligence-links">')
    foreach ($Id in $Ids) {
        $Record = @($Records | Where-Object { $_.Id -ieq [string] $Id })[0]
        if ($null -eq $Record) { continue }
        $SafeId = ConvertTo-PSIHtmlEncoded -Value $Id
        $Label = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record -Name $LabelProperty)
        [void] $Builder.Append("<button type=`"button`" class=`"psi-intelligence-link`" data-psi-cross-view=`"$View`" data-psi-cross-id=`"$SafeId`">$Label <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $Builder.Append('</div>')
    $Builder.ToString()
}

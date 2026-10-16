function ConvertTo-PSIApplicationShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][string] $Styles,
        [Parameter(Mandatory = $true)][string] $Sections,
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]] $Navigation,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Dialog,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $ExportToolbar,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $ExportScript,
        [Parameter(Mandatory = $true)][string] $StatusScript,
        [Parameter(Mandatory = $true)][string] $InteractionScript,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $TableScript,
        [Parameter()][bool] $HasTableSearch = $false,
        [Parameter()][bool] $IsMultiView = $false
    )

    $Title = ConvertTo-PSIHtmlEncoded -Value $Report.Title
    $Subtitle = ConvertTo-PSIHtmlEncoded -Value $Report.Subtitle
    $GeneratedOn = ConvertTo-PSIHtmlEncoded -Value ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $ModuleVersion = ConvertTo-PSIHtmlEncoded -Value $Report.ModuleVersion
    $Theme = [string] $Report.Theme
    $NavMarkup = [System.Text.StringBuilder]::new()
    foreach ($Group in $Navigation) {
        $GroupLabel = ConvertTo-PSIHtmlEncoded -Value $Group.Label
        [void] $NavMarkup.AppendLine("<div class=`"psi-app-nav-group`"><p class=`"psi-app-nav-heading`">$GroupLabel</p><ul>")
        foreach ($Item in $Group.Items) {
            $ItemId = 'psi-app-item-' + $Item.Id
            $ItemLabel = ConvertTo-PSIHtmlEncoded -Value $Item.Label
            $Regular = (Get-PSIIcon -Name $Item.Icon -Variant Regular -Size 20 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-regular"')
            $Filled = (Get-PSIIcon -Name $Item.Icon -Variant Filled -Size 20 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-filled"')
            $Icon = '<span class="psi-app-nav-icon">' + $Regular + $Filled + '</span>'
            $Badge = if ([string]::IsNullOrWhiteSpace($Item.Badge)) { '' } else {
                '<span class="psi-app-nav-badge">' + (ConvertTo-PSIHtmlEncoded -Value $Item.Badge) + '</span>'
            }
            if ($Item.Disabled) {
                [void] $NavMarkup.AppendLine("<li><span id=`"$ItemId`" class=`"psi-app-nav-item`" aria-disabled=`"true`">$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</span></li>")
            }
            else {
                $Current = if ($Item.Selected) {
                    if ($IsMultiView) { ' aria-current="page"' } else { ' aria-current="location"' }
                } else { '' }
                if ($IsMultiView) {
                    [void] $NavMarkup.AppendLine("<li><button type=`"button`" id=`"$ItemId`" class=`"psi-app-nav-item`" data-psi-app-item data-psi-app-view-target=`"$($Item.Id)`" aria-controls=`"$($Item.Target)`"$Current>$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</button></li>")
                }
                else {
                    [void] $NavMarkup.AppendLine("<li><a id=`"$ItemId`" class=`"psi-app-nav-item`" href=`"#$($Item.Target)`" data-psi-app-item$Current>$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</a></li>")
                }
            }
        }
        [void] $NavMarkup.AppendLine('</ul></div>')
    }

    $IconRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/Icons/Fluent'
    $License = ConvertTo-PSIHtmlEncoded -Value (Get-Content -LiteralPath (Join-Path $IconRoot 'LICENSE') -Raw -ErrorAction Stop)
    $Notice = ConvertTo-PSIHtmlEncoded -Value (Get-Content -LiteralPath (Join-Path $IconRoot 'NOTICE') -Raw -ErrorAction Stop)
    $AppScript = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-application.js') -Raw -ErrorAction Stop
    $MenuIcon = Get-PSIIcon -Name Menu -Size 22 -Strict
    $CloseIcon = Get-PSIIcon -Name AppClose -Size 20 -Strict
    $LightIcon = Get-PSIIcon -Name ThemeLight -Size 18 -Strict
    $DarkIcon = Get-PSIIcon -Name ThemeDark -Size 18 -Strict
    $AutoIcon = Get-PSIIcon -Name AppSettings -Size 18 -Strict
    $InfoIcon = Get-PSIIcon -Name SeverityInfo -Size 16 -Strict
    $SearchButton = if ($HasTableSearch) {
        $SearchIcon = Get-PSIIcon -Name NavigationSearch -Size 19 -Strict
        '<button type="button" class="psi-app-table-search-shortcut" data-psi-app-find-table aria-label="Find in the active view">' + $SearchIcon + '<span>Find in view</span></button>'
    }
    else { '' }
    $WorkspaceMode = if ($IsMultiView) { 'Views' } else { 'Document' }
    $CommandHeading = "<p class=`"psi-app-eyebrow`">PSInsightHTML | Report workspace</p><h1>$Title</h1><p class=`"psi-app-subtitle`">$Subtitle</p>"
    $ContextHeading = 'Snapshot details'
    $ViewCommandMarkup = [System.Text.StringBuilder]::new()
    if ($IsMultiView) {
        $InitialView = @($Report.Views | Where-Object { $_.State.Initial })[0]
        if ($null -eq $InitialView) { $InitialView = $Report.Views[0] }
        $ViewTitle = ConvertTo-PSIHtmlEncoded -Value $InitialView.Title
        $ViewSubtitle = ConvertTo-PSIHtmlEncoded -Value $InitialView.Subtitle
        $CommandHeading = "<p class=`"psi-app-eyebrow`">$Title | PSInsightHTML</p><h1 id=`"psi-app-active-view-title`" data-psi-app-view-title>$ViewTitle</h1><p class=`"psi-app-subtitle`" data-psi-app-view-subtitle>$ViewSubtitle</p>"
        $ContextHeading = '<span data-psi-app-context-title>' + $ViewTitle + '</span> details'
        foreach ($View in $Report.Views) {
            $Hidden = if ($View.Id -cne $InitialView.Id) { ' hidden' } else { '' }
            foreach ($Command in $View.Commands) {
                $SafeLabel = ConvertTo-PSIHtmlEncoded -Value $Command.Label
                $CommandIcon = Get-PSIIcon -Name $Command.Icon -Size 18 -Strict
                [void] $ViewCommandMarkup.AppendLine("<button type=`"button`" class=`"psi-app-view-command`" data-psi-app-command-view=`"$($View.Id)`" data-psi-app-command-target=`"$($Command.TargetView)`" aria-label=`"$SafeLabel`"$Hidden>$CommandIcon<span>$SafeLabel</span></button>")
            }
        }
    }

    @"
<!DOCTYPE html>
<html lang="en" data-theme="$Theme" data-psi-layout="Application" data-psi-workspace="$WorkspaceMode">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$Title</title>
  <style>
$Styles
  </style>
</head>
<body>
  <div class="psi-app-shell">
    <aside class="psi-app-sidebar" id="psi-app-navigation" aria-label="Report navigation">
      <div class="psi-app-brand"><span class="psi-app-brand-mark" aria-hidden="true"><svg viewBox="0 0 48 48" width="27" height="27" fill="none"><path d="M24 3 43 14v20L24 45 5 34V14L24 3Z" stroke="currentColor" stroke-width="2.5"/><path d="M15 31V17h8a5 5 0 0 1 0 10h-4M27 31h7M27 31a4 4 0 0 1 0-8h7" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></span><span><strong>PSInsightHTML</strong><small>Report workspace</small></span><button type="button" class="psi-app-nav-close" data-psi-app-close aria-label="Close navigation">$CloseIcon</button></div>
      <nav aria-label="Report sections">
$($NavMarkup.ToString())      </nav>
      <p class="psi-app-sidebar-foot">Standalone report | Module v$ModuleVersion</p>
    </aside>
    <div class="psi-app-scrim" data-psi-app-scrim hidden></div>
    <div class="psi-app-body">
      <header class="psi-app-command" id="psi-app-command">
        <div class="psi-app-command-leading"><button type="button" id="psi-app-nav-toggle" class="psi-app-menu-button" data-psi-app-toggle aria-controls="psi-app-navigation" aria-expanded="false" aria-label="Open navigation" title="Open navigation">$MenuIcon</button><div class="psi-app-heading">$CommandHeading</div></div>
        <div class="psi-app-command-actions">$($ViewCommandMarkup.ToString())$SearchButton<div class="psi-theme-control" role="group" aria-label="Report color theme"><button type="button" data-psi-theme="Light" aria-pressed="false">$LightIcon<span>Light</span></button><button type="button" data-psi-theme="Dark" aria-pressed="false">$DarkIcon<span>Dark</span></button><button type="button" data-psi-theme="Auto" aria-pressed="false">$AutoIcon<span>Auto</span></button></div>$ExportToolbar</div>
      </header>
      <main class="psi-app-workspace" id="psi-app-main">
        <div class="psi-app-content">$Sections</div>
        <aside class="psi-app-context" aria-label="Report context"><div class="psi-app-context-card"><p class="psi-app-context-eyebrow">$InfoIcon Report context</p><h2>$ContextHeading</h2><dl><div><dt>Generated</dt><dd>$GeneratedOn</dd></div><div><dt>Module</dt><dd>v$ModuleVersion</dd></div><div><dt>Theme</dt><dd data-psi-theme-value>$Theme</dd></div></dl><p>This standalone view contains its data and presentation assets.</p></div></aside>
      </main>
      <footer class="psi-app-footer">Generated by PSInsightHTML | Theme <span data-psi-theme-footer>$Theme</span></footer>
    </div>
  </div>
  <template id="psi-fluent-icon-attribution"><pre>$License

$Notice</pre></template>
  $Dialog
  $ExportScript
  $StatusScript
  $InteractionScript
  $TableScript
  <script>
$AppScript
  </script>
</body>
</html>
"@
}

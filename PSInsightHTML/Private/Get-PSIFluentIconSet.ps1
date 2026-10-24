function Get-PSIFluentIconSet {
    <#
    .SYNOPSIS
    Resolve the icon roles used by the Fluent renderer to inline SVG markup.

    .DESCRIPTION
    Resolution order per role:
      1. Curated Fluent System Icons SVG in Assets/Icons/Fluent (MIT, see NOTICE).
      2. The same Fluent glyph extracted from the Windows "Segoe Fluent Icons" font
         (Windows 11) or "Segoe MDL2 Assets" (Windows 10) at export time.
      3. The legacy PSInsightHTML stroke icon of the closest meaning.
    Every report embeds the resolved SVG, so it renders identically offline.
    #>
    [CmdletBinding()]
    param()

    if ($script:PSIFluentIconCache) { return $script:PSIFluentIconCache }

    # role = curated file stem | Segoe code point | legacy fallback
    $Roles = [ordered]@{
        home         = @('home', 0xE80F, 'dashboard');           search      = @('search', 0xE721, 'search')
        menu         = @('navigation', 0xE700, 'dashboard');     settings    = @('settings', 0xE713, 'settings')
        sun          = @('weather_sunny', 0xE706, 'theme/light'); moon       = @('weather_moon', 0xE708, 'theme/dark')
        document     = @('document', 0xE8A5, 'file');            rules       = @('document_bullet_list', 0xE9D5, 'file')
        chevronD     = @('chevron_down', 0xE70D, 'chevron');     close       = @('dismiss', 0xE711, 'close')
        warning      = @('warning', 0xE7BA, 'warning');          critical    = @('error_circle', 0xEB90, 'critical')
        healthy      = @('checkmark_circle', 0xE930, 'healthy'); info        = @('info', 0xE946, 'info')
        server       = @('server', 0xE968, 'server');            shield      = @('shield', 0xEA18, 'security')
        relationship = @('branch_fork', 0xF168, 'network');      download    = @('arrow_download', 0xE896, 'arrow')
        chevronR     = @('chevron_right', 0xE76C, 'arrow');      chevronU    = @('chevron_up', 0xE70E, 'chevron')
        copy         = @('copy', 0xE8C8, 'file');                filter      = @('filter', 0xE71C, 'search')
        print        = @('print', 0xE749, 'print');              link        = @('link', 0xE71B, 'arrow')
        unknown      = @('question_circle', 0xE9CE, 'info');     blocked     = @('prohibited', 0xE733, 'critical')
        clock        = @('clock', 0xE823, 'info');               calendar    = @('calendar', 0xE787, 'info')
        list         = @('text_bullet_list', 0xE8FD, 'file');    grid        = @('grid', 0xE8A9, 'dashboard')
        chart        = @('data_bar_vertical', 0xE9D2, 'dashboard'); pie      = @('data_pie', 0xEB05, 'dashboard')
        people       = @('people', 0xE716, 'users');             person      = @('person', 0xE77B, 'users')
        group        = @('people_team', 0xE902, 'users');        computer    = @('desktop', 0xE7F8, 'server')
        globe        = @('globe', 0xE774, 'network');            key         = @('key', 0xE192, 'security')
        lock         = @('lock_closed', 0xE72E, 'security');     sync        = @('arrow_sync', 0xE895, 'replication')
        flag         = @('flag', 0xE7C1, 'warning');             tag         = @('tag', 0xE8EC, 'file')
        mail         = @('mail', 0xE715, 'file');                folder      = @('folder', 0xE8B7, 'file')
        layers       = @('layer', 0xE81E, 'dashboard');          tree        = @('tree', 0xF168, 'network')
        arrowRight   = @('arrow_right', 0xF0AF, 'arrow');        openNew     = @('open', 0xE8A7, 'arrow')
        view         = @('eye', 0xE890, 'search');               more        = @('more_horizontal', 0xE712, 'dashboard')
        important    = @('important', 0xE8C9, 'warning');        shieldAlert = @('shield_error', 0xE730, 'security')
        checklist    = @('task_list_ltr', 0xE9D5, 'file');       sliders     = @('options', 0xE9E9, 'settings')
        admin        = @('person_key', 0xE7EF, 'security');      history     = @('history', 0xE81C, 'info')
        check        = @('checkmark', 0xE73E, 'healthy');        domain      = @('building', 0xE80F, 'domain')
        database     = @('database', 0xEE94, 'database');        network     = @('network', 0xE968, 'network')
        cloud        = @('cloud', 0xE753, 'cloud');              certificate = @('certificate', 0xEB95, 'certificate')
        diagnostic   = @('pulse', 0xE9D9, 'dashboard');          report      = @('document_data', 0xE9F9, 'file')
        lightbulb    = @('lightbulb', 0xEA80, 'info');           wrench      = @('wrench', 0xE90F, 'settings')
    }

    $IconDirectory = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Assets/Icons/Fluent'
    $Typeface = $null
    $FontPath = @("$env:WINDIR\Fonts\SegoeIcons.ttf", "$env:WINDIR\Fonts\segmdl2.ttf") |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if ($FontPath) {
        try {
            Add-Type -AssemblyName PresentationCore -ErrorAction Stop
            $Typeface = [System.Windows.Media.GlyphTypeface]::new([Uri]('file:///' + ($FontPath -replace '\\', '/')))
        }
        catch { $Typeface = $null }
    }
    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture

    $Set = [ordered]@{}
    $Sources = @{ Curated = 0; Font = 0; Legacy = 0 }
    foreach ($Role in $Roles.Keys) {
        $Stem, $CodePoint, $Legacy = $Roles[$Role]
        $Svg = $null
        $Curated = Join-Path -Path $IconDirectory -ChildPath ($Stem + '_24_regular.svg')
        if (Test-Path -LiteralPath $Curated -PathType Leaf) {
            $Paths = [regex]::Matches([System.IO.File]::ReadAllText($Curated), '<path[^>]*\sd="([^"]+)"') | ForEach-Object { '<path d="' + $_.Groups[1].Value + '"/>' }
            if ($Paths) { $Svg = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">' + ($Paths -join '') + '</svg>'; $Sources.Curated++ }
        }
        if (-not $Svg -and $Typeface) {
            $Glyph = 0
            if ($Typeface.CharacterToGlyphMap.TryGetValue([int] $CodePoint, [ref] $Glyph)) {
                $Geometry = [System.Windows.Media.PathGeometry]::CreateFromGeometry($Typeface.GetGlyphOutline($Glyph, 24, 24))
                $Data = $Geometry.ToString($Invariant) -replace '^F[01]', ''
                $Data = [regex]::Replace($Data, '-?\d+\.\d+', { param($M) [math]::Round([double]::Parse($M.Value, $Invariant), 2).ToString($Invariant) })
                if ($Data) {
                    $Rule = if ($Geometry.FillRule -eq 'EvenOdd') { 'evenodd' } else { 'nonzero' }
                    $Svg = '<svg viewBox="0 -24 24 24" fill="currentColor" fill-rule="' + $Rule + '" aria-hidden="true" focusable="false"><path d="' + $Data + '"/></svg>'
                    $Sources.Font++
                }
            }
        }
        if (-not $Svg) {
            $Svg = (Get-PSIIcon -Name $Legacy -Size 24) -replace ' width="24" height="24"', ''
            $Sources.Legacy++
        }
        $Set[$Role] = $Svg
    }
    Write-Verbose ("Fluent icon set: {0} curated SVG, {1} font glyph, {2} legacy" -f $Sources.Curated, $Sources.Font, $Sources.Legacy)
    $script:PSIFluentIconCache = $Set
    $Set
}

[CmdletBinding()]
param([Parameter()][string] $OutputPath)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ModuleRoot 'Reports/PSInsightHTML-Fluent-Icon-Showcase.html'
}

# A development fixture: show real embedded geometry for both curated variants.
$Roles = @(
    @{ Name='Home'; Key='NavigationHome' },
    @{ Name='Warning'; Key='SeverityWarning' },
    @{ Name='Shield'; Key='SecurityShield' },
    @{ Name='Server'; Key='ResourceServer' },
    @{ Name='Policy'; Key='Rules' },
    @{ Name='Relationship'; Key='Relationship' },
    @{ Name='Document'; Key='Document' },
    @{ Name='Settings'; Key='AppSettings' }
)
$Rows = [System.Text.StringBuilder]::new()
foreach ($Role in $Roles) {
    $Icons = & (Get-Module PSInsightHTML) {
        param($Key)
        @((Get-PSIIcon -Name $Key -Variant Regular -Size 28 -Strict),
          (Get-PSIIcon -Name $Key -Variant Filled -Size 28 -Strict))
    } $Role.Key
    [void] $Rows.AppendLine('<tr><th scope="row">' + $Role.Name + '</th><td>' + $Icons[0] + '</td><td>' + $Icons[1] + '</td></tr>')
}
$ThemeCss = [System.IO.File]::ReadAllText((Join-Path $ModuleRoot 'Assets/CSS/psi-theme.css'))
$IconRoot = Join-Path $ModuleRoot 'Assets/Icons/Fluent'
$Attribution = [System.Net.WebUtility]::HtmlEncode(
    ([System.IO.File]::ReadAllText((Join-Path $IconRoot 'LICENSE')) + "`n" +
     [System.IO.File]::ReadAllText((Join-Path $IconRoot 'NOTICE'))))
$Css = @'
body{max-width:800px;margin:0 auto;padding:32px;font:14px/1.5 system-ui,sans-serif;background:var(--psi-page);color:var(--psi-text)}
h1{font-size:28px;letter-spacing:-.03em}p{color:var(--psi-text-secondary)}
table{width:100%;border-collapse:collapse;background:var(--psi-surface);border:1px solid var(--psi-border)}
th,td{padding:12px 18px;border-bottom:1px solid var(--psi-border);text-align:left}
td svg{color:var(--psi-accent);vertical-align:middle}thead th{background:var(--psi-surface-interactive)}
'@
$Markup = @"
<!DOCTYPE html>
<html lang="en" data-theme="Auto">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>PSInsightHTML Fluent icon showcase</title><style>$ThemeCss`n$Css</style></head>
<body><main><h1>Fluent icon showcase</h1><p>Curated Microsoft Fluent System Icons. Both variants contain embedded SVG paths and inherit the theme accent.</p>
<table><thead><tr><th>Name</th><th>Regular</th><th>Filled</th></tr></thead><tbody>$($Rows.ToString())</tbody></table></main><template id="psi-fluent-icon-attribution"><pre>$Attribution</pre></template></body></html>
"@
$Directory = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw "Output directory '$Directory' does not exist." }
[System.IO.File]::WriteAllText($OutputPath, $Markup, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated Fluent icon showcase: $OutputPath"

function Get-PSIEmailObjectValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object] $InputObject,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $InputObject.Keys) {
            if ([string]::Equals([string] $Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $InputObject[$Key]
            }
        }
        return $null
    }
    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $Property) { return $Property.Value }
    return $null
}

function ConvertTo-PSIEmailComponentMarkup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Component,
        [Parameter(Mandatory = $true)][ValidateNotNull()][System.Collections.IDictionary] $TemplateStyle
    )

    $Properties = $Component.Properties
    if ($Properties -isnot [System.Collections.IDictionary]) {
        throw "Email component '$($Component.Type)' Properties must implement IDictionary."
    }

    switch ($Component.Type) {
        'Text' {
            $FontSize = switch ([string] $Properties.Size) {
                'Small' { '13px' }
                'Large' { '20px' }
                default { '14px' }
            }
            $Weight = if ([string] $Properties.Size -eq 'Large') { '600' } else { '400' }
            return '<div style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:{0};font-weight:{1};line-height:1.5;color:#334155;">{2}</div>' -f `
                $FontSize, $Weight, (ConvertTo-PSIEmailHtmlEncoded $Properties.Text)
        }
        'KPI' {
            $Status = Resolve-PSIEmailStatus ([string] $Properties.Status)
            $Colors = Get-PSIEmailStatusStyle $Status
            $Subtitle = if ([string]::IsNullOrWhiteSpace([string] $Properties.Subtitle)) { '' } else {
                '<div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;mso-line-height-rule:exactly;color:#64748b;">{0}</div>' -f (ConvertTo-PSIEmailHtmlEncoded $Properties.Subtitle)
            }
            return @'
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:separate;border:1px solid #dbe3ec;border-top:3px solid {0};border-radius:5px;background-color:#ffffff;">
  <tr><td style="padding:16px;">
    <div style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;font-weight:600;line-height:16px;mso-line-height-rule:exactly;color:#64748b;text-transform:uppercase;letter-spacing:0.1px;">{1}</div>
    <div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:30px;font-weight:600;line-height:34px;mso-line-height-rule:exactly;color:#172033;">{2}</div>
    {3}
    <div style="padding-top:8px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:11px;font-weight:600;line-height:14px;mso-line-height-rule:exactly;color:{4};text-transform:uppercase;letter-spacing:0.1px;">{5}</div>
  </td></tr>
</table>
'@ -f $Colors.Border, (ConvertTo-PSIEmailHtmlEncoded $Properties.Title),
                (ConvertTo-PSIEmailHtmlEncoded $Properties.Value), $Subtitle, $Colors.Text,
                (ConvertTo-PSIEmailHtmlEncoded $Status)
        }
        'KeyValue' {
            $Builder = [System.Text.StringBuilder]::new()
            [void] $Builder.Append(('<table width="100%" cellpadding="0" cellspacing="0" border="0" aria-label="{0}" style="width:100%;border-collapse:collapse;border:1px solid #dbe3ec;background-color:#ffffff;">' -f (ConvertTo-PSIEmailHtmlEncoded $Properties.Title)))
            [void] $Builder.Append(('<thead><tr><th colspan="2" align="left" style="padding:12px 16px;background-color:{0};border-left:3px solid {1};border-bottom:1px solid #dbe3ec;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:15px;font-weight:600;line-height:20px;mso-line-height-rule:exactly;color:#172033;">' -f $TemplateStyle.AccentSoft, $TemplateStyle.Accent))
            [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Properties.Title))
            [void] $Builder.Append('</th></tr></thead><tbody>')
            foreach ($Key in $Properties.Data.Keys) {
                [void] $Builder.Append('<tr>')
                [void] $Builder.Append('<th scope="row" width="55%" valign="top" align="left" style="width:55%;padding:8px 12px;border-bottom:1px solid #edf1f5;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;font-weight:600;line-height:18px;mso-line-height-rule:exactly;color:#64748b;">')
                [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Key))
                [void] $Builder.Append('</th><td width="45%" valign="top" align="right" style="width:45%;padding:8px 12px;border-bottom:1px solid #edf1f5;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:14px;font-weight:500;line-height:20px;mso-line-height-rule:exactly;color:#172033;">')
                [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Properties.Data[$Key]))
                [void] $Builder.Append('</td></tr>')
            }
            [void] $Builder.Append('</tbody></table>')
            return $Builder.ToString()
        }
        'Alert' {
            $Status = Resolve-PSIEmailStatus ([string] $Properties.Status)
            $Colors = Get-PSIEmailStatusStyle $Status
            return @'
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:separate;border-left:4px solid {0};background-color:{1};">
  <tr><td style="padding:12px 16px;">
    <div style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:11px;font-weight:600;line-height:14px;mso-line-height-rule:exactly;color:{2};text-transform:uppercase;letter-spacing:0.1px;">{3}</div>
    <div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:16px;font-weight:600;line-height:22px;mso-line-height-rule:exactly;color:#172033;">{4}</div>
    <div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:14px;line-height:21px;mso-line-height-rule:exactly;color:#475569;">{5}</div>
  </td></tr>
</table>
'@ -f $Colors.Border, $Colors.Background, $Colors.Text,
                (ConvertTo-PSIEmailHtmlEncoded $Status),
                (ConvertTo-PSIEmailHtmlEncoded $Properties.Title),
                (ConvertTo-PSIEmailHtmlEncoded $Properties.Message)
        }
        'Banner' {
            $Status = Resolve-PSIEmailStatus ([string] $Properties.Status)
            $Colors = Get-PSIEmailStatusStyle $Status
            return @'
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:separate;border:1px solid {0};border-left:6px solid {0};background-color:{1};">
  <tr>
    <td width="104" valign="middle" align="center" style="width:104px;padding:16px 12px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:11px;font-weight:600;line-height:15px;mso-line-height-rule:exactly;color:{2};text-transform:uppercase;letter-spacing:0.1px;">Status<br>{3}</td>
    <td valign="middle" style="padding:16px 16px 16px 8px;">
      <div style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:17px;font-weight:600;line-height:23px;mso-line-height-rule:exactly;color:#172033;">{4}</div>
      <div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:14px;line-height:21px;mso-line-height-rule:exactly;color:#475569;">{5}</div>
    </td>
  </tr>
</table>
'@ -f $Colors.Border, $Colors.Background, $Colors.Text,
                (ConvertTo-PSIEmailHtmlEncoded $Status),
                (ConvertTo-PSIEmailHtmlEncoded $Properties.Title),
                (ConvertTo-PSIEmailHtmlEncoded $Properties.Message)
        }
        'Table' {
            $Builder = [System.Text.StringBuilder]::new()
            $Data = @($Properties.Data)
            $Columns = @($Properties.Columns)
            $MaxRows = [int] $Properties.MaxRows
            $ShownCount = [math]::Min($Data.Count, $MaxRows)
            [void] $Builder.Append(('<table width="100%" cellpadding="0" cellspacing="0" border="0" aria-label="{0}" style="width:100%;border-collapse:collapse;border:1px solid #dbe3ec;background-color:#ffffff;">' -f (ConvertTo-PSIEmailHtmlEncoded $Properties.Title)))
            [void] $Builder.Append('<thead><tr><th align="left" colspan="')
            [void] $Builder.Append([math]::Max(1, $Columns.Count))
            [void] $Builder.Append(('" style="padding:12px 16px;background-color:{0};border-left:3px solid {1};border-bottom:1px solid #dbe3ec;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:16px;font-weight:600;line-height:22px;mso-line-height-rule:exactly;color:#172033;">' -f $TemplateStyle.AccentSoft, $TemplateStyle.Accent))
            [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Properties.Title))
            [void] $Builder.Append('</th></tr>')
            if ($Columns.Count -gt 0) {
                [void] $Builder.Append('<tr>')
                foreach ($Column in $Columns) {
                    $Label = if ($Properties.ColumnLabels.ContainsKey($Column)) { $Properties.ColumnLabels[$Column] } else { $Column }
                    [void] $Builder.Append('<th scope="col" align="left" valign="bottom" bgcolor="#e8eef5" style="padding:10px 12px;background-color:#e8eef5;border-bottom:1px solid #cbd5e1;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;font-weight:600;line-height:16px;mso-line-height-rule:exactly;color:#334155;">')
                    [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Label))
                    [void] $Builder.Append('</th>')
                }
                [void] $Builder.Append('</tr>')
            }
            [void] $Builder.Append('</thead><tbody>')
            if ($Columns.Count -eq 0) {
                [void] $Builder.Append('<tr><td style="padding:12px 16px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:13px;line-height:19px;mso-line-height-rule:exactly;color:#64748b;">No columns are available.</td></tr>')
            }
            else {
                if ($Data.Count -eq 0) {
                    [void] $Builder.Append('<tr><td colspan="')
                    [void] $Builder.Append($Columns.Count)
                    [void] $Builder.Append('" style="padding:12px 16px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:13px;line-height:19px;mso-line-height-rule:exactly;color:#64748b;">No records are available.</td></tr>')
                }
                else {
                    for ($Index = 0; $Index -lt $ShownCount; $Index++) {
                        $RowBackground = if ($Properties.ZebraStriping -and $Index % 2 -ne 0) { '#f8fafc' } else { '#ffffff' }
                        [void] $Builder.Append(('<tr bgcolor="{0}" style="background-color:{0};">' -f $RowBackground))
                        foreach ($Column in $Columns) {
                            $Value = Get-PSIEmailObjectValue -InputObject $Data[$Index] -Name $Column
                            [void] $Builder.Append('<td valign="top" style="padding:10px 12px;border-bottom:1px solid #e7edf3;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:13px;line-height:19px;mso-line-height-rule:exactly;color:#334155;word-break:break-word;overflow-wrap:anywhere;">')
                            [void] $Builder.Append((ConvertTo-PSIEmailHtmlEncoded $Value))
                            [void] $Builder.Append('</td>')
                        }
                        [void] $Builder.Append('</tr>')
                    }
                }
            }
            [void] $Builder.Append('</tbody></table>')
            if ($Data.Count -gt $MaxRows) {
                [void] $Builder.Append('<div style="padding-top:8px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;mso-line-height-rule:exactly;color:#64748b;">')
                [void] $Builder.Append(('Showing {0} of {1} records.' -f $ShownCount, $Data.Count))
                [void] $Builder.Append('</div>')
            }
            return $Builder.ToString()
        }
        'Divider' {
            return '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;"><tr><td style="height:1px;border-top:1px solid #dbe3ec;font-size:1px;line-height:1px;">&nbsp;</td></tr></table>'
        }
        default { throw "Email component type '$($Component.Type)' is not supported." }
    }
}

function ConvertTo-PSIEmailMarkup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter()][switch] $Preview
    )

    if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email' -or
        $Email.Sections -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightEmail email. Create it with New-PSIEmail.'
    }

    $Builder = [System.Text.StringBuilder]::new()
    $Template = if ($null -ne $Email.PSObject.Properties['Template'] -and
        -not [string]::IsNullOrWhiteSpace([string] $Email.Template)) { [string] $Email.Template } else { 'Operational' }
    $TemplateStyle = Get-PSIEmailTemplateStyle -Template $Template
    $SafeTitle = ConvertTo-PSIEmailHtmlEncoded $Email.Title
    $LogoMarkup = ConvertTo-PSIEmailLogoMarkup -Path ([string] $Email.LogoPath) `
        -AltText ([string] $Email.BrandName) -ContentId ([string] $Email.LogoContentId) `
        -InlineResources @($Email.InlineResources) -Preview:$Preview
    [void] $Builder.AppendLine('<!DOCTYPE html>')
    [void] $Builder.AppendLine('<html lang="en">')
    [void] $Builder.AppendLine('<head>')
    [void] $Builder.AppendLine('  <meta charset="utf-8">')
    [void] $Builder.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1">')
    [void] $Builder.AppendLine("  <title>$SafeTitle</title>")
    [void] $Builder.AppendLine('  <style type="text/css">')
    [void] $Builder.AppendLine('    @media only screen and (max-width:720px) {')
    [void] $Builder.AppendLine('      .psi-container { width:100% !important; }')
    [void] $Builder.AppendLine('      .psi-page-pad { padding:12px 8px !important; }')
    [void] $Builder.AppendLine('    }')
    [void] $Builder.AppendLine('  </style>')
    [void] $Builder.AppendLine('</head>')
    [void] $Builder.AppendLine('<body bgcolor="#eef2f6" style="margin:0;padding:0;background-color:#eef2f6;font-family:Segoe UI,Arial,Helvetica,sans-serif;">')
    if (-not [string]::IsNullOrWhiteSpace([string] $Email.Preheader)) {
        [void] $Builder.AppendLine(('  <div aria-hidden="true" style="display:none!important;visibility:hidden;font-size:1px;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;color:#eef2f6;">{0}</div>' -f (ConvertTo-PSIEmailHtmlEncoded $Email.Preheader)))
    }
    [void] $Builder.AppendLine('  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#eef2f6" style="width:100%;border-collapse:collapse;background-color:#eef2f6;">')
    [void] $Builder.AppendLine('    <tr><td class="psi-page-pad" align="center" style="padding:24px 12px;">')
    [void] $Builder.AppendLine('      <!--[if mso]><table role="presentation" width="920" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->')
    [void] $Builder.AppendLine('      <table role="presentation" class="psi-container" width="75%" align="center" cellpadding="0" cellspacing="0" border="0" bgcolor="#ffffff" style="width:75%;max-width:920px;border-collapse:collapse;background-color:#ffffff;">')
    [void] $Builder.AppendLine(('        <tr><td bgcolor="{0}" style="padding:24px 32px;background-color:{0};border-bottom:4px solid {1};">' -f $TemplateStyle.Header, $TemplateStyle.HeaderAccent))
    if (-not [string]::IsNullOrWhiteSpace([string] $Email.BrandName) -or
        -not [string]::IsNullOrWhiteSpace([string] $Email.EnvironmentLabel) -or
        -not [string]::IsNullOrWhiteSpace($LogoMarkup)) {
        [void] $Builder.AppendLine('          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;border-collapse:collapse;">')
        [void] $Builder.AppendLine('            <tr>')
        [void] $Builder.AppendLine('              <td valign="middle" style="padding:0 10px 15px 0;">')
        if (-not [string]::IsNullOrWhiteSpace($LogoMarkup)) { [void] $Builder.AppendLine("                $LogoMarkup") }
        if (-not [string]::IsNullOrWhiteSpace([string] $Email.BrandName)) {
            [void] $Builder.AppendLine(('                <div style="padding-top:4px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:11px;font-weight:600;line-height:15px;mso-line-height-rule:exactly;color:{0};text-transform:uppercase;letter-spacing:0.2px;">{1}</div>' -f $TemplateStyle.HeaderMuted, (ConvertTo-PSIEmailHtmlEncoded $Email.BrandName)))
        }
        [void] $Builder.AppendLine('              </td>')
        [void] $Builder.AppendLine('              <td valign="middle" align="right" style="padding:0 0 15px 10px;">')
        if (-not [string]::IsNullOrWhiteSpace([string] $Email.EnvironmentLabel)) {
            $EnvironmentColors = Get-PSIEmailStatusStyle -Status ([string] $Email.EnvironmentStatus)
            [void] $Builder.AppendLine(('                <span style="display:inline-block;padding:6px 8px;border:1px solid {0};background-color:{1};font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:11px;font-weight:600;line-height:15px;mso-line-height-rule:exactly;color:{2};text-transform:uppercase;letter-spacing:0.1px;">{3} · {4}</span>' -f $EnvironmentColors.Border, $EnvironmentColors.Background, $EnvironmentColors.Text, (ConvertTo-PSIEmailHtmlEncoded $Email.EnvironmentLabel), (ConvertTo-PSIEmailHtmlEncoded $Email.EnvironmentStatus)))
        }
        [void] $Builder.AppendLine('              </td>')
        [void] $Builder.AppendLine('            </tr>')
        [void] $Builder.AppendLine('          </table>')
    }
    [void] $Builder.AppendLine(('          <h1 style="margin:0;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:28px;font-weight:600;line-height:34px;mso-line-height-rule:exactly;color:#ffffff;">{0}</h1>' -f $SafeTitle))
    if (-not [string]::IsNullOrWhiteSpace([string] $Email.Subtitle)) {
        [void] $Builder.AppendLine(('          <div style="padding-top:8px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:15px;line-height:22px;mso-line-height-rule:exactly;color:{0};">{1}</div>' -f $TemplateStyle.HeaderMuted, (ConvertTo-PSIEmailHtmlEncoded $Email.Subtitle)))
    }
    $SourcePrefix = if ([string]::IsNullOrWhiteSpace([string] $Email.SourceLabel)) { '' } else {
        'Source: {0} &nbsp;·&nbsp; ' -f (ConvertTo-PSIEmailHtmlEncoded $Email.SourceLabel)
    }
    [void] $Builder.AppendLine(('          <div style="padding-top:12px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;mso-line-height-rule:exactly;color:{0};">{1}Generated {2}</div>' -f $TemplateStyle.HeaderMuted, $SourcePrefix, (ConvertTo-PSIEmailHtmlEncoded $Email.GeneratedOn.ToString('yyyy-MM-dd HH:mm zzz'))))
    [void] $Builder.AppendLine('        </td></tr>')

    foreach ($Section in $Email.Sections) {
        [void] $Builder.AppendLine('        <tr><td style="padding:32px 32px 4px 32px;">')
        [void] $Builder.AppendLine(('          <h2 style="margin:0;padding:0 0 8px 12px;border-left:4px solid {0};border-bottom:1px solid #e2e8f0;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:18px;font-weight:600;line-height:24px;mso-line-height-rule:exactly;color:{1};">{2}</h2>' -f $TemplateStyle.Accent, $TemplateStyle.Section, (ConvertTo-PSIEmailHtmlEncoded $Section.Title)))
        if (-not [string]::IsNullOrWhiteSpace([string] $Section.Description)) {
            [void] $Builder.AppendLine(('          <div style="padding-top:8px;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:14px;line-height:21px;mso-line-height-rule:exactly;color:#64748b;">{0}</div>' -f (ConvertTo-PSIEmailHtmlEncoded $Section.Description)))
        }
        [void] $Builder.AppendLine('        </td></tr>')
        foreach ($Row in $Section.Rows) {
            $Columns = [int] $Row.Columns
            if ($Columns -notin @(1, 2, 3, 4)) { throw "Email row Columns must be 1, 2, 3, or 4. Found '$Columns'." }
            $Width = [math]::Floor(100 / $Columns)
            [void] $Builder.AppendLine('        <tr><td style="padding:16px 24px 0 24px;">')
            [void] $Builder.AppendLine('          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;table-layout:fixed;border-collapse:collapse;">')
            $Components = @($Row.Components)
            if ($Components.Count -eq 0) {
                [void] $Builder.AppendLine('            <tr><td style="font-size:1px;line-height:1px;">&nbsp;</td></tr>')
            }
            for ($Index = 0; $Index -lt $Components.Count; $Index += $Columns) {
                [void] $Builder.AppendLine('            <tr>')
                for ($ColumnIndex = 0; $ColumnIndex -lt $Columns; $ColumnIndex++) {
                    $ComponentIndex = $Index + $ColumnIndex
                    [void] $Builder.AppendLine(('              <td width="{0}%" align="left" valign="top" style="width:{0}%;padding:0 8px 12px 8px;">' -f $Width))
                    if ($ComponentIndex -lt $Components.Count) {
                        [void] $Builder.AppendLine((ConvertTo-PSIEmailComponentMarkup -Component $Components[$ComponentIndex] -TemplateStyle $TemplateStyle))
                    }
                    else { [void] $Builder.AppendLine('                &nbsp;') }
                    [void] $Builder.AppendLine('              </td>')
                }
                [void] $Builder.AppendLine('            </tr>')
            }
            [void] $Builder.AppendLine('          </table>')
            [void] $Builder.AppendLine('        </td></tr>')
        }
    }

    [void] $Builder.AppendLine('        <tr><td style="padding:24px 32px 32px 32px;">')
    [void] $Builder.AppendLine(('          <div style="padding-top:12px;border-top:1px solid #dbe3ec;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;mso-line-height-rule:exactly;color:#64748b;">'))
    if (-not [string]::IsNullOrWhiteSpace([string] $Email.FooterNote)) {
        [void] $Builder.AppendLine(('            <div style="padding-bottom:8px;color:#475569;">{0}</div>' -f (ConvertTo-PSIEmailHtmlEncoded $Email.FooterNote)))
    }
    [void] $Builder.AppendLine(('            Generated with PSInsightEmail {0}' -f (ConvertTo-PSIEmailHtmlEncoded $Email.ModuleVersion)))
    [void] $Builder.AppendLine('          </div>')
    [void] $Builder.AppendLine('        </td></tr>')
    [void] $Builder.AppendLine('      </table>')
    [void] $Builder.AppendLine('      <!--[if mso]></td></tr></table><![endif]-->')
    [void] $Builder.AppendLine('    </td></tr>')
    [void] $Builder.AppendLine('  </table>')
    [void] $Builder.AppendLine('</body>')
    [void] $Builder.AppendLine('</html>')
    $Builder.ToString()
}

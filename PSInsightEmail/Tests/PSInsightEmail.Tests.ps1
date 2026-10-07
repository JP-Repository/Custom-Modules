BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $script:ModuleRoot -ChildPath 'PSInsightEmail.psd1') -Force

    function New-TestEmail {
        param([int] $Columns = 1)
        New-PSIEmail -Title 'Test email' -Subtitle 'Fictional sample' -Preheader 'Hidden preview' |
            Add-PSIEmailSection -Title 'Summary' -Description 'Sample section' |
            Add-PSIEmailRow -Columns $Columns
    }
}

Describe 'PSInsightEmail module contract' {
    It 'imports the module at version 0.1.0' {
        $Module = Get-Module PSInsightEmail
        $Module | Should -Not -BeNullOrEmpty
        $Module.Version.ToString() | Should -Be '0.1.0'
    }

    It 'exports exactly the intended sixteen public functions' {
        $Expected = @(
            'Add-PSIEmailAlert', 'Add-PSIEmailAttachment', 'Add-PSIEmailBanner', 'Add-PSIEmailDivider',
            'Add-PSIEmailInlineResource', 'Add-PSIEmailKeyValue',
            'Add-PSIEmailKPI', 'Add-PSIEmailRow', 'Add-PSIEmailSection',
            'Add-PSIEmailTable', 'Add-PSIEmailText', 'ConvertTo-PSIEmailHtml',
            'Export-PSIEmailPreview', 'New-PSIEmail', 'Send-PSIEmailGraph', 'Send-PSIEmailSmtp'
        )
        $Actual = @(Get-Command -Module PSInsightEmail -CommandType Function |
            Select-Object -ExpandProperty Name | Sort-Object)
        $Actual.Count | Should -Be 16
        $Actual -join ',' | Should -Be ($Expected -join ',')
    }

    It 'does not export private helpers' {
        (Get-Command ConvertTo-PSIEmailMarkup -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command ConvertTo-PSIEmailHtmlEncoded -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command New-PSIEmailComponent -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Get-PSIEmailLastRow -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Get-PSIEmailContentType -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Assert-PSIEmailContentId -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command New-PSIEmailGraphMessage -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Invoke-PSIEmailGraphRequest -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'declares PowerShell 5.1 compatibility and explicit exports' {
        $Manifest = Import-PowerShellDataFile -Path (Join-Path $script:ModuleRoot 'PSInsightEmail.psd1')
        $Manifest.PowerShellVersion | Should -Be '5.1'
        @($Manifest.FunctionsToExport).Count | Should -Be 16
        @($Manifest.FunctionsToExport) | Should -Not -Contain '*'
    }
}

Describe 'PSInsightEmail composition contracts' {
    It 'creates the email object without rendering or writing a file' {
        $Before = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter '*.psiemail-contract' -ErrorAction SilentlyContinue).Count
        $Email = New-PSIEmail -Title 'Operations' -Subtitle 'Sample' -Preheader 'Inbox text'
        $After = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter '*.psiemail-contract' -ErrorAction SilentlyContinue).Count

        $Email.PSObject.TypeNames | Should -Contain 'PSInsightEmail.Email'
        $Email.Title | Should -Be 'Operations'
        $Email.Subtitle | Should -Be 'Sample'
        $Email.Preheader | Should -Be 'Inbox text'
        $Email.Template | Should -Be 'Operational'
        $Email.EnvironmentStatus | Should -Be 'Neutral'
        $Email.GeneratedOn | Should -BeOfType [datetime]
        $Email.ModuleVersion | Should -Be '0.1.0'
        $Email.Sections.GetType().GetGenericTypeDefinition().FullName | Should -Be 'System.Collections.Generic.List`1'
        $Email.Sections.Count | Should -Be 0
        $Email.Attachments.GetType().GetGenericTypeDefinition().FullName | Should -Be 'System.Collections.Generic.List`1'
        $Email.InlineResources.GetType().GetGenericTypeDefinition().FullName | Should -Be 'System.Collections.Generic.List`1'
        $Email.Attachments.Count | Should -Be 0
        $Email.InlineResources.Count | Should -Be 0
        $After | Should -Be $Before
    }

    It 'adds sections and rows while returning the same email' {
        $Email = New-PSIEmail -Title 'Contract'
        $Result = $Email | Add-PSIEmailSection -Title 'Summary' -Description 'Description' |
            Add-PSIEmailRow -Columns 2
        [object]::ReferenceEquals($Email, $Result) | Should -BeTrue
        $Email.Sections.Count | Should -Be 1
        $Email.Sections[0].Title | Should -Be 'Summary'
        $Email.Sections[0].Description | Should -Be 'Description'
        $Email.Sections[0].Rows.Count | Should -Be 1
        $Email.Sections[0].Rows[0].Columns | Should -Be 2
    }

    It 'supports one-, two-, three-, and four-column rows' {
        foreach ($Count in 1, 2, 3, 4) {
            $Email = New-TestEmail -Columns $Count
            foreach ($Index in 1..$Count) {
                $Email | Add-PSIEmailText -Text "Column $Index" | Out-Null
            }
            $Email.Sections[0].Rows[0].Columns | Should -Be $Count
            $Html = ConvertTo-PSIEmailHtml -Email $Email
            if ($Count -eq 1) { $Html | Should -Match 'width="100%"[^>]*valign="top"' }
            if ($Count -eq 2) { $Html | Should -Match 'width="50%"[^>]*valign="top"' }
            if ($Count -eq 3) { $Html | Should -Match 'width="33%"[^>]*valign="top"' }
            if ($Count -eq 4) { $Html | Should -Match 'width="25%"[^>]*valign="top"' }
        }
    }

    It 'adds a structured text component' {
        $Email = New-TestEmail | Add-PSIEmailText -Text 'Sample text' -Size Large
        $Component = $Email.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Text'
        $Component.Properties.GetType().GetInterface('IDictionary') | Should -Not -BeNullOrEmpty
        $Component.Properties.Text | Should -Be 'Sample text'
        $Component.Properties.Size | Should -Be 'Large'
    }

    It 'adds KPI components for all supported statuses' {
        $Email = New-TestEmail -Columns 3
        foreach ($Status in 'Neutral', 'Informational', 'Healthy', 'Warning', 'Critical') {
            $Email | Add-PSIEmailKPI -Title $Status -Value 1 -Subtitle 'Sample' -Status $Status | Out-Null
        }
        $Email.Sections[0].Rows[0].Components.Count | Should -Be 5
        $Email.Sections[0].Rows[0].Components[4].Properties.Status | Should -Be 'Critical'
    }

    It 'adds a key-value component with IDictionary data' {
        $Data = [ordered]@{ Systems = 3; Warnings = 1 }
        $Email = New-TestEmail | Add-PSIEmailKeyValue -Title 'Scope' -Data $Data
        $Component = $Email.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'KeyValue'
        $Component.Properties.Data.Systems | Should -Be 3
    }

    It 'adds an alert with explicit status text' {
        $Email = New-TestEmail | Add-PSIEmailAlert -Status Warning -Title 'Review' -Message 'Sample warning'
        $Component = $Email.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Alert'
        $Component.Properties.Status | Should -Be 'Warning'
        (ConvertTo-PSIEmailHtml $Email) | Should -Match '>Warning<'
    }

    It 'adds a full-width status banner with structured content' {
        $Email = New-TestEmail | Add-PSIEmailBanner -Status Critical -Title 'Review required' -Message 'Fictional issue'
        $Component = $Email.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Banner'
        $Component.Properties.Status | Should -Be 'Critical'
        $Component.Properties.Title | Should -Be 'Review required'
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match 'Status<br>Critical'
        $Html | Should -Match '>Review required</div>'
        $Html | Should -Match '>Fictional issue</div>'
    }

    It 'adds a table with columns, labels, and a maximum row count' {
        $Data = @([pscustomobject]@{ Name = 'server01.example.invalid'; State = 'Healthy' })
        $Email = New-TestEmail | Add-PSIEmailTable -Title 'Systems' -Data $Data `
            -Columns @('Name', 'State') -ColumnLabels @{ Name = 'System' } -MaxRows 5
        $Component = $Email.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Table'
        $Component.Properties.Columns -join ',' | Should -Be 'Name,State'
        $Component.Properties.ColumnLabels.Name | Should -Be 'System'
        $Component.Properties.MaxRows | Should -Be 5
        $Component.Properties.ZebraStriping | Should -BeTrue
    }

    It 'adds a divider component' {
        $Email = New-TestEmail | Add-PSIEmailDivider
        $Email.Sections[0].Rows[0].Components[0].Type | Should -Be 'Divider'
    }
}

Describe 'PSInsightEmail rendering' {
    It 'stores each supported visual template on the email object' {
        foreach ($Template in 'Operational', 'Health', 'Threshold') {
            (New-PSIEmail -Title 'Template test' -Template $Template).Template | Should -Be $Template
        }
    }

    It 'renders header metadata and a concise footer note' {
        $Email = New-PSIEmail -Title 'Metadata' -Template Health -BrandName 'Example Health' `
            -EnvironmentLabel 'Example Lab' -EnvironmentStatus Warning `
            -SourceLabel 'Fictional inventory' -FooterNote 'Sample execution note.' `
            -LogoPath './missing-example-logo.png'
        $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow | Add-PSIEmailText -Text 'Content' | Out-Null
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '>Example Health</div>'
        $Html | Should -Match 'Example Lab · Warning'
        $Html | Should -Match 'Source: Fictional inventory'
        $Html | Should -Match '>Sample execution note\.</div>'
        $Html | Should -Not -Match '<img\b'
    }

    It 'embeds a supported preview logo without exposing its local path' {
        $LogoPath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.png')
        try {
            [System.IO.File]::WriteAllBytes($LogoPath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
            $Email = New-PSIEmail -Title 'Logo preview' -BrandName 'Example Brand' -LogoPath $LogoPath
            $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow | Add-PSIEmailText -Text 'Content' | Out-Null
            $Html = ConvertTo-PSIEmailHtml -Email $Email
            $Html | Should -Match '<img src="data:image/png;base64,'
            $Html | Should -Match 'alt="Example Brand logo"'
            $Html | Should -Not -Match ([regex]::Escape($LogoPath))
        }
        finally {
            if (Test-Path -LiteralPath $LogoPath) { Remove-Item -LiteralPath $LogoPath -Force }
        }
    }

    It 'generates a valid self-contained document for every template style' {
        $Headers = @{}
        foreach ($Template in 'Operational', 'Health', 'Threshold') {
            $Email = New-PSIEmail -Title "$Template sample" -Template $Template
            $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow |
                Add-PSIEmailBanner -Status Informational -Title 'Sample' -Message 'Fictional content' | Out-Null
            $Html = ConvertTo-PSIEmailHtml -Email $Email
            $Html | Should -Match '^<!DOCTYPE html>'
            $Html | Should -Match "<title>$Template sample</title>"
            $Html | Should -Match '</html>'
            $Html | Should -Not -Match '<script[\s>]|<link\b|https?://'
            $Headers[$Template] = ([regex]::Match($Html, 'background-color:(#[0-9a-f]{6});border-bottom:4px').Groups[1].Value)
        }
        @($Headers.Values | Select-Object -Unique).Count | Should -Be 3
    }

    It 'renders refined KPI hierarchy with a visible status label' {
        $Email = New-TestEmail | Add-PSIEmailKPI -Title 'Warnings' -Value 3 -Subtitle 'Review queue' -Status Warning
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match 'border-top:3px solid #d97706'
        $Html | Should -Match 'font-size:30px;font-weight:600[^>]*>3</div>'
        $Html | Should -Match '>Warning</div>'
    }

    It 'uses a wider responsive container with a fixed Outlook fallback and refined typography' {
        $Email = New-TestEmail | Add-PSIEmailText -Text 'Readable body copy'
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '<!--\[if mso\]><table role="presentation" width="920"'
        $Html | Should -Match '<table role="presentation" class="psi-container" width="75%"[^>]*max-width:920px'
        $Html | Should -Match '\.psi-container \{ width:100% !important; \}'
        $Html | Should -Match 'font-family:Segoe UI,Arial,Helvetica,sans-serif'
        $Html | Should -Not -Match 'font-family:Arial,Helvetica,sans-serif'
        $Html | Should -Match '<h1[^>]*font-size:28px;font-weight:600;line-height:34px'
        $Html | Should -Match '<h2[^>]*font-size:18px;font-weight:600;line-height:24px'
    }

    It 'exposes explicit text for every supported status' {
        $Email = New-TestEmail -Columns 4
        foreach ($Status in 'Healthy', 'Warning', 'Critical', 'Informational', 'Neutral') {
            $Email | Add-PSIEmailKPI -Title "$Status result" -Value 1 -Status $Status | Out-Null
        }
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        foreach ($Status in 'Healthy', 'Warning', 'Critical', 'Informational', 'Neutral') {
            $Html | Should -Match (">$Status</div>")
        }
    }

    It 'marks layout tables as presentation and data tables as semantic' {
        $Data = @([pscustomobject]@{ Name = 'server01.example.invalid'; Status = 'Healthy' })
        $Email = New-TestEmail | Add-PSIEmailTable -Title 'System data' -Data $Data -Columns @('Name', 'Status')
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '<table role="presentation"'
        $Html | Should -Match '<table width="100%"[^>]*aria-label="System data"'
        $Html | Should -Match '<table width="100%"[^>]*aria-label="System data"[^>]*style="width:100%'
        $Html | Should -Not -Match '<table role="presentation"[^>]*aria-label="System data"'
        $Html | Should -Match '<thead>'
        $Html | Should -Match '<tbody>'
        $Html | Should -Match '<th scope="col"[^>]*>Name</th>'
        $Html | Should -Match '<th scope="col"[^>]*>Status</th>'
        $Html | Should -Match '<th scope="col"[^>]*font-size:12px;font-weight:600'
        $Html | Should -Match '<td valign="top"[^>]*font-size:13px;line-height:19px'
        foreach ($Match in [regex]::Matches($Html, '<table\b[^>]*>')) {
            ($Match.Value -match 'role="presentation"|aria-label=') | Should -BeTrue
        }
    }

    It 'renders bounded table data and discloses truncation' {
        $Data = 1..4 | ForEach-Object { [pscustomobject]@{ Name = "Sample $_" } }
        $Email = New-TestEmail | Add-PSIEmailTable -Title 'Bounded' -Data $Data -Columns Name -MaxRows 2
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match 'Sample 1'
        $Html | Should -Match 'Sample 2'
        $Html | Should -Not -Match 'Sample 3'
        $Html | Should -Match 'Showing 2 of 4 records\.'
        $Html | Should -Match '<tr bgcolor="#f8fafc" style="background-color:#f8fafc;">'
    }

    It 'renders a clear semantic empty table state' {
        $Email = New-TestEmail | Add-PSIEmailTable -Title 'Empty inventory' -Data @() -Columns @('Name', 'Status')
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '<table width="100%"[^>]*aria-label="Empty inventory"'
        $Html | Should -Match '<tbody><tr><td colspan="2"[^>]*>No records are available\.</td></tr></tbody>'
    }

    It 'HTML-encodes all user-supplied display values' {
        $Dangerous = '<script>alert(1)</script> & "quoted"'
        $Email = New-PSIEmail -Title $Dangerous -Subtitle $Dangerous -Preheader $Dangerous
        $Email | Add-PSIEmailSection -Title $Dangerous -Description $Dangerous |
            Add-PSIEmailRow |
            Add-PSIEmailText -Text $Dangerous |
            Add-PSIEmailRow |
            Add-PSIEmailKeyValue -Title $Dangerous -Data ([ordered]@{ $Dangerous = $Dangerous }) |
            Add-PSIEmailRow |
            Add-PSIEmailTable -Title $Dangerous -Data @([pscustomobject]@{ Value = $Dangerous }) -Columns Value |
            Out-Null
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt; &amp; &quot;quoted&quot;'
        $Html | Should -Not -Match '<script[\s>]'
        $Html | Should -Not -Match 'alert\(1\)</script>'
    }

    It 'preserves encoded Unicode, long names, and email-like strings' {
        $LongName = ('server-' + ('x' * 120) + '.example.invalid')
        $DisplayValue = 'München & Zürich <review> "quoted" sample.user@example.invalid'
        $Email = New-TestEmail | Add-PSIEmailTable -Title 'Encoding inventory' `
            -Data @([pscustomobject]@{ Name = $LongName; Detail = $DisplayValue }) -Columns @('Name', 'Detail')
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match ([regex]::Escape($LongName))
        $Html | Should -Match 'M&#252;nchen &amp; Z&#252;rich &lt;review&gt; &quot;quoted&quot; sample\.user@example\.invalid'
        $Html | Should -Not -Match '<review>'
    }

    It 'omits absent optional header and footer metadata cleanly' {
        $Email = New-PSIEmail -Title 'Minimal email'
        $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow | Add-PSIEmailText -Text 'Content' | Out-Null
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '<h1[^>]*>Minimal email</h1>'
        $Html | Should -Not -Match 'Source:'
        $Html | Should -Not -Match '<img\b'
        $Html | Should -Not -Match '<h1[^>]*>\s*</h1>|<h2[^>]*>\s*</h2>'
        $Html | Should -Match 'Generated with PSInsightEmail 0\.1\.0'
    }

    It 'renders the preheader as hidden inbox preview text only' {
        $Email = New-TestEmail | Add-PSIEmailText -Text 'Visible body'
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        ([regex]::Matches($Html, 'Hidden preview')).Count | Should -Be 1
        $Html | Should -Match '<div aria-hidden="true"[^>]*>Hidden preview</div>'
        $Html | Should -Match 'display:none[^>]*mso-hide:all'
        $Html | Should -Match '>Visible body</div>'
    }

    It 'uses self-contained conservative email markup' {
        $Email = New-TestEmail -Columns 3 |
            Add-PSIEmailKPI -Title 'Healthy' -Value 3 -Status Healthy |
            Add-PSIEmailAlert -Status Informational -Title 'Note' -Message 'Sample' |
            Add-PSIEmailDivider
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '<table role="presentation"'
        $Html | Should -Match 'width="75%"'
        $Html | Should -Match 'max-width:920px'
        $Html | Should -Match 'font-family:Segoe UI,Arial,Helvetica,sans-serif'
        $Html | Should -Not -Match '<script[\s>]'
        $Html | Should -Not -Match '<link\b|@import|@font-face|fonts\.(googleapis|gstatic)'
        $Html | Should -Not -Match '<img\b|<image\b|background-image\s*:|url\s*\('
        $Html | Should -Not -Match 'display\s*:\s*(grid|flex)'
        $Html | Should -Not -Match '(position|float)\s*:'
        $Html | Should -Not -Match 'var\s*\('
        $Html | Should -Not -Match '\bfetch\s*\('
        $Html | Should -Not -Match 'https?://'
    }

    It 'returns a balanced basic HTML document' {
        $Email = New-TestEmail | Add-PSIEmailText -Text 'Content'
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match '^<!DOCTYPE html>'
        ([regex]::Matches($Html, '<html\b')).Count | Should -Be 1
        ([regex]::Matches($Html, '</html>')).Count | Should -Be 1
        ([regex]::Matches($Html, '<head>')).Count | Should -Be 1
        ([regex]::Matches($Html, '</head>')).Count | Should -Be 1
        ([regex]::Matches($Html, '<body\b')).Count | Should -Be 1
        ([regex]::Matches($Html, '</body>')).Count | Should -Be 1
    }

    It 'writes a UTF-8 preview file and returns FileInfo' {
        $Email = New-TestEmail | Add-PSIEmailText -Text 'Preview content'
        $Path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            $File = Export-PSIEmailPreview -Email $Email -Path $Path
            $File | Should -BeOfType [System.IO.FileInfo]
            $File.Exists | Should -BeTrue
            (Get-Content -LiteralPath $File.FullName -Raw) | Should -Match 'Preview content'
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $script:ModuleRoot 'PSInsightEmail.psd1') -Force
    $script:ResourceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PSInsightEmail-' + [guid]::NewGuid().ToString('N'))
    [void] (New-Item -Path $script:ResourceRoot -ItemType Directory -Force)
    $script:CsvPath = Join-Path $script:ResourceRoot 'sample.csv'
    [System.IO.File]::WriteAllText($script:CsvPath, "Name,Status`nATTACHMENT-BYTES-MUST-NOT-APPEAR,Healthy", [System.Text.UTF8Encoding]::new($false))
    $script:PngPath = Join-Path $script:ResourceRoot 'sample-logo.png'
    [System.IO.File]::WriteAllBytes($script:PngPath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
    $script:UnknownPath = Join-Path $script:ResourceRoot 'sample.unknown'
    [System.IO.File]::WriteAllText($script:UnknownPath, 'unknown sample')

    function New-ResourceTestEmail {
        New-PSIEmail -Title 'Resource test' -BrandName 'Example Automation' |
            Add-PSIEmailSection -Title 'Summary' |
            Add-PSIEmailRow |
            Add-PSIEmailText -Text 'Fictional content'
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:ResourceRoot) {
        Remove-Item -LiteralPath $script:ResourceRoot -Recurse -Force
    }
}

Describe 'PSInsightEmail attachment model' {
    It 'adds an attachment with default metadata and returns the same email' {
        $Email = New-ResourceTestEmail
        $Result = $Email | Add-PSIEmailAttachment -Path $script:CsvPath
        [object]::ReferenceEquals($Email, $Result) | Should -BeTrue
        $Email.Attachments.Count | Should -Be 1
        $Attachment = $Email.Attachments[0]
        $Attachment.PSObject.TypeNames | Should -Contain 'PSInsightEmail.Attachment'
        $Attachment.Path | Should -Be ([System.IO.Path]::GetFullPath($script:CsvPath))
        $Attachment.Name | Should -Be 'sample.csv'
        $Attachment.ContentType | Should -Be 'text/csv'
        $Attachment.Length | Should -Be (Get-Item $script:CsvPath).Length
    }

    It 'accepts a caller-supplied safe name and MIME override' {
        $Email = New-ResourceTestEmail | Add-PSIEmailAttachment -Path $script:CsvPath `
            -Name 'results.dat' -ContentType 'application/vnd.example.result'
        $Email.Attachments[0].Name | Should -Be 'results.dat'
        $Email.Attachments[0].ContentType | Should -Be 'application/vnd.example.result'
    }

    It 'detects all supported MIME types without an external library' {
        $Expected = [ordered]@{
            '.csv'='text/csv'; '.html'='text/html'; '.htm'='text/html'; '.txt'='text/plain'
            '.json'='application/json'; '.xml'='application/xml'; '.pdf'='application/pdf'
            '.xlsx'='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            '.xls'='application/vnd.ms-excel'; '.zip'='application/zip'; '.png'='image/png'
            '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif'
        }
        $Email = New-ResourceTestEmail
        $Index = 0
        foreach ($Extension in $Expected.Keys) {
            $Index++
            $Path = Join-Path $script:ResourceRoot ("mime-$Index$Extension")
            [System.IO.File]::WriteAllText($Path, 'sample')
            $Email | Add-PSIEmailAttachment -Path $Path | Out-Null
            $Email.Attachments[$Email.Attachments.Count - 1].ContentType | Should -Be $Expected[$Extension]
        }
    }

    It 'uses application/octet-stream for an unknown extension' {
        $Email = New-ResourceTestEmail | Add-PSIEmailAttachment -Path $script:UnknownPath
        $Email.Attachments[0].ContentType | Should -Be 'application/octet-stream'
    }

    It 'rejects missing files, directories, and remote URLs' {
        $Email = New-ResourceTestEmail
        { $Email | Add-PSIEmailAttachment -Path (Join-Path $script:ResourceRoot 'missing.csv') } | Should -Throw '*not found*'
        { $Email | Add-PSIEmailAttachment -Path $script:ResourceRoot } | Should -Throw '*local file*'
        { $Email | Add-PSIEmailAttachment -Path 'https://example.invalid/report.csv' } | Should -Throw '*local file path*'
    }

    It 'rejects unsafe attachment display names' {
        $Email = New-ResourceTestEmail
        { $Email | Add-PSIEmailAttachment -Path $script:CsvPath -Name "unsafe`nname.csv" } | Should -Throw '*safe file name*'
        { $Email | Add-PSIEmailAttachment -Path $script:CsvPath -Name '../result.csv' } | Should -Throw '*safe file name*'
    }

    It 'rejects an exact duplicate attachment path and name' {
        $Email = New-ResourceTestEmail | Add-PSIEmailAttachment -Path $script:CsvPath
        { $Email | Add-PSIEmailAttachment -Path $script:CsvPath } | Should -Throw '*already references*'
        $Email.Attachments.Count | Should -Be 1
    }

    It 'does not embed regular attachment metadata or bytes into HTML' {
        $Email = New-ResourceTestEmail | Add-PSIEmailAttachment -Path $script:CsvPath
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Not -Match 'ATTACHMENT-BYTES-MUST-NOT-APPEAR'
        $Html | Should -Not -Match ([regex]::Escape($script:CsvPath))
        $Html | Should -Not -Match 'sample\.csv'
    }
}

Describe 'PSInsightEmail inline resource model' {
    It 'adds an image resource with a generated deterministic safe ContentId' {
        $Email = New-ResourceTestEmail | Add-PSIEmailInlineResource -Path $script:PngPath
        $Resource = $Email.InlineResources[0]
        $Resource.PSObject.TypeNames | Should -Contain 'PSInsightEmail.InlineResource'
        $Resource.Name | Should -Be 'sample-logo.png'
        $Resource.ContentType | Should -Be 'image/png'
        $Resource.ContentId | Should -Match '^psi-sample-logo-[a-f0-9]{12}@psinsightemail$'
        $Resource.Length | Should -Be (Get-Item $script:PngPath).Length

        $OtherEmail = New-ResourceTestEmail | Add-PSIEmailInlineResource -Path $script:PngPath
        $OtherEmail.InlineResources[0].ContentId | Should -Be $Resource.ContentId
    }

    It 'accepts a caller ContentId and custom resource name' {
        $Email = New-ResourceTestEmail | Add-PSIEmailInlineResource -Path $script:PngPath `
            -ContentId 'example-logo@psinsightemail' -Name 'brand-logo.png'
        $Email.InlineResources[0].ContentId | Should -Be 'example-logo@psinsightemail'
        $Email.InlineResources[0].Name | Should -Be 'brand-logo.png'
    }

    It 'rejects duplicate or unsafe ContentIds' {
        $Email = New-ResourceTestEmail | Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'example-logo'
        { $Email | Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'EXAMPLE-LOGO' } | Should -Throw '*already exists*'
        { (New-ResourceTestEmail) | Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'bad id<quoted>' } | Should -Throw '*unsafe*'
    }

    It 'rejects non-image inline resources' {
        { (New-ResourceTestEmail) | Add-PSIEmailInlineResource -Path $script:CsvPath } | Should -Throw '*PNG, JPEG, and GIF*'
    }

    It 'allows an explicitly registered file to be both an attachment and inline resource' {
        $Email = New-ResourceTestEmail |
            Add-PSIEmailAttachment -Path $script:PngPath |
            Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'dual-use-logo'
        $Email.Attachments.Count | Should -Be 1
        $Email.InlineResources.Count | Should -Be 1
    }

    It 'renders production CID markup while preserving visible brand text' {
        $Email = New-PSIEmail -Title 'CID production' -BrandName 'Example Automation' -LogoContentId 'example-logo'
        $Email | Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'example-logo' |
            Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow | Add-PSIEmailText -Text 'Content' | Out-Null
        $Html = ConvertTo-PSIEmailHtml -Email $Email
        $Html | Should -Match 'src="cid:example-logo"'
        $Html | Should -Match 'alt="Example Automation logo"'
        $Html | Should -Match '>Example Automation</div>'
        $Html | Should -Not -Match 'src="data:image/'
    }

    It 'uses an embedded CID preview fallback without changing the email object' {
        $Email = New-PSIEmail -Title 'CID preview' -BrandName 'Example Automation' -LogoContentId 'preview-logo'
        $Email | Add-PSIEmailInlineResource -Path $script:PngPath -ContentId 'preview-logo' |
            Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow | Add-PSIEmailText -Text 'Content' | Out-Null
        $Path = Join-Path $script:ResourceRoot 'cid-preview.html'
        $OriginalContentId = $Email.LogoContentId
        $File = Export-PSIEmailPreview -Email $Email -Path $Path
        $Html = Get-Content -LiteralPath $File.FullName -Raw
        $Html | Should -Match 'src="data:image/png;base64,'
        $Html | Should -Not -Match 'src="cid:'
        $Email.LogoContentId | Should -Be $OriginalContentId
        $Email.InlineResources.Count | Should -Be 1
    }
}

Describe 'PSInsightEmail composition objects remain transport-neutral' {
    It 'keeps recipients and authentication out of the composition contract' {
        $Names = @(Get-Command -Module PSInsightEmail -CommandType Function | Select-Object -ExpandProperty Name)
        $Names.Count | Should -Be 16
        $Names -join ',' | Should -Not -Match 'Recipient|Auth'
        $Email = New-PSIEmail -Title 'Transport neutral'
        $Email.PSObject.Properties.Name | Should -Not -Contain 'Recipients'
        $Email.PSObject.Properties.Name | Should -Not -Contain 'Authentication'
        $Email.PSObject.Properties.Name | Should -Not -Contain 'AccessToken'
        $Email.PSObject.Properties.Name | Should -Not -Contain 'UserId'
    }
}

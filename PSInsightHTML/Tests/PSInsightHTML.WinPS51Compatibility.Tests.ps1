Describe 'PSInsightHTML Windows PowerShell 5.1 source compatibility' {
    BeforeAll {
        $script:CompatibilityModuleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:CompatibilityManifest = Join-Path $script:CompatibilityModuleRoot 'PSInsightHTML.psd1'
        Import-Module -Name $script:CompatibilityManifest -Force -ErrorAction Stop
    }

    It 'keeps executable PowerShell source free of typographic quote characters' {
        $QuoteCharacters = [char[]] @(
            [char] 0x2018,
            [char] 0x2019,
            [char] 0x201A,
            [char] 0x201B,
            [char] 0x201C,
            [char] 0x201D,
            [char] 0x201E,
            [char] 0x201F
        )
        $UnsafeFiles = @(
            Get-ChildItem -LiteralPath $script:CompatibilityModuleRoot -Recurse -File |
                Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') } |
                Where-Object { ([System.IO.File]::ReadAllText($_.FullName)).IndexOfAny($QuoteCharacters) -ge 0 } |
                Select-Object -ExpandProperty FullName
        )
        $UnsafeFiles | Should -BeNullOrEmpty
    }

    It 'keeps executable PowerShell source ASCII-safe without a Unicode allowlist' {
        $UnexpectedCharacters = [System.Collections.Generic.List[object]]::new()
        $SourceFiles = Get-ChildItem -LiteralPath $script:CompatibilityModuleRoot -Recurse -File |
            Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }
        foreach ($File in $SourceFiles) {
            $Text = [System.IO.File]::ReadAllText($File.FullName)
            for ($Index = 0; $Index -lt $Text.Length; $Index++) {
                if ([int] $Text[$Index] -gt 127) {
                    $UnexpectedCharacters.Add([pscustomobject]@{
                        File = $File.FullName
                        Index = $Index
                        CodePoint = 'U+{0:X4}' -f [int] $Text[$Index]
                    })
                }
            }
        }
        $UnexpectedCharacters | Should -BeNullOrEmpty
    }

    It 'keeps embedded JavaScript and CSS runtime assets ASCII-safe' {
        $UnexpectedAssets = @(
            Get-ChildItem -LiteralPath (Join-Path $script:CompatibilityModuleRoot 'Assets') -Recurse -File |
                Where-Object { $_.Extension -in @('.js', '.css') } |
                Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '[^\x00-\x7F]' } |
                Select-Object -ExpandProperty FullName
        )
        $UnexpectedAssets | Should -BeNullOrEmpty
    }

    It 'imports version 0.10.0 and retains exactly thirty public functions' {
        $Module = Get-Module PSInsightHTML
        $Module | Should -Not -BeNullOrEmpty
        $Module.Version.ToString() | Should -Be '0.10.0'
        @(Get-Command -Module PSInsightHTML -CommandType Function).Count | Should -Be 30
    }

    It 'renders the evidence hint with a browser-decoded right arrow' {
        $Report = New-PSIReport -Title 'Compatibility evidence hint'
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow |
            Add-PSIInsight -Title 'Warnings' -Value 1 -Status Warning `
                -Filter @{ Table = 'compatibility-evidence'; Conditions = @() } | Out-Null
        $Report | Add-PSIRow |
            Add-PSITable -Id 'compatibility-evidence' -Title 'Evidence' `
                -Data @([pscustomobject]@{ Name = 'Sample'; Status = 'Warning' }) `
                -Columns @('Name', 'Status') | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            Export-PSIReport -Report $Report -Path $Path | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'View evidence &rarr;'
            $Decoded = [System.Net.WebUtility]::HtmlDecode($Html)
            $ExpectedText = 'View evidence ' + [char] 0x2192
            $Decoded | Should -Match ([regex]::Escape($ExpectedText))
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }
}

BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $script:ModuleRoot 'PSInsightEmail.psd1') -Force
    $script:SmtpTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PSInsightEmail-Smtp-' + [guid]::NewGuid().ToString('N'))
    [void] (New-Item -Path $script:SmtpTestRoot -ItemType Directory -Force)
    $script:AttachmentPath = Join-Path $script:SmtpTestRoot 'smtp-results.csv'
    [System.IO.File]::WriteAllText($script:AttachmentPath, "Name,Status`nSMTP-BODY-MUST-NOT-CONTAIN-THIS,Healthy", [System.Text.UTF8Encoding]::new($false))
    $script:InlinePath = Join-Path $script:SmtpTestRoot 'smtp-logo.png'
    [System.IO.File]::WriteAllBytes($script:InlinePath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))

    function New-SmtpTestEmail {
        param([switch] $WithResources)
        $Email = New-PSIEmail -Title 'SMTP test' -BrandName 'Example Automation' -LogoContentId 'smtp-logo'
        $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow |
            Add-PSIEmailText -Text 'Fictional SMTP content' | Out-Null
        if ($WithResources) {
            $Email | Add-PSIEmailAttachment -Path $script:AttachmentPath -Name 'registered-results.csv' |
                Add-PSIEmailInlineResource -Path $script:InlinePath -ContentId 'smtp-logo' | Out-Null
        }
        $Email
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:SmtpTestRoot) {
        Remove-Item -LiteralPath $script:SmtpTestRoot -Recurse -Force
    }
}

Describe 'Send-PSIEmailSmtp command contract' {
    It 'is exported, supports ShouldProcess, and exposes no plain-text password parameter' {
        $Command = Get-Command Send-PSIEmailSmtp -Module PSInsightEmail
        $Command | Should -Not -BeNullOrEmpty
        $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        $Command.Parameters.ContainsKey('Password') | Should -BeFalse
        $Command.Parameters.Credential.ParameterType | Should -Be ([pscredential])
    }

    It 'validates malformed recipients before delivery even under WhatIf' {
        $Email = New-SmtpTestEmail
        { Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' `
            -From 'automation@example.invalid' -To 'not an address' -Subject 'Test' -WhatIf } |
            Should -Throw '*Invalid To email address*'
    }

    It 'requires at least one To recipient' {
        $Parameter = (Get-Command Send-PSIEmailSmtp).Parameters.To
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateCountAttribute] }).Count | Should -Be 1
    }

    It 'builds and validates under WhatIf without calling the network helper or returning success' {
        $Email = New-SmtpTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            Mock Invoke-PSIEmailSmtpClientSend { throw 'Network helper must not run.' }
            $Result = Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' `
                -From 'automation@example.invalid' -To 'recipient@example.invalid' `
                -Subject 'WhatIf test' -PassThru -WhatIf
            $Result | Should -BeNullOrEmpty
            Should -Invoke Invoke-PSIEmailSmtpClientSend -Times 0 -Exactly
        }
    }
}

Describe 'PSInsightEmail SMTP message construction' {
    It 'maps multiple recipients, reply-to, subject, priority, HTML, and UTF-8 encoding' {
        $Email = New-SmtpTestEmail
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $Message = New-PSIEmailSmtpMessage -Email $Email `
                -From 'automation@example.invalid' `
                -To @('one@example.invalid', 'two@example.invalid') `
                -Cc @('copy@example.invalid') -Bcc @('audit@example.invalid') `
                -ReplyTo 'reply@example.invalid' -Subject 'Résumé ✓' -Priority High
            try {
                $Message.From.Address | Should -Be 'automation@example.invalid'
                @($Message.To).Count | Should -Be 2
                $Message.CC[0].Address | Should -Be 'copy@example.invalid'
                $Message.Bcc[0].Address | Should -Be 'audit@example.invalid'
                $Message.ReplyToList[0].Address | Should -Be 'reply@example.invalid'
                $Message.Subject | Should -Be 'Résumé ✓'
                $Message.Priority | Should -Be ([System.Net.Mail.MailPriority]::High)
                $Message.IsBodyHtml | Should -BeTrue
                $Message.Body | Should -Match '^<!DOCTYPE html>'
                $Message.Body | Should -Match 'Fictional SMTP content'
                $Message.BodyEncoding.WebName | Should -Be 'utf-8'
                $Message.SubjectEncoding.WebName | Should -Be 'utf-8'
            }
            finally { $Message.Dispose() }
        }
    }

    It 'maps the registered attachment name and content type without placing bytes in HTML' {
        $Email = New-SmtpTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $Message = New-PSIEmailSmtpMessage -Email $Email -From 'automation@example.invalid' `
                -To 'recipient@example.invalid' -Subject 'Attachment test'
            try {
                $Message.Attachments.Count | Should -Be 1
                $Message.Attachments[0].Name | Should -Be 'registered-results.csv'
                $Message.Attachments[0].ContentType.MediaType | Should -Be 'text/csv'
                $Message.Body | Should -Not -Match 'SMTP-BODY-MUST-NOT-CONTAIN-THIS'
                $Message.Body | Should -Not -Match 'registered-results\.csv'
            }
            finally { $Message.Dispose() }
        }
    }

    It 'maps inline resources to an HTML AlternateView and preserves CID and content type' {
        $Email = New-SmtpTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $Message = New-PSIEmailSmtpMessage -Email $Email -From 'automation@example.invalid' `
                -To 'recipient@example.invalid' -Subject 'Inline test'
            try {
                $Message.Body | Should -Match 'src="cid:smtp-logo"'
                $Message.AlternateViews.Count | Should -Be 1
                $View = $Message.AlternateViews[0]
                $View.ContentType.MediaType | Should -Be 'text/html'
                $View.LinkedResources.Count | Should -Be 1
                $View.LinkedResources[0].ContentId | Should -Be 'smtp-logo'
                $View.LinkedResources[0].ContentType.MediaType | Should -Be 'image/png'
            }
            finally { $Message.Dispose() }
        }
    }

    It 'rejects an attachment that disappears after registration' {
        $Path = Join-Path $script:SmtpTestRoot 'disappearing.csv'
        [System.IO.File]::WriteAllText($Path, 'sample')
        $Email = New-SmtpTestEmail | Add-PSIEmailAttachment -Path $Path
        Remove-Item -LiteralPath $Path -Force
        { Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' `
            -From 'automation@example.invalid' -To 'recipient@example.invalid' `
            -Subject 'Missing file' -WhatIf } | Should -Throw '*Resource file was not found*'
    }
}

Describe 'PSInsightEmail SMTP submission boundary' {
    It 'maps SSL, timeout, credentials, and returns a safe PassThru result after mocked submission' {
        $Email = New-SmtpTestEmail -WithResources
        $SecurePassword = ConvertTo-SecureString 'test-only-secret' -AsPlainText -Force
        $Credential = [pscredential]::new('example-user', $SecurePassword)
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email; Credential = $Credential } {
            param($Email, $Credential)
            $script:ObservedClient = $null
            Mock Invoke-PSIEmailSmtpClientSend {
                param($Client, $Message)
                $script:ObservedClient = [pscustomobject]@{
                    Host = $Client.Host
                    Port = $Client.Port
                    EnableSsl = $Client.EnableSsl
                    Timeout = $Client.Timeout
                    CredentialType = $Client.Credentials.GetType().FullName
                    ToCount = $Message.To.Count
                }
            }
            $Result = Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' -Port 2525 `
                -From 'automation@example.invalid' -To @('one@example.invalid', 'two@example.invalid') `
                -Cc 'copy@example.invalid' -Bcc 'audit@example.invalid' `
                -Subject 'Example operational report' -UseSsl -Credential $Credential `
                -TimeoutSeconds 42 -PassThru

            Should -Invoke Invoke-PSIEmailSmtpClientSend -Times 1 -Exactly
            $script:ObservedClient.Host | Should -Be 'smtp.example.invalid'
            $script:ObservedClient.Port | Should -Be 2525
            $script:ObservedClient.EnableSsl | Should -BeTrue
            $script:ObservedClient.Timeout | Should -Be 42000
            $script:ObservedClient.CredentialType | Should -Match 'NetworkCredential'
            $script:ObservedClient.ToCount | Should -Be 2

            $Result.PSObject.TypeNames | Should -Contain 'PSInsightEmail.SmtpResult'
            $Result.Transport | Should -Be 'SMTP'
            $Result.Success | Should -BeTrue
            $Result.Server | Should -Be 'smtp.example.invalid'
            $Result.Port | Should -Be 2525
            $Result.UseSsl | Should -BeTrue
            @($Result.To).Count | Should -Be 2
            @($Result.Cc).Count | Should -Be 1
            @($Result.Bcc).Count | Should -Be 1
            $Result.Subject | Should -Be 'Example operational report'
            $Result.AttachmentCount | Should -Be 1
            $Result.InlineCount | Should -Be 1
            $Result.SentAt | Should -BeOfType [datetime]
            $Result.DurationMs | Should -BeOfType [long]
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Credential'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Password'
        }
    }

    It 'releases attachment and inline-resource streams after mocked submission' {
        $Email = New-SmtpTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            Mock Invoke-PSIEmailSmtpClientSend {}
            Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' `
                -From 'automation@example.invalid' -To 'recipient@example.invalid' `
                -Subject 'Disposal test' | Out-Null
        }
        foreach ($Path in @($script:AttachmentPath, $script:InlinePath)) {
            $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $Stream.Dispose()
        }
    }

    It 'throws a controlled error and releases resource streams when submission fails' {
        $Email = New-SmtpTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            Mock Invoke-PSIEmailSmtpClientSend { throw 'simulated submission failure' }
            { Send-PSIEmailSmtp -Email $Email -SmtpServer 'smtp.example.invalid' `
                -From 'automation@example.invalid' -To 'recipient@example.invalid' `
                -Subject 'Failure disposal test' -PassThru } |
                Should -Throw 'SMTP delivery failed: simulated submission failure'
        }
        foreach ($Path in @($script:AttachmentPath, $script:InlinePath)) {
            $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $Stream.Dispose()
        }
    }
}

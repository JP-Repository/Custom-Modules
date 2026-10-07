BeforeAll {
    $script:ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path $script:ModuleRoot 'PSInsightEmail.psd1') -Force
    $script:GraphTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PSInsightEmail-Graph-' + [guid]::NewGuid().ToString('N'))
    [void] (New-Item -Path $script:GraphTestRoot -ItemType Directory -Force)
    $script:AttachmentPath = Join-Path $script:GraphTestRoot 'graph-results.csv'
    $script:AttachmentText = "Name,Status`nGRAPH-ATTACHMENT-ONLY,Healthy"
    [System.IO.File]::WriteAllText($script:AttachmentPath, $script:AttachmentText, [System.Text.UTF8Encoding]::new($false))
    $script:InlinePath = Join-Path $script:GraphTestRoot 'graph-logo.png'
    [System.IO.File]::WriteAllBytes($script:InlinePath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))

    function New-GraphTestEmail {
        param([switch] $WithResources)
        $Email = New-PSIEmail -Title 'Graph test' -BrandName 'Example Automation' -LogoContentId 'graph-logo'
        $Email | Add-PSIEmailSection -Title 'Summary' | Add-PSIEmailRow |
            Add-PSIEmailText -Text 'Fictional Graph content' | Out-Null
        if ($WithResources) {
            $Email | Add-PSIEmailAttachment -Path $script:AttachmentPath -Name 'registered-results.csv' |
                Add-PSIEmailInlineResource -Path $script:InlinePath -ContentId 'graph-logo' | Out-Null
        }
        $Email
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:GraphTestRoot) {
        Remove-Item -LiteralPath $script:GraphTestRoot -Recurse -Force
    }
}

Describe 'Send-PSIEmailGraph command contract' {
    It 'is exported, supports ShouldProcess, and uses the documented defaults' {
        $Command = Get-Command Send-PSIEmailGraph -Module PSInsightEmail
        $Command | Should -Not -BeNullOrEmpty
        $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
        $Command.Parameters.AccessToken.ParameterType | Should -Be ([string])
        $Command.Parameters.SaveToSentItems.ParameterType | Should -Be ([bool])
        $Command.Parameters.ContainsKey('From') | Should -BeFalse
    }

    It 'builds and serializes under WhatIf without invoking the request helper or returning success' {
        $Email = New-GraphTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            Mock Invoke-PSIEmailGraphRequest { throw 'Request helper must not run.' }
            $Result = Send-PSIEmailGraph -Email $Email -AccessToken 'whatif-token' `
                -To 'recipient@example.invalid' -Subject 'WhatIf test' -PassThru -WhatIf
            $Result | Should -BeNullOrEmpty
            Should -Invoke Invoke-PSIEmailGraphRequest -Times 0 -Exactly
        }
    }
}

Describe 'PSInsightEmail Graph endpoint resolution' {
    It 'uses the default me endpoint and normalizes the default BaseUri' {
        InModuleScope PSInsightEmail {
            Resolve-PSIEmailGraphEndpoint -BaseUri 'https://graph.microsoft.com/v1.0/' -UserId 'me' |
                Should -Be 'https://graph.microsoft.com/v1.0/me/sendMail'
        }
    }

    It 'uses an encoded users endpoint for an explicit UserId' {
        InModuleScope PSInsightEmail {
            Resolve-PSIEmailGraphEndpoint -BaseUri 'https://graph.microsoft.com/v1.0' `
                -UserId 'sender+reports@example.invalid' |
                Should -Be 'https://graph.microsoft.com/v1.0/users/sender%2Breports%40example.invalid/sendMail'
        }
    }

    It 'rejects invalid UserId and BaseUri values before submission' {
        InModuleScope PSInsightEmail {
            { Resolve-PSIEmailGraphEndpoint -BaseUri 'http://graph.example.invalid/v1.0' -UserId 'me' } |
                Should -Throw '*absolute HTTPS URI*'
            { Resolve-PSIEmailGraphEndpoint -BaseUri 'https://graph.example.invalid/v1.0?token=value' -UserId 'me' } |
                Should -Throw '*query string*'
            { Resolve-PSIEmailGraphEndpoint -BaseUri 'https://graph.example.invalid/v1.0' -UserId ' padded ' } |
                Should -Throw '*Graph UserId*'
        }
    }
}

Describe 'PSInsightEmail Graph message construction' {
    It 'maps recipients, ReplyTo, subject, importance, HTML, and the default sent-items behavior' {
        $Email = New-GraphTestEmail
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $Payload = New-PSIEmailGraphMessage -Email $Email `
                -To @('one@example.invalid', 'two@example.invalid') `
                -Cc 'copy@example.invalid' -Bcc 'audit@example.invalid' `
                -ReplyTo 'reply@example.invalid' -Subject 'Résumé ✓' -Importance High
            $Payload.saveToSentItems | Should -BeTrue
            @($Payload.message.toRecipients).Count | Should -Be 2
            $Payload.message.ccRecipients[0].emailAddress.address | Should -Be 'copy@example.invalid'
            $Payload.message.bccRecipients[0].emailAddress.address | Should -Be 'audit@example.invalid'
            $Payload.message.replyTo[0].emailAddress.address | Should -Be 'reply@example.invalid'
            $Payload.message.subject | Should -Be 'Résumé ✓'
            $Payload.message.importance | Should -Be 'high'
            $Payload.message.body.contentType | Should -Be 'HTML'
            $Payload.message.body.content | Should -Match '^<!DOCTYPE html>'
            $Payload.message.body.content | Should -Match 'Fictional Graph content'
        }
    }

    It 'supports SaveToSentItems false and omits empty optional recipient collections' {
        $Email = New-GraphTestEmail
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $Payload = New-PSIEmailGraphMessage -Email $Email -To 'recipient@example.invalid' `
                -Subject 'No sent copy' -SaveToSentItems:$false
            $Payload.saveToSentItems | Should -BeFalse
            @($Payload.message.Keys) | Should -Not -Contain 'ccRecipients'
            @($Payload.message.Keys) | Should -Not -Contain 'bccRecipients'
            @($Payload.message.Keys) | Should -Not -Contain 'replyTo'
        }
    }

    It 'validates malformed recipients before network submission' {
        $Email = New-GraphTestEmail
        { Send-PSIEmailGraph -Email $Email -AccessToken 'test-token' -To 'not an address' `
            -Subject 'Invalid recipient' -WhatIf } | Should -Throw '*Invalid To email address*'
    }

    It 'converts normal and inline resources without changing the composition object' {
        $Email = New-GraphTestEmail -WithResources
        $AttachmentProperties = @($Email.Attachments[0].PSObject.Properties.Name)
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email; ExpectedText = $script:AttachmentText } {
            param($Email, $ExpectedText)
            $Payload = New-PSIEmailGraphMessage -Email $Email -To 'recipient@example.invalid' -Subject 'Resources'
            @($Payload.message.attachments).Count | Should -Be 2
            $Regular = $Payload.message.attachments[0]
            $Regular.'@odata.type' | Should -Be '#microsoft.graph.fileAttachment'
            $Regular.name | Should -Be 'registered-results.csv'
            $Regular.contentType | Should -Be 'text/csv'
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Regular.contentBytes)) |
                Should -Be $ExpectedText
            @($Regular.Keys) | Should -Not -Contain 'isInline'

            $Inline = $Payload.message.attachments[1]
            $Inline.'@odata.type' | Should -Be '#microsoft.graph.fileAttachment'
            $Inline.isInline | Should -BeTrue
            $Inline.contentId | Should -Be 'graph-logo'
            $Inline.contentType | Should -Be 'image/png'
            $Payload.message.body.content | Should -Match 'src="cid:graph-logo"'
            $Payload.message.body.content | Should -Not -Match 'GRAPH-ATTACHMENT-ONLY'
        }
        $AttachmentProperties | Should -Not -Contain 'contentBytes'
        $Email.Attachments[0].PSObject.Properties.Name | Should -Not -Contain 'contentBytes'
    }

    It 'rejects an attachment that disappears after registration' {
        $Path = Join-Path $script:GraphTestRoot 'disappearing.txt'
        [System.IO.File]::WriteAllText($Path, 'sample')
        $Email = New-GraphTestEmail | Add-PSIEmailAttachment -Path $Path
        Remove-Item -LiteralPath $Path -Force
        { Send-PSIEmailGraph -Email $Email -AccessToken 'test-token' `
            -To 'recipient@example.invalid' -Subject 'Missing attachment' -WhatIf } |
            Should -Throw '*Resource file was not found*'
    }
}

Describe 'PSInsightEmail Graph request boundary' {
    It 'uses me and the default Graph BaseUri during public submission' {
        $Email = New-GraphTestEmail
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $script:DefaultGraphEndpoint = $null
            Mock Invoke-PSIEmailGraphRequest {
                param($Endpoint)
                $script:DefaultGraphEndpoint = $Endpoint
            }
            $Result = Send-PSIEmailGraph -Email $Email -AccessToken 'default-endpoint-token' `
                -To 'recipient@example.invalid' -Subject 'Default endpoint' -PassThru
            $script:DefaultGraphEndpoint | Should -Be 'https://graph.microsoft.com/v1.0/me/sendMail'
            $Result.UserId | Should -Be 'me'
            $Result.Endpoint | Should -Be 'https://graph.microsoft.com/v1.0/me/sendMail'
        }
    }

    It 'places the token only in the Authorization header and sends UTF-8 JSON' {
        InModuleScope PSInsightEmail {
            $script:ObservedRequest = $null
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Headers, $ContentType, $Body, $TimeoutSec, $ConnectionTimeoutSeconds)
                $ObservedTimeout = if ($null -ne $TimeoutSec) { $TimeoutSec } else { $ConnectionTimeoutSeconds }
                $script:ObservedRequest = [pscustomobject]@{
                    Uri = $Uri; Method = $Method; Headers = $Headers
                    ContentType = $ContentType; Body = [byte[]] $Body.Clone(); TimeoutSec = $ObservedTimeout
                }
            }
            $Json = '{"message":{"subject":"Résumé ✓"}}'
            Invoke-PSIEmailGraphRequest -Endpoint 'https://graph.example.invalid/v1.0/me/sendMail' `
                -AccessToken 'header-only-secret' -Json $Json -TimeoutSeconds 42
            $script:ObservedRequest.Method | Should -Be 'Post'
            $script:ObservedRequest.Headers.Authorization | Should -Be 'Bearer header-only-secret'
            $script:ObservedRequest.ContentType | Should -Be 'application/json; charset=utf-8'
            $script:ObservedRequest.TimeoutSec | Should -Be 42
            [Text.Encoding]::UTF8.GetString([byte[]] $script:ObservedRequest.Body) | Should -Be $Json
            $Json | Should -Not -Match 'header-only-secret'
        }
    }

    It 'returns a safe GraphResult after mocked submission' {
        $Email = New-GraphTestEmail -WithResources
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            $script:ObservedGraphCall = $null
            Mock Invoke-PSIEmailGraphRequest {
                param($Endpoint, $AccessToken, $Json, $TimeoutSeconds)
                $script:ObservedGraphCall = [pscustomobject]@{
                    Endpoint = $Endpoint; AccessToken = $AccessToken
                    Json = $Json; TimeoutSeconds = $TimeoutSeconds
                }
            }
            $Result = Send-PSIEmailGraph -Email $Email -AccessToken 'pass-thru-secret' `
                -To @('one@example.invalid', 'two@example.invalid') `
                -Cc 'copy@example.invalid' -Bcc 'audit@example.invalid' `
                -Subject 'Graph report' -UserId 'sender@example.invalid' `
                -Importance High -SaveToSentItems:$false -TimeoutSeconds 33 -PassThru

            Should -Invoke Invoke-PSIEmailGraphRequest -Times 1 -Exactly
            $script:ObservedGraphCall.Endpoint | Should -Be 'https://graph.microsoft.com/v1.0/users/sender%40example.invalid/sendMail'
            $script:ObservedGraphCall.AccessToken | Should -Be 'pass-thru-secret'
            $script:ObservedGraphCall.Json | Should -Not -Match 'pass-thru-secret'
            $script:ObservedGraphCall.TimeoutSeconds | Should -Be 33
            ($script:ObservedGraphCall.Json | ConvertFrom-Json).saveToSentItems | Should -BeFalse

            $Result.PSObject.TypeNames | Should -Contain 'PSInsightEmail.GraphResult'
            $Result.Transport | Should -Be 'Graph'
            $Result.Success | Should -BeTrue
            $Result.UserId | Should -Be 'sender@example.invalid'
            @($Result.To).Count | Should -Be 2
            @($Result.Cc).Count | Should -Be 1
            @($Result.Bcc).Count | Should -Be 1
            $Result.Subject | Should -Be 'Graph report'
            $Result.Importance | Should -Be 'high'
            $Result.AttachmentCount | Should -Be 1
            $Result.InlineCount | Should -Be 1
            $Result.SubmittedAt | Should -BeOfType [datetime]
            $Result.DurationMs | Should -BeOfType [long]
            $Result.PSObject.Properties.Name | Should -Not -Contain 'AccessToken'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Headers'
            $Result.PSObject.Properties.Name | Should -Not -Contain 'Body'
        }
    }

    It 'redacts the access token from controlled request errors' {
        $Email = New-GraphTestEmail
        InModuleScope PSInsightEmail -Parameters @{ Email = $Email } {
            param($Email)
            Mock Invoke-PSIEmailGraphRequest { throw 'request failed with Bearer never-show-this-token' }
            $Caught = $null
            try {
                Send-PSIEmailGraph -Email $Email -AccessToken 'never-show-this-token' `
                    -To 'recipient@example.invalid' -Subject 'Failure test'
            }
            catch { $Caught = $_.Exception.Message }
            $Caught | Should -Match '^Graph submission failed:'
            $Caught | Should -Not -Match 'never-show-this-token'
            $Caught | Should -Match '\[REDACTED\]'
        }
    }
}

# PSInsightEmail

PSInsightEmail is a dependency-free PowerShell framework for composing professional, email-safe HTML from PowerShell objects. It targets enterprise operational messages and keeps composition and presentation separate from delivery.

## Current capabilities

- Structured `Email → Sections → Rows → Components` composition.
- Text, KPI, key/value, alert, table, and divider components.
- Full-width status banners with visible severity labels.
- One-, two-, three-, and four-column email rows using presentation tables.
- A responsive 75%-width light design capped at 920px, with a fixed-width Outlook fallback.
- Reusable brand, environment, source, and footer metadata.
- HTML encoding for all supplied display values.
- Bounded email tables with an explicit truncation note.
- Optional table zebra striping, enabled by default.
- HTML-string conversion and local preview export.
- Transport-neutral regular attachments and CID-ready inline image resources.
- SMTP delivery with `ShouldProcess`, optional credentials, TLS, and structured results.
- Microsoft Graph `sendMail` delivery with caller-supplied bearer tokens and structured results.

PowerShell 5.1 is the declared minimum version. SMTP delivery is available through `Send-PSIEmailSmtp`, and Microsoft Graph delivery is available through `Send-PSIEmailGraph`. Recipient and authentication settings remain transport invocation data rather than part of the email composition object.

## Import

From the parent `Custom-Modules` directory:

```powershell
Import-Module ./PSInsightEmail/PSInsightEmail.psd1 -Force
Get-Command -Module PSInsightEmail
```

## Visual templates

`New-PSIEmail -Template` selects one of three light visual treatments. Templates affect color and hierarchy only; component data and the object model remain the same.

- `Operational` (default): execution results, change summaries, and automation outcomes.
- `Health`: health checks, renewals, and expiry outlooks.
- `Threshold`: limits, exceptions, and review queues.

## Operational example

```powershell
$Email = New-PSIEmail -Title 'Operational Summary' `
    -Subtitle 'Fictional maintenance workflow' `
    -Preheader 'The sample operation completed successfully.' `
    -Template Operational -BrandName 'Example Automation' `
    -EnvironmentLabel 'Example Production' -EnvironmentStatus Healthy `
    -SourceLabel 'Sample workflow' `
    -FooterNote 'Automated sample run; review through the normal process.'

$Email |
    Add-PSIEmailSection -Title 'Execution Result' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Healthy -Title 'Changes applied' `
        -Message 'All fictional validation checks passed.' |
    Add-PSIEmailRow -Columns 3 |
    Add-PSIEmailKPI -Title 'Steps' -Value 3 -Status Informational |
    Add-PSIEmailKPI -Title 'Succeeded' -Value 3 -Status Healthy |
    Add-PSIEmailKPI -Title 'Failed' -Value 0 -Status Healthy |
    Add-PSIEmailRow |
    Add-PSIEmailText -Text 'No follow-up is required for this fictional run.' |
    Out-Null

$Html = ConvertTo-PSIEmailHtml -Email $Email
Export-PSIEmailPreview -Email $Email -Path ./PSInsightEmail/Examples/Preview/Service-Summary.html
```

Run the fictional examples from `Custom-Modules`:

```powershell
./PSInsightEmail/Examples/New-DemoEmail.ps1
./PSInsightEmail/Examples/New-OperationalEmail.ps1
./PSInsightEmail/Examples/New-HealthEmail.ps1
./PSInsightEmail/Examples/New-ThresholdEmail.ps1
./PSInsightEmail/Examples/New-AttachmentEmail.ps1
./PSInsightEmail/Examples/New-SmtpEmailExample.ps1
./PSInsightEmail/Examples/New-GraphEmailExample.ps1
```

## Attachments and inline resources

Registration stores local-file metadata; it does not read normal attachment bytes into the email object and does not send anything.

```powershell
$Email = New-PSIEmail -Title 'Result summary' `
    -BrandName 'Example Automation' `
    -LogoContentId 'example-logo@psinsightemail'

$Email | Add-PSIEmailAttachment -Path ./Output/results.csv -Name 'results.csv' | Out-Null

$Email | Add-PSIEmailInlineResource -Path ./Assets/logo.png `
    -ContentId 'example-logo@psinsightemail' | Out-Null
```

A regular attachment is a separate downloadable file for a transport adapter. An inline resource is an image intended for a MIME content ID reference such as `cid:example-logo@psinsightemail`. `ConvertTo-PSIEmailHtml` preserves that CID reference. `Export-PSIEmailPreview` temporarily embeds a matching registered PNG, JPEG, or GIF up to 1 MB as a data URI so a browser preview can display it; it does not modify the email object.

Generated previews and demo resource files are ignored by Git. `LogoPath` remains backward-compatible and can embed a PNG, JPEG, or GIF up to 1 MB as a data URI. Outlook support for data-URI images varies, so brand text remains the reliable fallback. SMTP delivery converts registered inline resources into MIME linked resources; Graph converts them into inline file attachments. Both preserve registered content IDs. See [Architecture](docs/Architecture.md) for the object, rendering, and transport contracts.

## SMTP transport

`Send-PSIEmailSmtp` renders the existing email object and translates its registered attachments and inline resources into a dependency-free .NET SMTP message. It uses `System.Net.Mail.SmtpClient` for Windows PowerShell 5.1 compatibility; `Send-MailMessage` is not used. SMTP availability, relay permission, authentication, TLS requirements, and message-size limits depend on the organization's mail server.

Validate a relay message without connecting or sending:

```powershell
Send-PSIEmailSmtp -Email $Email `
    -SmtpServer 'smtp.example.invalid' `
    -From 'automation@example.invalid' `
    -To 'recipient@example.invalid' `
    -Subject 'Example Operational Report' `
    -WhatIf
```

SSL, credentials, and multiple recipients remain transport invocation details:

```powershell
$Credential = Get-Credential
$Result = Send-PSIEmailSmtp -Email $Email `
    -SmtpServer 'smtp.example.invalid' -Port 587 -UseSsl `
    -Credential $Credential `
    -From 'automation@example.invalid' `
    -To @('operator1@example.invalid', 'operator2@example.invalid') `
    -Cc 'reviewer@example.invalid' `
    -Subject 'Example Operational Report' `
    -Priority High -PassThru
```

`-PassThru` returns delivery metadata only after `SmtpClient.Send()` completes. It never includes credentials or attachment contents. Regular attachments become MIME attachments at send time. Inline resources become linked resources with their registered CID and are not added as visible attachments. Run [New-SmtpEmailExample.ps1](Examples/New-SmtpEmailExample.ps1) for a safe fictional example that always uses `-WhatIf`.

## Microsoft Graph transport

`Send-PSIEmailGraph` submits the same rendered email through the Microsoft Graph `sendMail` endpoint. PSInsightEmail does not acquire OAuth tokens: the caller must supply a valid bearer token with sufficient Microsoft Graph permission. The token is used only in the request authorization header and is never added to the email object, JSON body, result, or verbose output.

The default `UserId` is `me`, which targets `/me/sendMail`. This delegated-style example validates the complete request without making a network call:

```powershell
Send-PSIEmailGraph -Email $Email `
    -AccessToken '<ACCESS-TOKEN>' `
    -To 'recipient@example.invalid' `
    -Subject 'Example Graph Report' `
    -WhatIf
```

Supply a user ID or user principal name to target `/users/{encoded-user-id}/sendMail`. Recipients remain transport invocation data, and `SaveToSentItems` defaults to true:

```powershell
$Result = Send-PSIEmailGraph -Email $Email `
    -AccessToken $AccessToken `
    -UserId 'sender@example.invalid' `
    -To @('operator1@example.invalid', 'operator2@example.invalid') `
    -Cc 'reviewer@example.invalid' `
    -Subject 'Example Graph Report' `
    -Importance High `
    -SaveToSentItems:$true `
    -PassThru
```

At submission time, regular attachments become Graph `fileAttachment` objects and inline resources become inline `fileAttachment` objects with their registered content IDs. The direct `sendMail` payload includes Base64 file content but the rendered HTML does not. `-PassThru` reports successful request submission rather than final mailbox delivery and never includes tokens, headers, HTML, or attachment content. Large attachments that require Graph upload sessions are not supported yet; Graph size-limit errors are surfaced without dropping files. Run [New-GraphEmailExample.ps1](Examples/New-GraphEmailExample.ps1) for a safe fictional example that always uses `-WhatIf`.

## Accessibility and compatibility

Status components always include explicit status text, with color used as a secondary cue. Layout tables use `role="presentation"`; data and key/value tables retain semantic headers, including column or row scope. User-supplied content is HTML-encoded, titles use heading elements, and brand text remains visible if a logo cannot load. The light palettes use restrained, contrasting foreground and background colors, though direct assistive-technology and email-client testing is still required.

See [Email Client Compatibility](docs/Email-Client-Compatibility.md) for the design target, Outlook-specific fallbacks, and current validation status.

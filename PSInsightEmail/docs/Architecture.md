# Architecture

## Email object model

PSInsightEmail uses a small mutable object hierarchy:

```text
Email
  Sections
    Rows
      Components
  Attachments
  InlineResources
```

`New-PSIEmail` creates a `PSInsightEmail.Email` object containing `Title`, `Subtitle`, `Preheader`, `Template`, header/footer metadata, `GeneratedOn`, `ModuleVersion`, and three `List[object]` collections named `Sections`, `Attachments`, and `InlineResources`. A section contains its title, optional description, and rows. A row specifies one, two, three, or four columns and holds its components. Composition commands append to the latest section or row and return the same email object, enabling pipeline construction.

The `Operational`, `Health`, and `Threshold` templates select restrained palette tokens used by the renderer. Template selection changes presentation only. It does not alter component contracts or introduce external template files.

## Component model

Every component has this internal contract:

```powershell
[pscustomobject]@{
    Type       = 'Text'
    Properties = @{ Text = 'Example'; Size = 'Normal' }
}
```

`Properties` implements `IDictionary`; it contains structured values rather than markup. There is no raw-HTML input. The renderer encodes every title, label, message, table cell, key, and value at the point where it becomes HTML.

## Renderer

`ConvertTo-PSIEmailHtml` validates the email object and returns a complete HTML document without writing a file. `Export-PSIEmailPreview` is a thin development boundary: it calls the converter, writes UTF-8 HTML, optionally requests the operating system's default opener, and returns `FileInfo`.

The rendered body uses a centered 75%-width container capped at 920px. Sections and rows are nested `<table role="presentation">` structures. One- through four-column rows are emitted as table cells with explicit widths. Component styling is inline, colors are literal values, and fonts use the `Segoe UI, Arial, Helvetica, sans-serif` system stack. Status components include visible status text, so meaning does not depend on color.

Layout-only tables carry `role="presentation"`. Actual data tables omit that role and use `<thead>`, `<tbody>`, and `<th scope="col">`; compact key/value tables use scoped row headers. The email title and section titles use heading elements. These semantics remain useful when visual styles are removed during forwarding, printing, or assistive-technology navigation.

The preheader uses a hidden, inbox-preview-compatible block before the visible container. It is never repeated in the visible header. The visible header contains the title, optional subtitle, generated timestamp, and optional brand, environment, and source metadata. The footer can show one concise execution or source note.

`LogoPath` is preview-oriented. PNG, JPEG, and GIF files up to 1 MB are embedded as data URIs, avoiding an external image request. Missing, unsupported, oversized, or unreadable files are omitted while brand text remains visible. Some Outlook versions do not render data-URI images; the SMTP and Graph adapters provide CID embedding for registered inline resources.

## Email-client compatibility strategy

Email clients support a narrower and less consistent HTML/CSS surface than browsers. The foundation therefore uses simple HTML, presentation tables, `cellpadding`, `cellspacing`, explicit widths, inline styles, and restrained light-theme colors. Critical layout does not depend on CSS Grid or Flexbox. There are no external stylesheets, web fonts, images, CSS variables, SVG requirements, or browser storage APIs.

The outer report container uses 75% of the available desktop width with a 920px maximum. A conditional 920px MSO table gives traditional Outlook desktop a stable Word-rendering width, while the normal table retains percentage sizing. A small viewport enhancement restores the container to 100% width below 720px; the content remains table-based and readable if media rules are removed. Multi-column rows use explicit HTML and CSS cell widths with fixed table layout. Typography uses the `Segoe UI` system stack, pixel line heights, and selected `mso-line-height-rule` hints to reduce Outlook variation. Background colors are supplied with both conservative HTML attributes and inline CSS where useful.

JavaScript is prohibited because major email clients remove, block, or refuse to execute it, and executable content is inappropriate for portable operational email. Interactive report behavior such as search, sorting, pagination, and client-side export belongs in browser reports, not email bodies. Email tables instead render a bounded record set and disclose truncation.

## Transport boundary

The PSInsightEmail composition model and renderer own email-safe presentation and transport-neutral resource registration. They do not know about recipients, SMTP settings, Microsoft Graph, authentication, or sending. Transport adapters consume the HTML string and resource metadata while owning their credentials, delivery options, encoding, and provider-specific size constraints. Keeping that boundary separate allows the same composed email to be previewed, tested, and passed to different senders without coupling authentication or delivery state to rendering.

### Regular attachments

`Add-PSIEmailAttachment` validates a local file and records its normalized path, safe display name, detected or supplied content type, and byte length. It does not read or Base64-encode the file. Exact duplicate path/name registrations are rejected. The renderer ignores regular attachments, so attachment data and paths never enter the HTML body.

```text
PSInsightEmail.Attachment
  Path
  Name
  ContentType
  Length
```

### Inline resources

`Add-PSIEmailInlineResource` records the same file metadata plus a MIME-safe, email-unique `ContentId`. Phase 3 accepts PNG, JPEG, and GIF resources. A caller can supply a safe ID or allow a deterministic ID to be generated from the normalized local path. Inline registration alone does not add markup.

```text
PSInsightEmail.InlineResource
  Path
  Name
  ContentType
  ContentId
  Length
```

When `LogoContentId` is set, production HTML from `ConvertTo-PSIEmailHtml` uses `src="cid:<ContentId>"`. Preview export privately resolves a matching registered resource and embeds supported images up to 1 MB as a data URI, without changing the email object. Larger images retain their metadata but are omitted from the browser preview. `LogoPath` remains the backward-compatible direct-preview path and is never converted into a CID automatically.

The SMTP adapter constructs MIME attachment and related-resource parts from these objects. The Graph adapter translates the same metadata into Graph file-attachment shapes. Each adapter reads and encodes content at its delivery boundary and enforces its own provider constraints; the core model assumes neither transport's limits.

```text
               PSInsightEmail.Email
                       |
                 HTML renderer
                       |
              +--------+--------+
              |                 |
            SMTP              Graph
```

## SMTP transport adapter

```text
Email composition
        |
        v
ConvertTo-PSIEmailHtml
        |
        v
SMTP transport adapter
        |
        v
System.Net.Mail.SmtpClient
```

`Send-PSIEmailSmtp` owns recipients, relay settings, optional credentials, TLS selection, priority, and submission. It calls the existing renderer and never reconstructs sections or components. Recipients and credentials are invocation data and are never added to the email object.

The private SMTP message builder converts regular attachment metadata into `System.Net.Mail.Attachment` objects and inline resource metadata into `LinkedResource` objects on an HTML `AlternateView`. Files are revalidated and opened only at the send boundary. The public command disposes the message and SMTP client in `finally`; disposing the message releases attachments, alternate views, linked resources, and their file streams.

Message construction happens before `ShouldProcess`. Therefore `-WhatIf` validates addresses, renders HTML, opens registered resources, and catches missing local files, but it does not create an SMTP client or connect. Submission is isolated behind a private helper so automated tests can replace the network call while exercising the real MIME construction and disposal path.

The implementation uses built-in `System.Net.Mail` for dependency-free Windows PowerShell 5.1 compatibility. It does not disable certificate validation or implement retries.

## Microsoft Graph transport adapter

`Send-PSIEmailGraph` calls the same `ConvertTo-PSIEmailHtml` renderer and translates recipients and registered resources into a PowerShell object matching the Graph `sendMail` request shape. `ConvertTo-Json` performs serialization; the adapter does not concatenate JSON or alter the email composition object.

The default sender context is `/me/sendMail`. An explicit `UserId` selects `/users/{encoded-user-id}/sendMail`; the adapter never infers sender identity from recipients or composition metadata. The caller supplies the bearer token, which is added only to the authorization header by the private request helper. Token acquisition, tenants, app registrations, MSAL, and Microsoft.Graph SDK authentication remain outside this module.

Normal and inline files are revalidated and read at Graph message-construction time. Both become Graph `fileAttachment` objects; inline resources also carry `isInline = true` and their registered `contentId`. The direct request model does not support upload sessions, so large-attachment rejection remains a Graph service response surfaced as a controlled error.

Graph message construction and JSON serialization happen before `ShouldProcess`. `-WhatIf` therefore renders HTML, validates addresses and files, reads attachment bytes, and constructs the final request body without invoking the request helper. The helper uses built-in `Invoke-RestMethod` with UTF-8 JSON and an HTTPS endpoint. A successful empty `sendMail` response is accepted as submission; it does not prove final recipient delivery.

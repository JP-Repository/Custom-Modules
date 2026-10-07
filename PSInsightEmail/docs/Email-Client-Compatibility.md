# Email Client Compatibility

PSInsightEmail targets conservative enterprise HTML email. The generated document uses a 75%-width table-based container capped at 920px, inline CSS, system fonts, encoded content, and no JavaScript or external resources. Layout-only tables use `role="presentation"`; real data tables retain semantic table structure.

## Compatibility strategy

- Use `<!DOCTYPE html>`, UTF-8 metadata, a language attribute, zero body margins, and a viewport hint.
- Use HTML table attributes alongside inline CSS for width, alignment, vertical alignment, borders, spacing, and background colors.
- Provide an MSO conditional 920px wrapper for traditional Outlook desktop.
- Keep one- through four-column KPI layouts readable at their declared widths without requiring stacking or media queries.
- Use Segoe UI, Arial, Helvetica, and generic sans-serif fonts with explicit font sizes, weights, and selected MSO line-height rules.
- Include visible text for every status; color and borders are secondary cues.
- Use `<thead>`, `<tbody>`, and scoped headers for data tables.
- Keep the title, status, metrics, table headings, and footer in static markup so printing and forwarding require no interaction.
- Hide the preheader with a compact, conventional pattern without invisible filler.

## Client matrix

| Client | Intended strategy | Validation status |
| --- | --- | --- |
| Outlook Windows desktop | Primary design target: presentation tables, fixed-width MSO wrapper, inline styles, HTML width/alignment attributes, and MSO line-height hints. | Structurally validated by automated tests; no direct Outlook desktop rendering session has been performed. |
| Outlook Web | Simple tables and inline CSS with no scripts or external assets. | Structurally validated only; no direct client session has been performed. |
| New Outlook | Same conservative HTML as Outlook Web, without reliance on browser interaction. | Structurally validated only; no direct client session has been performed. |
| Apple Mail | Standards-compatible document and inline styles; no essential media queries. | Not directly validated. |
| Gmail Web | Inline styles, table layout, system fonts, and static content. | Not directly validated. |

“Structurally validated” means Pester tests inspect the generated markup and the repository examples generate successfully. It does not mean the message has been sent through or visually reviewed in that client.

SMTP and Microsoft Graph delivery do not change or improve client rendering compatibility. Both adapters send the same HTML returned by `ConvertTo-PSIEmailHtml`; the client-specific validation status in this document remains unchanged.

## Logos

For standalone previews, `LogoPath` can embed a PNG, JPEG, or GIF up to 1 MB as a data URI. A CID-ready logo can instead be registered with `Add-PSIEmailInlineResource` and selected with `LogoContentId`. Production HTML preserves the `cid:` reference, while preview export uses the registered local image as a temporary data URI where practical. Data-URI image support is inconsistent in Outlook, so `BrandName` remains visible and the message never depends on the logo. SMTP converts registered inline resources into linked MIME resources, while Graph converts them into inline file attachments; both preserve their content IDs.

## Automatic dark mode

The source email remains a light design. Some clients may automatically transform colors in dark mode. PSInsightEmail does not add dark-mode selectors, CSS variables, or client-specific color overrides. Status meaning remains available as text if a client alters colors.

## Remaining validation work

Before claiming client support, capture visual baselines in Outlook Windows desktop, Outlook Web, New Outlook, Apple Mail, and Gmail Web. Review one-, three-, and four-column KPI rows; long data-table values; forwarding; printing; automatic dark mode; high zoom; and common screen-reader navigation. Verify contrast after any client-driven color transformation.

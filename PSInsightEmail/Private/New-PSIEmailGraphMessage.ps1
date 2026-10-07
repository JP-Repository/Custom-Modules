function ConvertTo-PSIEmailGraphRecipient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Address,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label
    )

    $Validated = Resolve-PSIEmailMailAddress -Address $Address -Label $Label
    [ordered]@{
        emailAddress = [ordered]@{
            address = $Validated.Address
        }
    }
}

function ConvertTo-PSIEmailGraphRecipients {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][string[]] $Addresses = @(),
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Label
    )

    foreach ($Address in @($Addresses)) {
        if ([string]::IsNullOrWhiteSpace($Address)) { throw "$Label recipient addresses cannot be empty." }
        ConvertTo-PSIEmailGraphRecipient -Address $Address -Label $Label
    }
}

function ConvertTo-PSIEmailGraphFileAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()] $Resource,
        [Parameter()][switch] $Inline
    )

    $Label = if ($Inline) { 'Inline resource' } else { 'Attachment' }
    $File = Resolve-PSIEmailRegisteredFile -Resource $Resource -Label $Label
    $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    try {
        $Attachment = [ordered]@{
            '@odata.type' = '#microsoft.graph.fileAttachment'
            name          = [string] $Resource.Name
            contentType   = [string] $Resource.ContentType
            contentBytes  = [Convert]::ToBase64String($Bytes)
        }
        if ($Inline) {
            $Attachment.contentId = Assert-PSIEmailContentId -ContentId ([string] $Resource.ContentId)
            $Attachment.isInline = $true
        }
        $Attachment
    }
    finally {
        if ($Bytes.Length -gt 0) { [Array]::Clear($Bytes, 0, $Bytes.Length) }
    }
}

function New-PSIEmailGraphMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateCount(1, 1024)][string[]] $To,
        [Parameter()][AllowEmptyCollection()][string[]] $Cc = @(),
        [Parameter()][AllowEmptyCollection()][string[]] $Bcc = @(),
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter()][AllowEmptyString()][string] $ReplyTo = '',
        [Parameter()][ValidateSet('Low', 'Normal', 'High')][string] $Importance = 'Normal',
        [Parameter()][bool] $SaveToSentItems = $true
    )

    if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email') {
        throw 'The supplied object is not a valid PSInsightEmail email.'
    }
    if ($Email.Attachments -isnot [System.Collections.Generic.List[object]] -or
        $Email.InlineResources -isnot [System.Collections.Generic.List[object]]) {
        throw 'The email does not contain valid attachment resource collections.'
    }

    $ToRecipients = @(ConvertTo-PSIEmailGraphRecipients -Addresses $To -Label 'To')
    if ($ToRecipients.Count -eq 0) { throw 'At least one To recipient is required.' }
    $CcRecipients = @(ConvertTo-PSIEmailGraphRecipients -Addresses $Cc -Label 'Cc')
    $BccRecipients = @(ConvertTo-PSIEmailGraphRecipients -Addresses $Bcc -Label 'Bcc')
    $Html = ConvertTo-PSIEmailHtml -Email $Email

    $Message = [ordered]@{
        subject      = $Subject
        body         = [ordered]@{
            contentType = 'HTML'
            content     = $Html
        }
        toRecipients = $ToRecipients
        importance   = $Importance.ToLowerInvariant()
    }
    if ($CcRecipients.Count -gt 0) { $Message.ccRecipients = $CcRecipients }
    if ($BccRecipients.Count -gt 0) { $Message.bccRecipients = $BccRecipients }
    if (-not [string]::IsNullOrWhiteSpace($ReplyTo)) {
        $Message.replyTo = @(
            ConvertTo-PSIEmailGraphRecipient -Address $ReplyTo -Label 'ReplyTo'
        )
    }

    $Attachments = [System.Collections.Generic.List[object]]::new()
    foreach ($Resource in @($Email.Attachments)) {
        $Attachments.Add((ConvertTo-PSIEmailGraphFileAttachment -Resource $Resource))
    }
    foreach ($Resource in @($Email.InlineResources)) {
        $Attachments.Add((ConvertTo-PSIEmailGraphFileAttachment -Resource $Resource -Inline))
    }
    if ($Attachments.Count -gt 0) { $Message.attachments = [object[]] $Attachments.ToArray() }

    [ordered]@{
        message         = $Message
        saveToSentItems = [bool] $SaveToSentItems
    }
}

function Resolve-PSIEmailGraphBaseUri {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $BaseUri)

    if ([string]::IsNullOrWhiteSpace($BaseUri)) { throw 'Graph BaseUri cannot be empty or whitespace.' }
    $Parsed = $null
    if (-not [Uri]::TryCreate($BaseUri, [UriKind]::Absolute, [ref] $Parsed) -or
        $Parsed.Scheme -ne [Uri]::UriSchemeHttps -or [string]::IsNullOrWhiteSpace($Parsed.Host)) {
        throw "Graph BaseUri must be an absolute HTTPS URI: $BaseUri"
    }
    if (-not [string]::IsNullOrEmpty($Parsed.UserInfo) -or
        -not [string]::IsNullOrEmpty($Parsed.Query) -or
        -not [string]::IsNullOrEmpty($Parsed.Fragment)) {
        throw 'Graph BaseUri cannot contain credentials, a query string, or a fragment.'
    }
    $Parsed.AbsoluteUri.TrimEnd('/')
}

function Resolve-PSIEmailGraphEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $BaseUri,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $UserId
    )

    $NormalizedBaseUri = Resolve-PSIEmailGraphBaseUri -BaseUri $BaseUri
    if ([string]::IsNullOrWhiteSpace($UserId) -or $UserId -ne $UserId.Trim() -or
        $UserId.IndexOfAny([char[]] @(0..31)) -ge 0) {
        throw 'Graph UserId cannot be empty, padded with whitespace, or contain control characters.'
    }
    if ([string]::Equals($UserId, 'me', [System.StringComparison]::OrdinalIgnoreCase)) {
        return "$NormalizedBaseUri/me/sendMail"
    }
    $EncodedUserId = [Uri]::EscapeDataString($UserId)
    "$NormalizedBaseUri/users/$EncodedUserId/sendMail"
}

function Get-PSIEmailGraphSafeErrorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord] $ErrorRecord,
        [Parameter()][AllowEmptyString()][string] $AccessToken = ''
    )

    $Message = if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $ErrorRecord.ErrorDetails.Message
    }
    else {
        $ErrorRecord.Exception.Message
    }
    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) { $Message = $Message.Replace($AccessToken, '[REDACTED]') }
    $Message -replace '(?i)Bearer\s+[^\s,;]+', 'Bearer [REDACTED]'
}

function Invoke-PSIEmailGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Endpoint,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $AccessToken,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Json,
        [Parameter()][ValidateRange(1, 86400)][int] $TimeoutSeconds = 100
    )

    $Headers = @{ Authorization = "Bearer $AccessToken" }
    $Utf8Body = [System.Text.UTF8Encoding]::new($false).GetBytes($Json)
    try {
        Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $Headers `
            -ContentType 'application/json; charset=utf-8' -Body $Utf8Body `
            -TimeoutSec $TimeoutSeconds -ErrorAction Stop | Out-Null
    }
    catch {
        $SafeMessage = Get-PSIEmailGraphSafeErrorMessage -ErrorRecord $_ -AccessToken $AccessToken
        throw "Microsoft Graph request failed: $SafeMessage"
    }
    finally {
        if ($Utf8Body.Length -gt 0) { [Array]::Clear($Utf8Body, 0, $Utf8Body.Length) }
    }
}

function Add-PSIEmailMailAddresses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Net.Mail.MailAddressCollection] $Collection,
        [Parameter()][AllowEmptyCollection()][string[]] $Addresses = @(),
        [Parameter(Mandatory = $true)][string] $Label
    )

    foreach ($Address in @($Addresses)) {
        if ([string]::IsNullOrWhiteSpace($Address)) { throw "$Label recipient addresses cannot be empty." }
        $Collection.Add((Resolve-PSIEmailMailAddress -Address $Address -Label $Label))
    }
}

function Add-PSIEmailSmtpAttachments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Net.Mail.MailMessage] $Message,
        [Parameter()][AllowEmptyCollection()][object[]] $Attachments = @()
    )

    foreach ($Metadata in @($Attachments)) {
        $File = Resolve-PSIEmailRegisteredFile -Resource $Metadata -Label 'Attachment'
        $Attachment = $null
        try {
            $Attachment = [System.Net.Mail.Attachment]::new($File.FullName, [string] $Metadata.ContentType)
            $Attachment.Name = [string] $Metadata.Name
            $Attachment.NameEncoding = [System.Text.Encoding]::UTF8
            $Attachment.TransferEncoding = [System.Net.Mime.TransferEncoding]::Base64
            $Message.Attachments.Add($Attachment)
            $Attachment = $null
        }
        finally {
            if ($null -ne $Attachment) { $Attachment.Dispose() }
        }
    }
}

function Add-PSIEmailSmtpInlineResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Net.Mail.MailMessage] $Message,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Html,
        [Parameter()][AllowEmptyCollection()][object[]] $InlineResources = @()
    )

    if (@($InlineResources).Count -eq 0) { return }
    $View = $null
    try {
        $View = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString(
            $Html, [System.Text.Encoding]::UTF8, 'text/html'
        )
        foreach ($Metadata in @($InlineResources)) {
            $File = Resolve-PSIEmailRegisteredFile -Resource $Metadata -Label 'Inline resource'
            $LinkedResource = $null
            try {
                $LinkedResource = [System.Net.Mail.LinkedResource]::new($File.FullName, [string] $Metadata.ContentType)
                $LinkedResource.ContentId = Assert-PSIEmailContentId -ContentId ([string] $Metadata.ContentId)
                $LinkedResource.TransferEncoding = [System.Net.Mime.TransferEncoding]::Base64
                $View.LinkedResources.Add($LinkedResource)
                $LinkedResource = $null
            }
            finally {
                if ($null -ne $LinkedResource) { $LinkedResource.Dispose() }
            }
        }
        $Message.AlternateViews.Add($View)
        $View = $null
    }
    finally {
        if ($null -ne $View) { $View.Dispose() }
    }
}

function New-PSIEmailSmtpMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $From,
        [Parameter(Mandatory = $true)][ValidateCount(1, 1024)][string[]] $To,
        [Parameter()][AllowEmptyCollection()][string[]] $Cc = @(),
        [Parameter()][AllowEmptyCollection()][string[]] $Bcc = @(),
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter()][AllowEmptyString()][string] $ReplyTo = '',
        [Parameter()][ValidateSet('Low', 'Normal', 'High')][string] $Priority = 'Normal'
    )

    if ($Email.PSObject.TypeNames -notcontains 'PSInsightEmail.Email') {
        throw 'The supplied object is not a valid PSInsightEmail email.'
    }
    if ($Email.Attachments -isnot [System.Collections.Generic.List[object]] -or
        $Email.InlineResources -isnot [System.Collections.Generic.List[object]]) {
        throw 'The email does not contain valid attachment resource collections.'
    }

    $Html = ConvertTo-PSIEmailHtml -Email $Email
    $Message = [System.Net.Mail.MailMessage]::new()
    try {
        $Message.From = Resolve-PSIEmailMailAddress -Address $From -Label 'From'
        Add-PSIEmailMailAddresses -Collection $Message.To -Addresses $To -Label 'To'
        if ($Message.To.Count -eq 0) { throw 'At least one To recipient is required.' }
        Add-PSIEmailMailAddresses -Collection $Message.CC -Addresses $Cc -Label 'Cc'
        Add-PSIEmailMailAddresses -Collection $Message.Bcc -Addresses $Bcc -Label 'Bcc'
        if (-not [string]::IsNullOrWhiteSpace($ReplyTo)) {
            $Message.ReplyToList.Add((Resolve-PSIEmailMailAddress -Address $ReplyTo -Label 'ReplyTo'))
        }
        $Message.Subject = $Subject
        $Message.SubjectEncoding = [System.Text.Encoding]::UTF8
        $Message.Body = $Html
        $Message.BodyEncoding = [System.Text.Encoding]::UTF8
        $Message.IsBodyHtml = $true
        $Message.Priority = [System.Net.Mail.MailPriority] [System.Enum]::Parse(
            [System.Net.Mail.MailPriority],
            $Priority,
            $true
        )
        Add-PSIEmailSmtpAttachments -Message $Message -Attachments @($Email.Attachments)
        Add-PSIEmailSmtpInlineResources -Message $Message -Html $Html -InlineResources @($Email.InlineResources)
        return $Message
    }
    catch {
        $Message.Dispose()
        throw
    }
}

function Invoke-PSIEmailSmtpClientSend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Net.Mail.SmtpClient] $Client,
        [Parameter(Mandatory = $true)][System.Net.Mail.MailMessage] $Message
    )
    $Client.Send($Message)
}

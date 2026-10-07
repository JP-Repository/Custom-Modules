function Send-PSIEmailSmtp {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $SmtpServer,
        [Parameter()][ValidateRange(1, 65535)][int] $Port = 25,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $From,
        [Parameter(Mandatory = $true)][ValidateCount(1, 1024)][string[]] $To,
        [Parameter()][AllowEmptyCollection()][string[]] $Cc = @(),
        [Parameter()][AllowEmptyCollection()][string[]] $Bcc = @(),
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter()][switch] $UseSsl,
        [Parameter()][AllowNull()][pscredential] $Credential,
        [Parameter()][ValidateRange(1, 86400)][int] $TimeoutSeconds = 100,
        [Parameter()][AllowEmptyString()][string] $ReplyTo = '',
        [Parameter()][ValidateSet('Low', 'Normal', 'High')][string] $Priority = 'Normal',
        [Parameter()][switch] $PassThru
    )
    process {
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Message = $null
        $Client = $null
        try {
            Write-Verbose 'Preparing SMTP message.'
            $Message = New-PSIEmailSmtpMessage -Email $Email -From $From -To $To -Cc $Cc -Bcc $Bcc `
                -Subject $Subject -ReplyTo $ReplyTo -Priority $Priority
            Write-Verbose ("Adding {0} attachment(s) and {1} inline resource(s)." -f $Message.Attachments.Count, $Email.InlineResources.Count)

            $Target = '{0}:{1}' -f $SmtpServer, $Port
            if (-not $PSCmdlet.ShouldProcess($Target, "Submit SMTP message '$Subject'")) { return }

            $Client = [System.Net.Mail.SmtpClient]::new($SmtpServer, $Port)
            $Client.EnableSsl = [bool] $UseSsl
            $Client.Timeout = $TimeoutSeconds * 1000
            if ($null -ne $Credential) { $Client.Credentials = $Credential.GetNetworkCredential() }

            Write-Verbose "Connecting to $Target."
            Invoke-PSIEmailSmtpClientSend -Client $Client -Message $Message
            Write-Verbose 'Message submitted.'
            $Timer.Stop()

            if ($PassThru) {
                [pscustomobject]@{
                    PSTypeName      = 'PSInsightEmail.SmtpResult'
                    Transport       = 'SMTP'
                    Success         = $true
                    Server          = $SmtpServer
                    Port            = $Port
                    UseSsl          = [bool] $UseSsl
                    From            = $Message.From.Address
                    To              = [string[]] @($Message.To | ForEach-Object { $_.Address })
                    Cc              = [string[]] @($Message.CC | ForEach-Object { $_.Address })
                    Bcc             = [string[]] @($Message.Bcc | ForEach-Object { $_.Address })
                    Subject         = $Message.Subject
                    AttachmentCount = $Message.Attachments.Count
                    InlineCount     = $Email.InlineResources.Count
                    SentAt          = Get-Date
                    DurationMs      = [long] $Timer.ElapsedMilliseconds
                }
            }
        }
        catch {
            $Timer.Stop()
            throw "SMTP delivery failed: $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $Client) { $Client.Dispose() }
            if ($null -ne $Message) { $Message.Dispose() }
            if ($Timer.IsRunning) { $Timer.Stop() }
        }
    }
}

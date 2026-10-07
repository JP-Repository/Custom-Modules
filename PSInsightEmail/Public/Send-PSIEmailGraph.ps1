function Send-PSIEmailGraph {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $AccessToken,
        [Parameter(Mandatory = $true)][ValidateCount(1, 1024)][string[]] $To,
        [Parameter()][AllowEmptyCollection()][string[]] $Cc = @(),
        [Parameter()][AllowEmptyCollection()][string[]] $Bcc = @(),
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Subject,
        [Parameter()][ValidateNotNullOrEmpty()][string] $UserId = 'me',
        [Parameter()][AllowEmptyString()][string] $ReplyTo = '',
        [Parameter()][ValidateSet('Low', 'Normal', 'High')][string] $Importance = 'Normal',
        [Parameter()][bool] $SaveToSentItems = $true,
        [Parameter()][ValidateNotNullOrEmpty()][string] $BaseUri = 'https://graph.microsoft.com/v1.0',
        [Parameter()][ValidateRange(1, 86400)][int] $TimeoutSeconds = 100,
        [Parameter()][switch] $PassThru
    )
    process {
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Json = $null
        try {
            if ([string]::IsNullOrWhiteSpace($AccessToken)) { throw 'AccessToken cannot be empty or whitespace.' }
            Write-Verbose 'Preparing Microsoft Graph message.'
            $Endpoint = Resolve-PSIEmailGraphEndpoint -BaseUri $BaseUri -UserId $UserId
            $Payload = New-PSIEmailGraphMessage -Email $Email -To $To -Cc $Cc -Bcc $Bcc `
                -Subject $Subject -ReplyTo $ReplyTo -Importance $Importance `
                -SaveToSentItems $SaveToSentItems
            $Json = $Payload | ConvertTo-Json -Depth 12 -Compress -ErrorAction Stop

            if (-not $PSCmdlet.ShouldProcess($Endpoint, "Submit Microsoft Graph message '$Subject'")) { return }

            Write-Verbose "Submitting message to Microsoft Graph endpoint $Endpoint."
            Invoke-PSIEmailGraphRequest -Endpoint $Endpoint -AccessToken $AccessToken `
                -Json $Json -TimeoutSeconds $TimeoutSeconds
            Write-Verbose 'Microsoft Graph accepted the sendMail request.'
            $Timer.Stop()

            if ($PassThru) {
                [pscustomobject]@{
                    PSTypeName      = 'PSInsightEmail.GraphResult'
                    Transport       = 'Graph'
                    Success         = $true
                    Endpoint        = $Endpoint
                    UserId          = $UserId
                    To              = [string[]] @($Payload.message.toRecipients | ForEach-Object { $_.emailAddress.address })
                    Cc              = [string[]] @($Payload.message.ccRecipients | ForEach-Object { $_.emailAddress.address })
                    Bcc             = [string[]] @($Payload.message.bccRecipients | ForEach-Object { $_.emailAddress.address })
                    Subject         = $Payload.message.subject
                    Importance      = $Payload.message.importance
                    AttachmentCount = $Email.Attachments.Count
                    InlineCount     = $Email.InlineResources.Count
                    SubmittedAt     = Get-Date
                    DurationMs      = [long] $Timer.ElapsedMilliseconds
                }
            }
        }
        catch {
            $Timer.Stop()
            $SafeMessage = Get-PSIEmailGraphSafeErrorMessage -ErrorRecord $_ -AccessToken $AccessToken
            throw "Graph submission failed: $SafeMessage"
        }
        finally {
            if ($Timer.IsRunning) { $Timer.Stop() }
            $Json = $null
        }
    }
}

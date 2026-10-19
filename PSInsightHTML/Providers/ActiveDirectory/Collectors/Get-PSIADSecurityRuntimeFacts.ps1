function Get-PSIADSecurityRuntimeFacts {
    <# .SYNOPSIS Collect bounded read-only security facts in one optional session to a DC. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $HostName,[ValidateRange(1,168)][int] $WindowHours=72)
    if (-not (Get-Command Invoke-Command -ErrorAction SilentlyContinue)) { throw [System.NotSupportedException]::new('PowerShell remoting is unavailable.') }
    Invoke-Command -ComputerName $HostName -ArgumentList $WindowHours -ErrorAction Stop -ScriptBlock {
        param($Hours)
        $Now=Get-Date; $Facts=[System.Collections.Generic.List[object]]::new(); $Telemetry=[System.Collections.Generic.List[object]]::new()
        function Add-Fact { param($Rule,$Value,$Type,$Source,$State='Collected',$Confidence='High',$Detail=$null,$ErrorClass='')
            $Facts.Add([pscustomobject]@{ RuleId=$Rule; Value=$Value; EvidenceType=$Type; SourceType=$Source; CollectionState=$State; Confidence=$Confidence; Detail=$Detail; ErrorClass=$ErrorClass; Timestamp=$Now; QueryWindowHours=$null })
        }
        function Get-Dword { param($Path,$Name)
            try { $Item=Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop; [pscustomobject]@{ State='Collected'; Value=[int]$Item.$Name } }
            catch { [pscustomobject]@{ State='NotTested'; Value=$null } }
        }
        # Direct runtime and effective local observations; individual failures do not erase other facts.
        try {
            $S=Get-SmbServerConfiguration -ErrorAction Stop
            $Client=$null
            try { $Client=Get-SmbClientConfiguration -ErrorAction Stop } catch { }
            $Value=if ($S.RequireSecuritySignature) { 'Required' } elseif ($S.EnableSecuritySignature) { 'EnabledNotRequired' } else { 'Disabled' }
            Add-Fact 'smb-signing' $Value 'EffectivePolicy' 'RuntimeConfiguration' 'Collected' 'High' ([pscustomobject]@{ ServerEnabled=[bool]$S.EnableSecuritySignature; ServerRequired=[bool]$S.RequireSecuritySignature; ClientEnabled=if ($Client) { [bool]$Client.EnableSecuritySignature } else { $null }; ClientRequired=if ($Client) { [bool]$Client.RequireSecuritySignature } else { $null }; ClientCollectionState=if ($Client) { 'Collected' } else { 'NotSupported' } })
            Add-Fact 'smbv1' $(if ($S.EnableSMB1Protocol) { 'Enabled' } else { 'Disabled' }) 'EffectiveConfiguration' 'RuntimeConfiguration'
        } catch { $State=if ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -or $_.Exception -is [System.NotSupportedException]) { 'NotSupported' } else { 'Failed' }; Add-Fact 'smb-signing' $null 'EffectivePolicy' 'RuntimeConfiguration' $State 'None' $null $_.Exception.GetType().Name }
        try {
            $Profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
            if ($Profiles.Count -eq 3) {
                $State=if (@($Profiles | Where-Object { -not $_.Enabled }).Count -eq 0) { 'Enabled' } elseif (@($Profiles | Where-Object { $_.Enabled }).Count) { 'Partial' } else { 'Disabled' }
                Add-Fact 'firewall' $State 'EffectiveConfiguration' 'RuntimeConfiguration' 'Collected' 'High' @($Profiles | ForEach-Object { [pscustomobject]@{ Profile=[string]$_.Name; Enabled=[bool]$_.Enabled; DefaultInboundAction=[string]$_.DefaultInboundAction; DefaultOutboundAction=[string]$_.DefaultOutboundAction } })
            } else { Add-Fact 'firewall' $null 'EffectiveConfiguration' 'RuntimeConfiguration' 'Partial' 'None' $Profiles }
        } catch { $State=if ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -or $_.Exception -is [System.NotSupportedException]) { 'NotSupported' } else { 'Failed' }; Add-Fact 'firewall' $null 'EffectiveConfiguration' 'RuntimeConfiguration' $State 'None' $null $_.Exception.GetType().Name }
        try {
            $D=Get-MpComputerStatus -ErrorAction Stop
            $State=if (-not $D.AMServiceEnabled -or -not $D.AntivirusEnabled) { 'Disabled' } elseif ($D.RealTimeProtectionEnabled -and $D.BehaviorMonitorEnabled) { 'Healthy' } else { 'Degraded' }
            Add-Fact 'defender' $State 'ProductHealth' 'ProductRuntime' 'Collected' 'High' ([pscustomobject]@{ AMServiceEnabled=[bool]$D.AMServiceEnabled; AntivirusEnabled=[bool]$D.AntivirusEnabled; RealTimeProtectionEnabled=[bool]$D.RealTimeProtectionEnabled; BehaviorMonitorEnabled=[bool]$D.BehaviorMonitorEnabled; AntivirusSignatureLastUpdated=$D.AntivirusSignatureLastUpdated; AntivirusSignatureVersion=[string]$D.AntivirusSignatureVersion })
        } catch { $State=if ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -or $_.Exception -is [System.NotSupportedException]) { 'NotSupported' } else { 'Failed' }; Add-Fact 'defender' $null 'ProductHealth' 'ProductRuntime' $State 'None' $null $_.Exception.GetType().Name }
        try {
            $G=Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
            $Running=1 -in @($G.SecurityServicesRunning); $Configured=1 -in @($G.SecurityServicesConfigured)
            Add-Fact 'credential-guard' $(if ($Running) { 'Enabled' } else { 'Disabled' }) 'EffectiveConfiguration' 'CIM' 'Collected' 'High' ([pscustomobject]@{ Configured=$Configured; Running=$Running })
        } catch { $State=if ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -or $_.Exception -is [System.NotSupportedException]) { 'NotSupported' } else { 'Failed' }; Add-Fact 'credential-guard' $null 'EffectiveConfiguration' 'CIM' $State 'None' $null $_.Exception.GetType().Name }
        $Lsa=Get-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
        if ($Lsa.State -eq 'Collected') { Add-Fact 'lsass-protection' $Lsa.Value 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Configured=$Lsa.Value; Running=$null }) }
        $W=Get-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential'
        if ($W.State -eq 'Collected') { Add-Fact 'wdigest' $(if ($W.Value -eq 1) { 'Enabled' } else { 'Disabled' }) 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Configured=$W.Value; Effective=$null }) }
        foreach ($Protocol in @('TLS 1.0','TLS 1.1','TLS 1.2')) {
            foreach ($Side in @('Client','Server')) {
                $Path="HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$Protocol\$Side"
                $Enabled=Get-Dword $Path 'Enabled'; $Default=Get-Dword $Path 'DisabledByDefault'
                $Rule=($Protocol -replace '[^0-9]','').ToLowerInvariant()
                if ($Enabled.State -eq 'Collected' -or $Default.State -eq 'Collected') {
                    Add-Fact "tls$Rule-$($Side.ToLowerInvariant())" $Enabled.Value 'RegistryConfiguration' 'RegistryRuntime' 'Partial' 'Medium' ([pscustomobject]@{ Enabled=$Enabled.Value; DisabledByDefault=$Default.Value; Side=$Side; Protocol=$Protocol })
                }
            }
        }
        try {
            $Policy=@(& auditpol /get /category:* /r 2>&1)
            if ($LASTEXITCODE -ne 0) { throw 'auditpol returned a nonzero exit code' }
            $Rows=@($Policy | ConvertFrom-Csv)
            if ($Rows.Count) { Add-Fact 'audit-policy' $null 'EffectiveAuditPolicy' 'AuditPolicy' 'Partial' 'High' $Rows }
        } catch { Add-Fact 'audit-policy' $null 'EffectiveAuditPolicy' 'AuditPolicy' 'Failed' 'None' $null $_.Exception.GetType().Name }
        try {
            $Log=Get-WinEvent -ListLog Security -ErrorAction Stop
            Add-Fact 'event-retention' ([math]::Round([double]$Log.MaximumSizeInBytes / 1MB,1)) 'EventLogConfiguration' 'EventLog' 'Collected' 'High' ([pscustomobject]@{ Log='Security'; MaximumSizeInBytes=$Log.MaximumSizeInBytes; LogMode=[string]$Log.LogMode; IsEnabled=[bool]$Log.IsEnabled })
        } catch { Add-Fact 'event-retention' $null 'EventLogConfiguration' 'EventLog' 'Failed' 'None' $null $_.Exception.GetType().Name }
        try {
            $Store=New-Object System.Security.Cryptography.X509Certificates.X509Store('My','LocalMachine'); $Store.Open('ReadOnly')
            try { $Certs=@($Store.Certificates | Where-Object { $_.HasPrivateKey } | ForEach-Object { [pscustomobject]@{ Thumbprint=$_.Thumbprint; Subject=$_.Subject; Issuer=$_.Issuer; NotBefore=$_.NotBefore; NotAfter=$_.NotAfter; HasPrivateKey=[bool]$_.HasPrivateKey; DnsNameList=@($_.DnsNameList | ForEach-Object { [string]$_ }); EnhancedKeyUsageList=@($_.EnhancedKeyUsageList | ForEach-Object { [string]$_ }) } }) }
            finally { $Store.Close() }
            Add-Fact 'ldaps-capability' $null 'CertificateInspection' 'CertificateStore' 'Partial' 'Medium' $Certs
        } catch { Add-Fact 'ldaps-capability' $null 'CertificateInspection' 'CertificateStore' 'Failed' 'None' $null $_.Exception.GetType().Name }
        # A successful bounded query proves only that the configured log was read. No event means no observation in that window.
        try {
            $Items=@(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624,4776,4769; StartTime=$Now.AddHours(-$Hours)} -MaxEvents 300 -ErrorAction Stop)
            foreach ($E in $Items) {
                [xml]$Xml=$E.ToXml(); $Map=@{}; foreach ($Node in @($Xml.Event.EventData.Data)) { $Map[[string]$Node.Name]=[string]$Node.'#text' }
                if ($E.Id -eq 4624 -and $Map.AuthenticationPackageName -eq 'NTLM') {
                    $Version=if ($Map.LmPackageName -match 'NTLM\s*V1|^LM$') { 'NTLMv1' } elseif ($Map.LmPackageName -match 'NTLM\s*V2') { 'NTLMv2' } else { 'Unknown' }
                    $Telemetry.Add([pscustomobject]@{ Kind='NTLM'; Version=$Version; DC=$env:COMPUTERNAME; Timestamp=$E.TimeCreated; Account=$Map.TargetUserName; Client=$Map.WorkstationName; Service=$null; SourceEvent=4624; CollectionWindowHours=$Hours })
                } elseif ($E.Id -eq 4776) {
                    $Telemetry.Add([pscustomobject]@{ Kind='NTLM'; Version='Unknown'; DC=$env:COMPUTERNAME; Timestamp=$E.TimeCreated; Account=$Map.TargetUserName; Client=$Map.Workstation; Service=$null; SourceEvent=4776; CollectionWindowHours=$Hours })
                } elseif ($E.Id -eq 4769) {
                    $Type=([string]$Map.TicketEncryptionType).ToLowerInvariant()
                    $Version=switch ($Type) { '0x11' { 'AES128' }; '0x12' { 'AES256' }; '0x17' { 'RC4' }; '0x18' { 'RC4' }; default { 'Unknown' } }
                    $Telemetry.Add([pscustomobject]@{ Kind='Kerberos'; Version=$Version; DC=$env:COMPUTERNAME; Timestamp=$E.TimeCreated; Account=$Map.TargetUserName; Client=$Map.IpAddress; Service=$Map.ServiceName; SourceEvent=4769; CollectionWindowHours=$Hours })
                }
            }
            Add-Fact 'authentication-events' $Items.Count 'EventQuery' 'EventLog' 'Collected' 'High' $null
        } catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { Add-Fact 'authentication-events' 0 'EventQuery' 'EventLog' 'Collected' 'High' $null }
            else { Add-Fact 'authentication-events' $null 'EventQuery' 'EventLog' 'Failed' 'None' $null $_.Exception.GetType().Name }
        }
        [pscustomobject]@{ Facts=$Facts.ToArray(); Telemetry=$Telemetry.ToArray(); QueryWindowHours=$Hours; CollectionMethod='One read-only PowerShell remoting invocation' }
    }
}

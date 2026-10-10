Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

function Get-PSIADWorkbookEntryXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchive] $Archive,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $EntryName
    )

    $Entry = $Archive.GetEntry($EntryName)
    if ($null -eq $Entry) {
        throw "The Excel workbook is missing required package entry '$EntryName'."
    }

    $Settings = [System.Xml.XmlReaderSettings]::new()
    $Settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $Settings.XmlResolver = $null
    $Stream = $Entry.Open()
    $Reader = $null
    try {
        $Reader = [System.Xml.XmlReader]::Create($Stream, $Settings)
        $Document = [System.Xml.XmlDocument]::new()
        $Document.XmlResolver = $null
        $Document.Load($Reader)
        return ,$Document
    }
    finally {
        if ($null -ne $Reader) { $Reader.Dispose() }
        $Stream.Dispose()
    }
}

function Get-PSIExcelColumnIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $CellReference
    )

    $Letters = [regex]::Match($CellReference, '^[A-Za-z]+').Value.ToUpperInvariant()
    if ([string]::IsNullOrEmpty($Letters)) {
        throw "Invalid Excel cell reference '$CellReference'."
    }

    $Index = 0
    foreach ($Character in $Letters.ToCharArray()) {
        $Index = ($Index * 26) + ([int] $Character - [int] [char] 'A' + 1)
    }

    $Index - 1
}

function ConvertFrom-PSIExcelCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement] $Cell,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $SharedStrings = @(),

        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNamespaceManager] $NamespaceManager
    )

    $CellType = $Cell.GetAttribute('t')
    $ValueNode = $Cell.SelectSingleNode('./m:v', $NamespaceManager)

    if ($CellType -eq 'inlineStr') {
        $TextNodes = $Cell.SelectNodes('.//m:t', $NamespaceManager)
        $Text = [System.Text.StringBuilder]::new()
        foreach ($TextNode in $TextNodes) { [void] $Text.Append($TextNode.InnerText) }
        return $Text.ToString()
    }
    if ($null -eq $ValueNode) { return $null }

    $RawValue = $ValueNode.InnerText
    switch ($CellType) {
        's' {
            $SharedIndex = [int] $RawValue
            if ($SharedIndex -lt 0 -or $SharedIndex -ge $SharedStrings.Count) {
                throw "Workbook shared-string index '$SharedIndex' is out of range."
            }
            return $SharedStrings[$SharedIndex]
        }
        'b' { return ($RawValue -eq '1') }
        'n' {
            $Number = [double]::Parse($RawValue, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($Number -eq [math]::Truncate($Number)) { return [long] $Number }
            return $Number
        }
        default { return $RawValue }
    }
}

function Import-PSIADUserInventoryWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $WorksheetName = 'AD_User_Accounts'
    )

    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $ResolvedPath -PathType Leaf)) {
        throw "Excel workbook not found: $Path"
    }

    try {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($ResolvedPath)
    }
    catch {
        throw "Could not open '$Path' as an .xlsx workbook. $($_.Exception.Message)"
    }

    try {
        $Workbook = Get-PSIADWorkbookEntryXml -Archive $Archive -EntryName 'xl/workbook.xml'
        $Relationships = Get-PSIADWorkbookEntryXml -Archive $Archive -EntryName 'xl/_rels/workbook.xml.rels'
        $WorkbookNamespace = $Workbook.DocumentElement.NamespaceURI
        $RelationshipNamespace = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
        $PackageRelationshipNamespace = 'http://schemas.openxmlformats.org/package/2006/relationships'

        $WorkbookManager = [System.Xml.XmlNamespaceManager]::new($Workbook.NameTable)
        $WorkbookManager.AddNamespace('m', $WorkbookNamespace)
        $WorkbookManager.AddNamespace('r', $RelationshipNamespace)
        $RelationshipManager = [System.Xml.XmlNamespaceManager]::new($Relationships.NameTable)
        $RelationshipManager.AddNamespace('p', $PackageRelationshipNamespace)

        $RelationshipTargets = @{}
        foreach ($Relationship in $Relationships.SelectNodes('/p:Relationships/p:Relationship', $RelationshipManager)) {
            $RelationshipTargets[$Relationship.GetAttribute('Id')] = $Relationship.GetAttribute('Target')
        }

        $WorksheetPath = $null
        foreach ($Worksheet in $Workbook.SelectNodes('/m:workbook/m:sheets/m:sheet', $WorkbookManager)) {
            if ([string]::Equals($Worksheet.GetAttribute('name'), $WorksheetName, [System.StringComparison]::Ordinal)) {
                $RelationshipId = $Worksheet.GetAttribute('id', $RelationshipNamespace)
                if (-not $RelationshipTargets.ContainsKey($RelationshipId)) {
                    throw "No package relationship was found for worksheet '$WorksheetName'."
                }
                $Target = ([string] $RelationshipTargets[$RelationshipId]).Replace('\', '/')
                if ($Target.StartsWith('/')) { $WorksheetPath = $Target.TrimStart('/') }
                elseif ($Target.StartsWith('xl/')) { $WorksheetPath = $Target }
                else { $WorksheetPath = 'xl/' + $Target }
                break
            }
        }
        if ([string]::IsNullOrEmpty($WorksheetPath)) {
            throw "Worksheet '$WorksheetName' was not found in '$Path'."
        }

        $SharedStrings = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $Archive.GetEntry('xl/sharedStrings.xml')) {
            $SharedStringDocument = Get-PSIADWorkbookEntryXml -Archive $Archive -EntryName 'xl/sharedStrings.xml'
            $SharedStringManager = [System.Xml.XmlNamespaceManager]::new($SharedStringDocument.NameTable)
            $SharedStringManager.AddNamespace('m', $SharedStringDocument.DocumentElement.NamespaceURI)
            foreach ($SharedString in $SharedStringDocument.SelectNodes('/m:sst/m:si', $SharedStringManager)) {
                $Text = [System.Text.StringBuilder]::new()
                foreach ($TextNode in $SharedString.SelectNodes('.//m:t', $SharedStringManager)) {
                    [void] $Text.Append($TextNode.InnerText)
                }
                $SharedStrings.Add($Text.ToString())
            }
        }

        $WorksheetDocument = Get-PSIADWorkbookEntryXml -Archive $Archive -EntryName $WorksheetPath
        $WorksheetManager = [System.Xml.XmlNamespaceManager]::new($WorksheetDocument.NameTable)
        $WorksheetManager.AddNamespace('m', $WorksheetDocument.DocumentElement.NamespaceURI)
        $Rows = $WorksheetDocument.SelectNodes('/m:worksheet/m:sheetData/m:row', $WorksheetManager)
        if ($Rows.Count -lt 2) {
            throw "Worksheet '$WorksheetName' does not contain a header and data rows."
        }

        $HeaderCells = @{}
        $HeaderRow = $Rows[0]
        $HeaderMaximum = -1
        foreach ($Cell in $HeaderRow.SelectNodes('./m:c', $WorksheetManager)) {
            $ColumnIndex = Get-PSIExcelColumnIndex -CellReference $Cell.GetAttribute('r')
            $HeaderText = [string] (ConvertFrom-PSIExcelCell -Cell $Cell -SharedStrings $SharedStrings.ToArray() -NamespaceManager $WorksheetManager)
            if ([string]::IsNullOrWhiteSpace($HeaderText)) { continue }
            if ($HeaderCells.ContainsValue($HeaderText)) { throw "Worksheet '$WorksheetName' contains duplicate column name '$HeaderText'." }
            $HeaderCells[$ColumnIndex] = $HeaderText.Trim()
            $HeaderMaximum = [math]::Max($HeaderMaximum, $ColumnIndex)
        }
        if ($HeaderCells.Count -eq 0) { throw "Worksheet '$WorksheetName' does not contain column headers." }

        $Records = [System.Collections.Generic.List[object]]::new()
        for ($RowIndex = 1; $RowIndex -lt $Rows.Count; $RowIndex++) {
            $Row = $Rows[$RowIndex]
            $Values = @{}
            foreach ($Cell in $Row.SelectNodes('./m:c', $WorksheetManager)) {
                $ColumnIndex = Get-PSIExcelColumnIndex -CellReference $Cell.GetAttribute('r')
                if (-not $HeaderCells.ContainsKey($ColumnIndex)) { continue }
                $Values[$HeaderCells[$ColumnIndex]] = ConvertFrom-PSIExcelCell -Cell $Cell -SharedStrings $SharedStrings.ToArray() -NamespaceManager $WorksheetManager
            }

            $HasValues = $false
            foreach ($ColumnName in $HeaderCells.Values) {
                if ($null -ne $Values[$ColumnName] -and -not [string]::IsNullOrWhiteSpace([string] $Values[$ColumnName])) {
                    $HasValues = $true
                    break
                }
            }
            if (-not $HasValues) { continue }

            $Record = [ordered]@{}
            for ($ColumnIndex = 0; $ColumnIndex -le $HeaderMaximum; $ColumnIndex++) {
                if ($HeaderCells.ContainsKey($ColumnIndex)) {
                    $ColumnName = $HeaderCells[$ColumnIndex]
                    $Record[$ColumnName] = $Values[$ColumnName]
                }
            }
            $Records.Add([pscustomobject] $Record)
        }

        return $Records.ToArray()
    }
    finally {
        $Archive.Dispose()
    }
}

function ConvertTo-PSIADInventoryDate {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $Text = ([string] $Value).Trim()
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::Equals($Text, 'Never', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $ParsedDate = [datetime]::MinValue
    $Formats = [string[]] @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd')
    $Parsed = [datetime]::TryParseExact(
        $Text,
        $Formats,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $ParsedDate
    )
    if (-not $Parsed) {
        throw "The date value '$Text' is not in a supported ISO format (yyyy-MM-dd or yyyy-MM-dd HH:mm:ss)."
    }
    $ParsedDate
}

function Get-PSIADUserInventoryMedian {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [double[]] $Values = @()
    )

    if ($Values.Count -eq 0) { return $null }
    $SortedValues = @($Values | Sort-Object)
    $Middle = [int] [math]::Floor($SortedValues.Count / 2)
    if ($SortedValues.Count % 2 -eq 1) { return [double] $SortedValues[$Middle] }
    ([double] $SortedValues[$Middle - 1] + [double] $SortedValues[$Middle]) / 2
}

function Get-PSIADUserInventoryAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter()]
        [datetime] $AsOfDate = (Get-Date),

        [Parameter()]
        [System.Collections.IDictionary] $Thresholds = @{}
    )

    $AllowedThresholds = @('PasswordAgeWarningDays', 'InactiveUserWarningDays', 'AccountExpiryWarningDays')
    $ConfiguredThresholds = [ordered]@{
        PasswordAgeWarningDays = $null
        InactiveUserWarningDays = $null
        AccountExpiryWarningDays = $null
    }
    foreach ($ThresholdName in $Thresholds.Keys) {
        if ($ThresholdName -notin $AllowedThresholds) {
            throw "Unsupported report threshold '$ThresholdName'. Supported thresholds: $($AllowedThresholds -join ', ')."
        }
        if ($null -eq $Thresholds[$ThresholdName] -or [string]::IsNullOrWhiteSpace([string] $Thresholds[$ThresholdName])) {
            continue
        }
        $ThresholdValue = 0
        if (-not [int]::TryParse([string] $Thresholds[$ThresholdName], [ref] $ThresholdValue) -or $ThresholdValue -lt 1) {
            throw "Threshold '$ThresholdName' must be an explicitly configured positive whole number of days."
        }
        $ConfiguredThresholds[$ThresholdName] = $ThresholdValue
    }

    $AsOf = $AsOfDate.Date
    $NormalizedRecords = [System.Collections.Generic.List[object]]::new()
    $PasswordAges = [System.Collections.Generic.List[double]]::new()
    $LastLogonAges = [System.Collections.Generic.List[double]]::new()
    $ExpirationStates = @{ Never = 0; Expired = 0; Today = 0; Future = 0; Missing = 0 }
    $FuturePasswordDates = 0
    $FutureLastLogonDates = 0
    $PolicyFindings = [System.Collections.Generic.List[object]]::new()
    $AccountStatusCounts = @{}

    foreach ($SourceRecord in $Data) {
        $PasswordLastSet = ConvertTo-PSIADInventoryDate -Value $SourceRecord.pwdLastSet
        $LastLogon = ConvertTo-PSIADInventoryDate -Value $SourceRecord.lastLogonTimestamp
        $AccountExpiresNever = [string]::Equals(([string] $SourceRecord.accountExpires).Trim(), 'Never', [System.StringComparison]::OrdinalIgnoreCase)
        $AccountExpires = ConvertTo-PSIADInventoryDate -Value $SourceRecord.accountExpires
        $PasswordAgeDays = $null
        $LastLogonAgeDays = $null
        $DaysToExpiration = $null

        if ($null -ne $PasswordLastSet) {
            $PasswordAgeDays = [int] [math]::Floor(($AsOf - $PasswordLastSet).TotalDays)
            if ($PasswordAgeDays -ge 0) { $PasswordAges.Add([double] $PasswordAgeDays) }
            else { $FuturePasswordDates++ }
        }
        if ($null -ne $LastLogon) {
            $LastLogonAgeDays = [int] [math]::Floor(($AsOf - $LastLogon).TotalDays)
            if ($LastLogonAgeDays -ge 0) { $LastLogonAges.Add([double] $LastLogonAgeDays) }
            else { $FutureLastLogonDates++ }
        }

        if ($AccountExpiresNever) {
            $ExpirationStates.Never++
            $ExpirationState = 'Never'
        }
        elseif ($null -eq $AccountExpires) {
            $ExpirationStates.Missing++
            $ExpirationState = 'Not provided'
        }
        else {
            $DaysToExpiration = [int] [math]::Floor(($AccountExpires.Date - $AsOf).TotalDays)
            if ($DaysToExpiration -lt 0) {
                $ExpirationStates.Expired++
                $ExpirationState = 'Expired'
            }
            elseif ($DaysToExpiration -eq 0) {
                $ExpirationStates.Today++
                $ExpirationState = 'Expires today'
            }
            else {
                $ExpirationStates.Future++
                $ExpirationState = 'Future'
            }
        }

        $AccountStatus = ([string] $SourceRecord.accountStatus).Trim()
        if (-not $AccountStatusCounts.ContainsKey($AccountStatus)) { $AccountStatusCounts[$AccountStatus] = 0 }
        $AccountStatusCounts[$AccountStatus]++

        $CloudSyncStatus = [string] $SourceRecord.'extensionAttribute3 (CloudSyncStatus)'
        if ([string]::IsNullOrWhiteSpace($CloudSyncStatus)) { $CloudSyncStatus = 'Not supplied' }
        $Country = [string] $SourceRecord.co
        if ([string]::IsNullOrWhiteSpace($Country)) { $Country = 'Not supplied' }
        $Department = [string] $SourceRecord.department
        if ([string]::IsNullOrWhiteSpace($Department)) { $Department = 'Not supplied' }
        $EmployeeType = [string] $SourceRecord.employeeType
        if ([string]::IsNullOrWhiteSpace($EmployeeType)) { $EmployeeType = 'Not supplied' }
        $Office = [string] $SourceRecord.physicalDeliveryOfficeName
        if ([string]::IsNullOrWhiteSpace($Office)) { $Office = 'Not supplied' }

        # Microsoft documents ADS_UF_DONT_EXPIRE_PASSWD as the 0x00010000 flag.
        # Keep the raw UAC value out of report output and expose only this derived boolean.
        $PasswordNeverExpires = $null
        if ($null -ne $SourceRecord.userAccountControl) {
            $PasswordNeverExpires = (([long] $SourceRecord.userAccountControl -band 0x00010000) -ne 0)
        }

        $NormalizedRecords.Add([pscustomobject]@{
            DisplayName             = [string] $SourceRecord.displayName
            UserPrincipalName       = [string] $SourceRecord.userPrincipalName
            AccountStatus           = $AccountStatus
            EmployeeType            = $EmployeeType
            Department              = $Department
            Office                  = $Office
            Country                 = $Country
            CloudSyncStatus         = $CloudSyncStatus
            PasswordLastSet         = $PasswordLastSet
            PasswordLastSetDisplay  = if ($null -ne $PasswordLastSet) { $PasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
            PasswordAgeDays         = $PasswordAgeDays
            PasswordNeverExpires    = $PasswordNeverExpires
            LastLogon               = $LastLogon
            LastLogonDisplay        = if ($null -ne $LastLogon) { $LastLogon.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
            LastLogonAgeDays        = $LastLogonAgeDays
            AccountExpires          = $AccountExpires
            AccountExpiresNever     = $AccountExpiresNever
            AccountExpiresDisplay   = if ($AccountExpiresNever) { 'Never' } elseif ($null -ne $AccountExpires) { $AccountExpires.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
            DaysToExpiration        = $DaysToExpiration
            ExpirationState         = $ExpirationState
        })

        if ($null -ne $PasswordAgeDays -and $null -ne $ConfiguredThresholds.PasswordAgeWarningDays -and
            $PasswordAgeDays -ge $ConfiguredThresholds.PasswordAgeWarningDays) {
            $PolicyFindings.Add([pscustomobject]@{
                DisplayName       = [string] $SourceRecord.displayName
                UserPrincipalName = [string] $SourceRecord.userPrincipalName
                AccountStatus     = $AccountStatus
                Department        = $Department
                Finding           = 'Password age threshold met'
                ObservedDays      = $PasswordAgeDays
                ThresholdDays     = $ConfiguredThresholds.PasswordAgeWarningDays
            })
        }
        if ($null -ne $LastLogonAgeDays -and $null -ne $ConfiguredThresholds.InactiveUserWarningDays -and
            $LastLogonAgeDays -ge $ConfiguredThresholds.InactiveUserWarningDays) {
            $PolicyFindings.Add([pscustomobject]@{
                DisplayName       = [string] $SourceRecord.displayName
                UserPrincipalName = [string] $SourceRecord.userPrincipalName
                AccountStatus     = $AccountStatus
                Department        = $Department
                Finding           = 'Last-logon inactivity threshold met'
                ObservedDays      = $LastLogonAgeDays
                ThresholdDays     = $ConfiguredThresholds.InactiveUserWarningDays
            })
        }
        if ($null -ne $DaysToExpiration -and $DaysToExpiration -ge 0 -and
            $null -ne $ConfiguredThresholds.AccountExpiryWarningDays -and
            $DaysToExpiration -le $ConfiguredThresholds.AccountExpiryWarningDays) {
            $PolicyFindings.Add([pscustomobject]@{
                DisplayName       = [string] $SourceRecord.displayName
                UserPrincipalName = [string] $SourceRecord.userPrincipalName
                AccountStatus     = $AccountStatus
                Department        = $Department
                Finding           = 'Account expiration threshold met'
                ObservedDays      = $DaysToExpiration
                ThresholdDays     = $ConfiguredThresholds.AccountExpiryWarningDays
            })
        }
    }

    [pscustomobject]@{
        AsOfDate                    = $AsOf
        Records                     = [object[]] $NormalizedRecords.ToArray()
        UserCount                   = $NormalizedRecords.Count
        EnabledCount                = [int] $(if ($AccountStatusCounts.ContainsKey('Enabled')) { $AccountStatusCounts['Enabled'] } else { 0 })
        DisabledCount               = [int] $(if ($AccountStatusCounts.ContainsKey('Disabled')) { $AccountStatusCounts['Disabled'] } else { 0 })
        AccountStatusCounts         = $AccountStatusCounts
        PasswordDateCount           = $PasswordAges.Count
        PasswordAgeMedianDays       = Get-PSIADUserInventoryMedian -Values $PasswordAges.ToArray()
        PasswordAgeMaximumDays      = if ($PasswordAges.Count -gt 0) { ($PasswordAges | Measure-Object -Maximum).Maximum } else { $null }
        FuturePasswordDateCount     = $FuturePasswordDates
        LastLogonDateCount          = $LastLogonAges.Count
        LastLogonAgeMedianDays      = Get-PSIADUserInventoryMedian -Values $LastLogonAges.ToArray()
        LastLogonAgeMaximumDays     = if ($LastLogonAges.Count -gt 0) { ($LastLogonAges | Measure-Object -Maximum).Maximum } else { $null }
        FutureLastLogonDateCount    = $FutureLastLogonDates
        ExpirationStates            = $ExpirationStates
        Thresholds                  = $ConfiguredThresholds
        Findings                    = [object[]] $PolicyFindings.ToArray()
    }
}

function New-PSIADUserInventoryInsightDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Analysis,

        [Parameter()]
        [System.Collections.IDictionary] $Thresholds = @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 }
    )

    $ConfiguredThresholds = [ordered]@{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 }
    foreach ($Name in $Thresholds.Keys) {
        if ($Name -notin @($ConfiguredThresholds.Keys)) {
            throw "Unsupported insight threshold '$Name'. Supported thresholds: $(@($ConfiguredThresholds.Keys) -join ', ')."
        }
        $ParsedValue = 0
        if (-not [int]::TryParse([string] $Thresholds[$Name], [ref] $ParsedValue) -or $ParsedValue -lt 1) {
            throw "Insight threshold '$Name' must be configured as a positive whole number of days."
        }
        $ConfiguredThresholds[$Name] = $ParsedValue
    }
    $Thresholds = $ConfiguredThresholds
    if ([int] $Thresholds.Stale180Days -lt [int] $Thresholds.Stale90Days) {
        throw 'Stale180Days must be greater than or equal to Stale90Days.'
    }

    $All = @($Analysis.Records)
    $ExpiredEnabled = @($All | Where-Object { $_.AccountStatus -eq 'Enabled' -and $_.ExpirationState -eq 'Expired' })
    $Stale90 = @($All | Where-Object { $null -ne $_.LastLogonAgeDays -and $_.LastLogonAgeDays -ge [int] $Thresholds.Stale90Days })
    $Stale180 = @($All | Where-Object { $null -ne $_.LastLogonAgeDays -and $_.LastLogonAgeDays -ge [int] $Thresholds.Stale180Days })
    $OldPasswords = @($All | Where-Object { $_.PasswordNeverExpires -eq $false -and $null -ne $_.PasswordAgeDays -and $_.PasswordAgeDays -ge [int] $Thresholds.PasswordAgeDays })
    $NeverExpiresPasswords = @($All | Where-Object { $_.PasswordNeverExpires -eq $true })
    $NeverLoggedOn = @($All | Where-Object { $null -eq $_.LastLogon })
    $CloudMissing = @($All | Where-Object { [string]::Equals($_.CloudSyncStatus, 'Not supplied', [System.StringComparison]::OrdinalIgnoreCase) })

    @(
        [pscustomobject]@{ Title = 'All Users'; Value = $Analysis.UserCount; Description = 'Open the complete reviewed inventory evidence.'; Status = 'Info'; Icon = 'users'; Conditions = @() }
        [pscustomobject]@{ Title = "Stale $([char] 0x2265) $($Thresholds.Stale90Days) Days"; Value = $Stale90.Count; Description = 'Based on lastLogonTimestamp; threshold is report-configured. This is a count, not a policy finding.'; Status = 'Info'; Icon = 'info'; Conditions = @([pscustomobject]@{ Property = 'LastLogonAgeDays'; Operator = 'GreaterThanOrEqual'; Value = [int] $Thresholds.Stale90Days }) }
        [pscustomobject]@{ Title = "Stale $([char] 0x2265) $($Thresholds.Stale180Days) Days"; Value = $Stale180.Count; Description = 'Based on lastLogonTimestamp; threshold is report-configured. This is a count, not a policy finding.'; Status = 'Info'; Icon = 'info'; Conditions = @([pscustomobject]@{ Property = 'LastLogonAgeDays'; Operator = 'GreaterThanOrEqual'; Value = [int] $Thresholds.Stale180Days }) }
        [pscustomobject]@{ Title = 'Enabled + Expired'; Value = $ExpiredEnabled.Count; Description = 'Enabled accounts whose expiration date is before the report date; no policy severity is inferred.'; Status = 'Info'; Icon = 'security'; Conditions = @([pscustomobject]@{ Property = 'AccountStatus'; Operator = 'Equals'; Value = 'Enabled' }, [pscustomobject]@{ Property = 'ExpirationState'; Operator = 'Equals'; Value = 'Expired' }) }
        [pscustomobject]@{ Title = "Password $([char] 0x2265) $($Thresholds.PasswordAgeDays) Days"; Value = $OldPasswords.Count; Description = 'Based on pwdLastSet; accounts marked password-never-expires are excluded.'; Status = 'Info'; Icon = 'security'; Conditions = @([pscustomobject]@{ Property = 'PasswordNeverExpires'; Operator = 'Equals'; Value = $false }, [pscustomobject]@{ Property = 'PasswordAgeDays'; Operator = 'GreaterThanOrEqual'; Value = [int] $Thresholds.PasswordAgeDays }) }
        [pscustomobject]@{ Title = 'Password Never Expires'; Value = $NeverExpiresPasswords.Count; Description = 'Derived from the documented DONT_EXPIRE_PASSWD userAccountControl flag.'; Status = 'Info'; Icon = 'security'; Conditions = @([pscustomobject]@{ Property = 'PasswordNeverExpires'; Operator = 'Equals'; Value = $true }) }
        [pscustomobject]@{ Title = 'Never Logged On'; Value = $NeverLoggedOn.Count; Description = 'No lastLogonTimestamp value was supplied.'; Status = 'Info'; Icon = 'users'; Conditions = @([pscustomobject]@{ Property = 'LastLogonAgeDays'; Operator = 'IsEmpty' }) }
        [pscustomobject]@{ Title = 'Cloud Sync Missing'; Value = $CloudMissing.Count; Description = 'CloudSyncStatus was blank in the source inventory; shown as a data-profile count.'; Status = 'Info'; Icon = 'cloud'; Conditions = @([pscustomobject]@{ Property = 'CloudSyncStatus'; Operator = 'Equals'; Value = 'Not supplied' }) }
    )
}

function Get-PSIADUserInventoryEmptyFieldProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data
    )

    if ($Data.Count -eq 0) { return @() }
    $Columns = @($Data[0].PSObject.Properties | ForEach-Object { $_.Name })
    $Profile = [System.Collections.Generic.List[object]]::new()
    foreach ($Column in $Columns) {
        $EmptyCount = 0
        $UniqueValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in $Data) {
            $Value = $Record.PSObject.Properties[$Column].Value
            if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { $EmptyCount++ }
            else { [void] $UniqueValues.Add([string] $Value) }
        }
        if ($EmptyCount -gt 0) {
            $Profile.Add([pscustomobject]@{
                Field             = $Column
                EmptyCount        = $EmptyCount
                EmptyPercent      = [math]::Round(($EmptyCount / [double] $Data.Count) * 100, 1)
                UniqueNonEmpty    = $UniqueValues.Count
            })
        }
    }
    $Profile.ToArray()
}

function New-PSIADUserInventoryDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property
    )

    @(
        $Data |
            Group-Object -Property $Property |
            Sort-Object -Property Name |
            ForEach-Object {
                [pscustomobject]@{
                    Category = [string] $_.Name
                    Count    = [int] $_.Count
                }
            }
    )
}

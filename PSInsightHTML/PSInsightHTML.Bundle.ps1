# PSInsightHTML generated bundle - DO NOT EDIT. Regenerate with Build/Build-PSInsightHTML.ps1.
# Fingerprint: 9C1C49E5838EF82E85AEB9878FA5B9C4D1E05AB16CC5581029C5E4779A83C88B
# Sources: 98

#region Private/Add-PSIComponentToLastRow.ps1
function Add-PSIComponentToLastRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable] $Properties
    )

    $LastRow = Get-PSILastRow -Report $Report
    $ComponentsProperty = $LastRow.PSObject.Properties['Components']
    if ($null -eq $ComponentsProperty -or $ComponentsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The latest row does not contain a valid Components collection.'
    }

    $Component = New-PSIComponent -Type $Type -Properties $Properties
    $ComponentsProperty.Value.Add($Component)
    $Report
}
#endregion

#region Private/Add-PSIRelationshipComponent.ps1
function Add-PSIRelationshipComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidateSet('Tree','Topology','RelationshipExplorer')][string] $Type,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [string[]] $FilterProperties = @(),
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' },
        [int] $MaxNodes = 100
    )
    if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
        (Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()).Count -eq 0) {
        throw "$Type requires an application view. Add a view first."
    }
    $Model = Get-PSIProperty -InputObject $Report -Name 'ApplicationModel' -DefaultValue $null
    if ($null -eq $Model) { throw "$Type requires Set-PSIApplicationModel first." }
    foreach ($Kind in @('Resource','Finding','Evidence')) {
        if ([string] $LinkViews[$Kind] -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Type LinkViews requires a valid $Kind view ID." }
    }
    foreach ($Property in $FilterProperties) {
        if ($Property -notin $DetailProperties -or $Property -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw "$Type FilterProperties must be valid DetailProperties." }
    }
    $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties
    $Row = Get-PSILastRow -Report $Report
    $Row.Components.Add((New-PSIComponent -Type $Type -Properties @{
        Id=$Id; Title=$Title; Presentation=$Presentation; LinkViews=$LinkViews; MaxNodes=$MaxNodes; FilterProperties=@($FilterProperties)
    }))
    $Report
}
#endregion

#region Private/Assert-PSIApplicationAssessment.ps1
function Assert-PSIApplicationAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter()][AllowNull()][pscustomobject] $Model = $null
    )
    foreach ($Field in @('Id','Name','AssessmentType','Target','Profile')) {
        if ([string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Assessment -Name $Field))) { throw "Assessment requires a non-empty $Field." }
    }
    if ([string] $Assessment.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'Assessment Id is invalid.' }
    if ($Assessment.GeneratedAt -isnot [datetime]) { throw 'Assessment GeneratedAt must be a DateTime.' }
    if ([double] $Assessment.Thresholds.Review -lt 0 -or [double] $Assessment.Thresholds.Ready -gt 100 -or
        [double] $Assessment.Thresholds.Review -gt [double] $Assessment.Thresholds.Ready) { throw 'Assessment score thresholds are invalid.' }
    $Ids = @{}
    foreach ($Kind in @('Categories','Checks','Exceptions')) {
        $Ids[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in @($Assessment.$Kind)) {
            if ($null -eq $Record) { throw "$Kind cannot contain a null record." }
            $Definition = @{}
            foreach ($Property in $Record.PSObject.Properties) { $Definition[$Property.Name] = $Property.Value }
            if ($Kind -eq 'Categories') { $Definition.Remove('Score'); $Definition.Remove('Status') }
            $ContractKind = switch ($Kind) { Categories { 'Category' } Checks { 'Check' } Exceptions { 'Exception' } }
            [void] (New-PSIAssessmentContractObject -Kind $ContractKind -Definition $Definition)
            if (-not $Ids[$Kind].Add([string] $Record.Id)) { throw "$Kind contains duplicate Id '$($Record.Id)'." }
        }
    }
    if ($Assessment.Categories.Count -eq 0 -or $Assessment.Checks.Count -eq 0) { throw 'Assessment requires at least one category and one check.' }
    $CategoryMembership = @{}
    foreach ($Category in $Assessment.Categories) {
        foreach ($CheckId in @($Category.CheckIds)) {
            if (-not $Ids.Checks.Contains([string] $CheckId)) { throw "Category '$($Category.Id)' references missing Check '$CheckId'." }
            if ($CategoryMembership.ContainsKey([string] $CheckId)) { throw "Check '$CheckId' is assigned to multiple categories." }
            $CategoryMembership[[string] $CheckId] = [string] $Category.Id
        }
    }
    foreach ($Check in $Assessment.Checks) {
        if (-not $Ids.Categories.Contains([string] $Check.CategoryId)) { throw "Check '$($Check.Id)' references missing Category '$($Check.CategoryId)'." }
        if (-not $CategoryMembership.ContainsKey([string] $Check.Id) -or $CategoryMembership[[string] $Check.Id] -ine [string] $Check.CategoryId) {
            throw "Check '$($Check.Id)' and Category '$($Check.CategoryId)' have inconsistent CheckIds."
        }
    }
    foreach ($Exception in $Assessment.Exceptions) {
        if ($Exception.CheckId -and -not $Ids.Checks.Contains([string] $Exception.CheckId)) { throw "Exception '$($Exception.Id)' references missing Check '$($Exception.CheckId)'." }
        if ($Exception.ApprovedAt -and $Exception.ExpiresAt -and $Exception.ExpiresAt -le $Exception.ApprovedAt) { throw "Exception '$($Exception.Id)' ExpiresAt must follow ApprovedAt." }
    }
    if ($null -ne $Model) {
        [void] (Assert-PSIApplicationModel -Model $Model)
        $ModelIds = @{}
        foreach ($Kind in @('Findings','Resources','Evidence')) {
            $ModelIds[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Record in @($Model.$Kind)) { [void] $ModelIds[$Kind].Add([string] $Record.Id) }
        }
        $References = @(
            @{ Records=@($Assessment); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment); Field='EvidenceIds'; Target='Evidence' },
            @{ Records=@($Assessment.Categories); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment.Categories); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment.Checks); Field='FindingIds'; Target='Findings' },
            @{ Records=@($Assessment.Checks); Field='ResourceIds'; Target='Resources' },
            @{ Records=@($Assessment.Checks); Field='EvidenceIds'; Target='Evidence' },
            @{ Records=@($Assessment.Exceptions); Field='ResourceIds'; Target='Resources' }
        )
        foreach ($Reference in $References) {
            foreach ($Record in $Reference.Records) {
                $Values = Get-PSIProperty -InputObject $Record -Name $Reference.Field -DefaultValue @()
                foreach ($Id in @($Values)) {
                    if ([string]::IsNullOrWhiteSpace([string] $Id) -or -not $ModelIds[$Reference.Target].Contains([string] $Id)) {
                        throw "'$($Record.Id)' has broken $($Reference.Field) reference '$Id' to $($Reference.Target)."
                    }
                }
            }
        }
        foreach ($Exception in $Assessment.Exceptions) {
            if ($Exception.FindingId -and -not $ModelIds.Findings.Contains([string] $Exception.FindingId)) { throw "Exception '$($Exception.Id)' references missing Finding '$($Exception.FindingId)'." }
        }
        foreach ($Field in @('FindingIds','ResourceIds','EvidenceIds')) {
            $AssessmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Id in @($Assessment.$Field)) { [void] $AssessmentIds.Add([string] $Id) }
            foreach ($Check in $Assessment.Checks) {
                foreach ($Id in @($Check.$Field)) {
                    if (-not $AssessmentIds.Contains([string] $Id)) { throw "Check '$($Check.Id)' links '$Id' outside Assessment.$Field." }
                }
            }
        }
    }
    $true
}
#endregion

#region Private/Assert-PSIApplicationLinks.ps1
function Assert-PSIApplicationLinks {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    foreach ($View in $Report.Views) {
        foreach ($Section in $View.Sections) {
            foreach ($Row in $Section.Rows) {
                foreach ($Component in $Row.Components) {
                    if ($Component.Type -ne 'Explorer' -or -not $Component.Properties.EntityType) { continue }
                    $Properties = $Component.Properties
                    $RequiredKinds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Checks = switch ([string] $Properties.EntityType) {
                        Finding { @(@('AffectedResourceIds','Resource'),@('EvidenceIds','Evidence')) }
                        Resource { @(@('FindingIds','Finding'),@('EvidenceIds','Evidence'),@('RelationshipIds','Resource')) }
                        Evidence { @(@('ResourceIds','Resource'),@('FindingIds','Finding')) }
                        Check { @(@('FindingIds','Finding'),@('ResourceIds','Resource'),@('EvidenceIds','Evidence')) }
                        Category { @(@('CheckIds','Check')) }
                        Exception { @(@('CheckId','Check'),@('FindingId','Finding'),@('ResourceIds','Resource')) }
                    }
                    foreach ($Record in @($Properties.Data)) {
                        foreach ($Check in $Checks) {
                            $Values = @(Get-PSIProperty -InputObject $Record -Name $Check[0] -DefaultValue @())
                            if (@($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }).Count -gt 0) {
                                [void] $RequiredKinds.Add([string] $Check[1])
                            }
                        }
                    }
                    foreach ($Kind in $RequiredKinds) {
                        $TargetId = [string] $Properties.LinkViews[$Kind]
                        $TargetView = @($Report.Views | Where-Object { $_.Id -ieq $TargetId })[0]
                        if ($null -eq $TargetView) { throw "Explorer '$($Properties.Id)' links to missing $Kind view '$TargetId'." }
                        $HasTargetExplorer = $false
                        foreach ($TargetSection in $TargetView.Sections) {
                            foreach ($TargetRow in $TargetSection.Rows) {
                                foreach ($TargetComponent in $TargetRow.Components) {
                                    if ($TargetComponent.Type -eq 'Explorer' -and $TargetComponent.Properties.EntityType -eq $Kind) { $HasTargetExplorer = $true }
                                }
                            }
                        }
                        if (-not $HasTargetExplorer) { throw "Explorer '$($Properties.Id)' links to view '$TargetId' without a $Kind explorer." }
                    }
                }
            }
        }
    }
    $true
}
#endregion

#region Private/Assert-PSIApplicationModel.ps1
function Assert-PSIApplicationModel {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Model)

    $Kinds = @('Findings','Resources','Evidence','Relationships')
    $Ids = @{}
    foreach ($Kind in $Kinds) {
        $Ids[$Kind] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in @((Get-PSIProperty -InputObject $Model -Name $Kind -DefaultValue @()))) {
            if ($null -eq $Record) { throw "$Kind cannot contain a null record." }
            $Definition = @{}
            foreach ($Property in $Record.PSObject.Properties) { $Definition[$Property.Name] = $Property.Value }
            $ContractKind = if ($Kind -eq 'Evidence') { 'Evidence' } else { $Kind.TrimEnd('s') }
            [void] (New-PSIContractObject -Kind $ContractKind -Definition $Definition)
            $Id = [string] (Get-PSIProperty -InputObject $Record -Name Id)
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind contains an invalid or missing Id." }
            if (-not $Ids[$Kind].Add($Id)) { throw "$Kind contains duplicate Id '$Id'." }
        }
    }
    $References = @(
        @{ Kind='Findings'; Field='AffectedResourceIds'; Target='Resources' },
        @{ Kind='Findings'; Field='EvidenceIds'; Target='Evidence' },
        @{ Kind='Findings'; Field='Relationships'; Target='Relationships' },
        @{ Kind='Resources'; Field='FindingIds'; Target='Findings' },
        @{ Kind='Resources'; Field='EvidenceIds'; Target='Evidence' },
        @{ Kind='Resources'; Field='RelationshipIds'; Target='Relationships' },
        @{ Kind='Evidence'; Field='FindingIds'; Target='Findings' },
        @{ Kind='Evidence'; Field='ResourceIds'; Target='Resources' },
        @{ Kind='Relationships'; Field='SourceResourceId'; Target='Resources' },
        @{ Kind='Relationships'; Field='TargetResourceId'; Target='Resources' },
        @{ Kind='Relationships'; Field='FindingIds'; Target='Findings' },
        @{ Kind='Relationships'; Field='EvidenceIds'; Target='Evidence' }
    )
    foreach ($Reference in $References) {
        foreach ($Record in @((Get-PSIProperty -InputObject $Model -Name $Reference.Kind -DefaultValue @()))) {
            $Value = Get-PSIProperty -InputObject $Record -Name $Reference.Field
            if ($null -eq $Value) { continue }
            foreach ($ReferenceId in @($Value)) {
                if ($Reference.Kind -eq 'Relationships' -and $Reference.Target -eq 'Resources' -and
                    (Get-PSIProperty -InputObject $Record -Name 'IsExternal' -DefaultValue $false) -eq $true -and
                    (Get-PSIProperty -InputObject $Record -Name 'EvidenceOnly' -DefaultValue $false) -eq $true -and
                    -not $Ids.Resources.Contains([string] $ReferenceId)) {
                    $OtherField = if ($Reference.Field -eq 'SourceResourceId') { 'TargetResourceId' } else { 'SourceResourceId' }
                    $OtherId = [string] (Get-PSIProperty -InputObject $Record -Name $OtherField)
                    if ($Ids.Resources.Contains($OtherId)) { continue }
                }
                if ([string]::IsNullOrWhiteSpace([string] $ReferenceId) -or -not $Ids[$Reference.Target].Contains([string] $ReferenceId)) {
                    throw "$($Reference.Kind) '$($Record.Id)' has broken $($Reference.Field) reference '$ReferenceId' to $($Reference.Target)."
                }
            }
        }
    }
    $true
}
#endregion

#region Private/Assert-PSIReportIds.ps1
function Assert-PSIReportIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable] $Sections,

        [Parameter()]
        [System.Collections.IEnumerable] $AdditionalSections = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $ProposedTableId = ''
    )

    $TableIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Section in @($Sections) + @($AdditionalSections)) {
        foreach ($Row in @($Section.Rows)) {
            foreach ($Component in @($Row.Components)) {
                if ($Component.Type -ne 'Table') { continue }
                $TableId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ([string]::IsNullOrWhiteSpace($TableId)) { continue }
                if (-not $TableIds.Add($TableId)) {
                    throw "Table ID '$TableId' already exists in this report. Assign a unique table ID before composing or exporting."
                }
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProposedTableId) -and -not $TableIds.Add($ProposedTableId)) {
        throw "Table ID '$ProposedTableId' already exists in this report. Assign a unique table ID before adding the table."
    }
    ,$TableIds
}
#endregion

#region Private/Compare-PSIConditionValues.ps1
function Compare-PSIConditionValues {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object] $Left,
        [Parameter()][AllowNull()][object] $Right
    )

    if ($null -eq $Left -or $null -eq $Right) { return $null }

    if ($Left -is [bool] -or $Right -is [bool]) {
        $LeftBool = $false
        $RightBool = $false
        if ($Left -is [bool]) { $LeftBool = $Left; $LeftValid = $true }
        else { $LeftValid = $Left -is [string] -and [bool]::TryParse($Left, [ref] $LeftBool) }
        if ($Right -is [bool]) { $RightBool = $Right; $RightValid = $true }
        else { $RightValid = $Right -is [string] -and [bool]::TryParse($Right, [ref] $RightBool) }
        if (-not ($LeftValid -and $RightValid)) { return $null }
        return [Math]::Sign([int] $LeftBool - [int] $RightBool)
    }

    $Culture = [System.Globalization.CultureInfo]::InvariantCulture
    $NumberStyle = [System.Globalization.NumberStyles]::Float
    $LeftNumber = [decimal] 0
    $RightNumber = [decimal] 0
    if ([decimal]::TryParse([string] $Left, $NumberStyle, $Culture, [ref] $LeftNumber) -and
        [decimal]::TryParse([string] $Right, $NumberStyle, $Culture, [ref] $RightNumber)) {
        return $LeftNumber.CompareTo($RightNumber)
    }

    $LeftDate = [datetimeoffset]::MinValue
    $RightDate = [datetimeoffset]::MinValue
    $DateStyle = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if (($Left -is [datetime] -or $Left -is [datetimeoffset] -or $Left -is [string]) -and
        ($Right -is [datetime] -or $Right -is [datetimeoffset] -or $Right -is [string])) {
        $LeftDateText = if ($Left -is [datetime] -or $Left -is [datetimeoffset]) { $Left.ToString('o', $Culture) } else { [string] $Left }
        $RightDateText = if ($Right -is [datetime] -or $Right -is [datetimeoffset]) { $Right.ToString('o', $Culture) } else { [string] $Right }
        if ([datetimeoffset]::TryParse($LeftDateText, $Culture, $DateStyle, [ref] $LeftDate) -and
            [datetimeoffset]::TryParse($RightDateText, $Culture, $DateStyle, [ref] $RightDate)) {
            return $LeftDate.UtcDateTime.CompareTo($RightDate.UtcDateTime)
        }
    }

    if ($Left -is [string] -and $Right -is [string]) {
        return [string]::Compare($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return $null
}
#endregion

#region Private/ConvertTo-PSIApplicationShell.ps1
function ConvertTo-PSIApplicationShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][string] $Styles,
        [Parameter(Mandatory = $true)][string] $Sections,
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]] $Navigation,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Dialog,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $ExportToolbar,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $ExportScript,
        [Parameter(Mandatory = $true)][string] $StatusScript,
        [Parameter(Mandatory = $true)][string] $InteractionScript,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $TableScript,
        [Parameter()][bool] $HasTableSearch = $false,
        [Parameter()][bool] $IsMultiView = $false,
        [Parameter()][bool] $HasRelationshipComponents = $false,
        [Parameter()][bool] $EnableReportPrint = $true
    )

    $Title = ConvertTo-PSIHtmlEncoded -Value $Report.Title
    $Subtitle = ConvertTo-PSIHtmlEncoded -Value $Report.Subtitle
    $GeneratedOn = ConvertTo-PSIHtmlEncoded -Value ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $ModuleVersion = ConvertTo-PSIHtmlEncoded -Value $Report.ModuleVersion
    $Theme = [string] $Report.Theme
    $NavigationMode = [string] (Get-PSIProperty -InputObject $Report -Name 'Navigation' -DefaultValue 'Sidebar')
    $Density = [string] (Get-PSIProperty -InputObject $Report -Name 'Density' -DefaultValue 'Comfortable')
    $ResourceWorkspace = ConvertTo-PSIResourceWorkspace -Report $Report
    $HasResourceExplorer = if ($ResourceWorkspace.Explorer) { 'true' } else { 'false' }
    $HasInspector = if ($ResourceWorkspace.Inspector) { 'true' } else { 'false' }
    $NavMarkup = [System.Text.StringBuilder]::new()
    foreach ($Group in $Navigation) {
        $GroupLabel = ConvertTo-PSIHtmlEncoded -Value $Group.Label
        [void] $NavMarkup.AppendLine("<div class=`"psi-app-nav-group`"><p class=`"psi-app-nav-heading`">$GroupLabel</p><ul>")
        foreach ($Item in $Group.Items) {
            $ItemId = 'psi-app-item-' + $Item.Id
            $ItemLabel = ConvertTo-PSIHtmlEncoded -Value $Item.Label
            $Regular = (Get-PSIIcon -Name $Item.Icon -Variant Regular -Size 20 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-regular"')
            $Filled = (Get-PSIIcon -Name $Item.Icon -Variant Filled -Size 20 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-filled"')
            $Icon = '<span class="psi-app-nav-icon">' + $Regular + $Filled + '</span>'
            $Badge = if ([string]::IsNullOrWhiteSpace($Item.Badge)) { '' } else {
                '<span class="psi-app-nav-badge">' + (ConvertTo-PSIHtmlEncoded -Value $Item.Badge) + '</span>'
            }
            $ItemTitle = if ($NavigationMode -eq 'FluentExplorer') { " title=`"$ItemLabel`"" } else { '' }
            if ($Item.Disabled) {
                [void] $NavMarkup.AppendLine("<li><span id=`"$ItemId`" class=`"psi-app-nav-item`" aria-disabled=`"true`"$ItemTitle>$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</span></li>")
            }
            else {
                $Current = if ($Item.Selected) {
                    if ($IsMultiView) { ' aria-current="page"' } else { ' aria-current="location"' }
                } else { '' }
                if ($IsMultiView) {
                    [void] $NavMarkup.AppendLine("<li><button type=`"button`" id=`"$ItemId`" class=`"psi-app-nav-item`" data-psi-app-item data-psi-app-view-target=`"$($Item.Id)`" aria-controls=`"$($Item.Target)`"$Current$ItemTitle>$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</button></li>")
                }
                else {
                    [void] $NavMarkup.AppendLine("<li><a id=`"$ItemId`" class=`"psi-app-nav-item`" href=`"#$($Item.Target)`" data-psi-app-item$Current$ItemTitle>$Icon<span class=`"psi-app-nav-label`">$ItemLabel</span>$Badge</a></li>")
                }
            }
        }
        [void] $NavMarkup.AppendLine('</ul></div>')
    }

    $IconRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/Icons/Fluent'
    $License = ConvertTo-PSIHtmlEncoded -Value (Get-Content -LiteralPath (Join-Path $IconRoot 'LICENSE') -Raw -ErrorAction Stop)
    $Notice = ConvertTo-PSIHtmlEncoded -Value (Get-Content -LiteralPath (Join-Path $IconRoot 'NOTICE') -Raw -ErrorAction Stop)
    $AppScript = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-application.js') -Raw -ErrorAction Stop
    $RelationshipScript = if ($HasRelationshipComponents) { Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-relationships.js') -Raw -ErrorAction Stop } else { '' }
    $RelationshipScriptMarkup = if ($HasRelationshipComponents) { "<script>`n$RelationshipScript`n</script>" } else { '' }
    $PrintProjection = ''
    $PrintScript = ''
    if ($EnableReportPrint) {
        $PrintProjection = ConvertTo-PSIPrintProjection -Report $Report
        $PrintScript = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-print.js') -Raw -ErrorAction Stop
        $AssessmentTarget = [string] (Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Report -Name 'ApplicationAssessment') -Name 'Target')
        $FooterIdentity = ConvertTo-PSICssString -Value ($Report.Title + $(if ($AssessmentTarget) { ' | ' + $AssessmentTarget } else { '' }))
        $FooterVersion = ConvertTo-PSICssString -Value ('PSInsightHTML v' + $Report.ModuleVersion + ' | Page ')
        $Styles += "`n@media print { @page { @bottom-left { content: `"$FooterIdentity`"; } @bottom-right { content: `"$FooterVersion`" counter(page); } } }"
    }
    $MenuIcon = Get-PSIIcon -Name Menu -Size 22 -Strict
    $CloseIcon = Get-PSIIcon -Name AppClose -Size 20 -Strict
    $LightIcon = Get-PSIIcon -Name ThemeLight -Size 18 -Strict
    $DarkIcon = Get-PSIIcon -Name ThemeDark -Size 18 -Strict
    $AutoIcon = Get-PSIIcon -Name AppSettings -Size 18 -Strict
    $InfoIcon = Get-PSIIcon -Name SeverityInfo -Size 16 -Strict
    $GlobalSearchButton = ''
    $GlobalSearchMarkup = ''
    $GlobalSearchScript = ''
    if ($IsMultiView) {
        $GlobalIcon = Get-PSIIcon -Name NavigationSearch -Size 19 -Strict
        $SearchTitle = if ($null -ne (Get-PSIProperty -InputObject $Report -Name 'ApplicationAssessment')) { 'Search assessment' } else { 'Search report' }
        $GlobalSearchButton = '<button type="button" class="psi-app-global-search-trigger" data-psi-global-search-trigger aria-haspopup="dialog" aria-controls="psi-global-search" aria-label="Search all report views and records">' + $GlobalIcon + '<span>' + $SearchTitle + '</span><kbd>Ctrl K</kbd></button>'
        $SearchIndex = @(Get-PSIApplicationSearchIndex -Report $Report)
        $IndexJson = (ConvertTo-Json -InputObject $SearchIndex -Depth 4 -Compress).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
        $SearchIconMarkup = [System.Text.StringBuilder]::new()
        foreach ($Entry in @(@('View','Document'),@('Check','Rules'),@('Finding','SeverityWarning'),@('Resource','ResourceServer'),@('Evidence','Document'),@('Exception','SeverityInfo'))) {
            [void] $SearchIconMarkup.Append('<template data-psi-search-icon="' + $Entry[0] + '">' + (Get-PSIIcon -Name $Entry[1] -Size 19 -Strict) + '</template>')
        }
        $GlobalSearchMarkup = @"
  <script type="application/json" id="psi-global-search-index">$IndexJson</script>
  $($SearchIconMarkup.ToString())
  <div class="psi-global-search-backdrop" data-psi-global-search-backdrop hidden>
    <section class="psi-global-search-dialog" id="psi-global-search" role="dialog" aria-modal="true" aria-labelledby="psi-global-search-title" aria-describedby="psi-global-search-help">
      <header class="psi-global-search-header"><div><p>Report workspace</p><h2 id="psi-global-search-title">$SearchTitle</h2></div><button type="button" data-psi-global-search-close aria-label="Close search">$CloseIcon</button></header>
      <div class="psi-global-search-modes" role="group" aria-label="Palette mode"><button type="button" data-psi-global-mode="Search" aria-pressed="true">Search</button><button type="button" data-psi-global-mode="Commands" aria-pressed="false">Commands</button></div>
      <label class="psi-global-search-input-wrap" for="psi-global-search-input">$GlobalIcon<span class="psi-sr-only">Search views and records or enter a command</span><input id="psi-global-search-input" type="search" data-psi-global-search-input role="combobox" aria-autocomplete="list" aria-expanded="true" aria-controls="psi-global-search-results" autocomplete="off" placeholder="Find a view, check, finding, resource..."></label>
      <p class="psi-global-search-summary" data-psi-global-search-summary role="status" aria-live="polite"></p>
      <div class="psi-global-search-results" id="psi-global-search-results" data-psi-global-search-results role="listbox" aria-label="Search results"></div>
      <footer id="psi-global-search-help">Up / Down to select &middot; Enter to open &middot; Esc to close &middot; Type &gt; for commands</footer>
    </section>
  </div>
"@
        $GlobalSearchScript = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-search.js') -Raw -ErrorAction Stop
    }
    $SearchButton = if ($HasTableSearch) {
        $SearchIcon = Get-PSIIcon -Name NavigationSearch -Size 19 -Strict
        '<button type="button" class="psi-app-table-search-shortcut" data-psi-app-find-table aria-label="Find in the active view">' + $SearchIcon + '<span>Find in view</span></button>'
    }
    else { '' }
    $WorkspaceMode = if ($IsMultiView) { 'Views' } else { 'Document' }
    $CommandHeading = "<p class=`"psi-app-eyebrow`">PSInsightHTML | Report workspace</p><h1>$Title</h1><p class=`"psi-app-subtitle`">$Subtitle</p>"
    $ContextHeading = 'Snapshot details'
    $ViewCommandMarkup = [System.Text.StringBuilder]::new()
    $WorkspaceTabs = ''
    if ($IsMultiView) {
        $InitialView = @($Report.Views | Where-Object { $_.State.Initial })[0]
        if ($null -eq $InitialView) {
            $SelectedNavItem = @($Navigation | ForEach-Object { $_.Items } | Where-Object { $_.Selected })[0]
            $InitialView = @($Report.Views | Where-Object { $_.Id -ceq $SelectedNavItem.Id })[0]
        }
        $ViewTitle = ConvertTo-PSIHtmlEncoded -Value $InitialView.Title
        $ViewSubtitle = ConvertTo-PSIHtmlEncoded -Value $InitialView.Subtitle
        $CommandHeading = "<p class=`"psi-app-eyebrow`">$Title | PSInsightHTML</p><h1 id=`"psi-app-active-view-title`" data-psi-app-view-title>$ViewTitle</h1><p class=`"psi-app-subtitle`" data-psi-app-view-subtitle>$ViewSubtitle</p>"
        $ContextHeading = '<span data-psi-app-context-title>' + $ViewTitle + '</span> details'
        if ($NavigationMode -eq 'FluentExplorer' -and $Density -eq 'Compact') {
            $TabMarkup = [System.Text.StringBuilder]::new()
            [void] $TabMarkup.Append('<nav class="psi-workspace-tabs" role="tablist" aria-label="Workspace views">')
            foreach ($View in $Report.Views) {
                $SafeId = [string] $View.Id
                $SafeLabel = ConvertTo-PSIHtmlEncoded -Value $View.Title
                $IsSelected = if ($View.Id -ceq $InitialView.Id) { 'true' } else { 'false' }
                $TabIndex = if ($IsSelected -eq 'true') { '0' } else { '-1' }
                $DisabledAttribute = if ($View.Disabled) { ' disabled aria-disabled="true"' } else { '' }
                $Count = ''
                if ($null -ne $View.TabCount) { $Count = '<span class="psi-workspace-tab-count">' + [int]$View.TabCount + '</span>' }
                [void] $TabMarkup.Append("<button type=`"button`" id=`"psi-workspace-tab-$SafeId`" role=`"tab`" data-psi-workspace-tab=`"$SafeId`" aria-controls=`"psi-view-$SafeId`" aria-selected=`"$IsSelected`" tabindex=`"$TabIndex`"$DisabledAttribute>$SafeLabel$Count</button>")
            }
            [void] $TabMarkup.Append('</nav>')
            $WorkspaceTabs = $TabMarkup.ToString()
        }
        foreach ($View in $Report.Views) {
            $Hidden = if ($View.Id -cne $InitialView.Id) { ' hidden' } else { '' }
            foreach ($Command in $View.Commands) {
                $SafeLabel = ConvertTo-PSIHtmlEncoded -Value $Command.Label
                $CommandIcon = Get-PSIIcon -Name $Command.Icon -Size 18 -Strict
                [void] $ViewCommandMarkup.AppendLine("<button type=`"button`" class=`"psi-app-view-command`" data-psi-app-command-view=`"$($View.Id)`" data-psi-app-command-target=`"$($Command.TargetView)`" aria-label=`"$SafeLabel`"$Hidden>$CommandIcon<span>$SafeLabel</span></button>")
            }
        }
    }
    $ContextMarkup = if ($ResourceWorkspace.Inspector) { $ResourceWorkspace.Inspector } else {
        '<aside class="psi-app-context" aria-label="Report context"><div class="psi-app-context-card"><p class="psi-app-context-eyebrow">' + $InfoIcon + ' Report context</p><h2>' + $ContextHeading + '</h2><dl><div><dt>Generated</dt><dd>' + $GeneratedOn + '</dd></div><div><dt>Module</dt><dd>v' + $ModuleVersion + '</dd></div><div><dt>Theme</dt><dd data-psi-theme-value>' + $Theme + '</dd></div></dl><p>This standalone view contains its data and presentation assets.</p></div></aside>'
    }

    @"
<!DOCTYPE html>
<html lang="en" data-theme="$Theme" data-psi-layout="Application" data-psi-workspace="$WorkspaceMode" data-psi-navigation="$NavigationMode" data-psi-density="$Density" data-psi-resource-explorer="$HasResourceExplorer" data-psi-inspector="$HasInspector">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$Title</title>
  <style>
$Styles
  </style>
</head>
<body>
  <div class="psi-app-shell">
    <aside class="psi-app-sidebar" id="psi-app-navigation" aria-label="$(if ($NavigationMode -eq 'FluentExplorer') { 'Global navigation' } else { 'Report navigation' })">
      <div class="psi-app-brand"><span class="psi-app-brand-mark" aria-hidden="true"><svg viewBox="0 0 48 48" width="27" height="27" fill="none"><path d="M24 3 43 14v20L24 45 5 34V14L24 3Z" stroke="currentColor" stroke-width="2.5"/><path d="M15 31V17h8a5 5 0 0 1 0 10h-4M27 31h7M27 31a4 4 0 0 1 0-8h7" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></span><span><strong>PSInsightHTML</strong><small>Report workspace</small></span><button type="button" class="psi-app-nav-close" data-psi-app-close aria-label="Close navigation">$CloseIcon</button></div>
      <nav aria-label="Report sections">
$($NavMarkup.ToString())      </nav>
      <p class="psi-app-sidebar-foot">Standalone report | Module v$ModuleVersion</p>
    </aside>
    <div class="psi-app-scrim" data-psi-app-scrim hidden></div>
$($ResourceWorkspace.Explorer)
    <div class="psi-app-body">
      <header class="psi-app-command" id="psi-app-command">
        <div class="psi-app-command-leading"><button type="button" id="psi-app-nav-toggle" class="psi-app-menu-button" data-psi-app-toggle aria-controls="psi-app-navigation" aria-expanded="false" aria-label="Open navigation" title="Open navigation">$MenuIcon</button><div class="psi-app-heading">$CommandHeading</div></div>
        <div class="psi-app-command-actions">$($ResourceWorkspace.Controls)$($ViewCommandMarkup.ToString())$GlobalSearchButton$SearchButton<div class="psi-theme-control" role="group" aria-label="Report color theme"><button type="button" data-psi-theme="Light" aria-pressed="false">$LightIcon<span>Light</span></button><button type="button" data-psi-theme="Dark" aria-pressed="false">$DarkIcon<span>Dark</span></button><button type="button" data-psi-theme="Auto" aria-pressed="false">$AutoIcon<span>Auto</span></button></div>$ExportToolbar</div>
      </header>
      <main class="psi-app-workspace" id="psi-app-main">
        <div class="psi-app-content">$($ResourceWorkspace.Header)$WorkspaceTabs$Sections</div>
        $ContextMarkup
      </main>
      <footer class="psi-app-footer">Generated by PSInsightHTML | Theme <span data-psi-theme-footer>$Theme</span></footer>
    </div>
  </div>
  $PrintProjection
  $($ResourceWorkspace.Data)
  $GlobalSearchMarkup
  <template id="psi-fluent-icon-attribution"><pre>$License

$Notice</pre></template>
  $Dialog
  $ExportScript
  $StatusScript
  $InteractionScript
  $TableScript
  <script>
$AppScript
  </script>
  <script>
$($ResourceWorkspace.Script)
  </script>
  $RelationshipScriptMarkup
  <script>
$GlobalSearchScript
  </script>
  <script>
$PrintScript
  </script>
</body>
</html>
"@
}
#endregion

#region Private/ConvertTo-PSIAssessmentDetailHtml.ps1
function ConvertTo-PSIAssessmentDetailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Check','Category')][string] $Kind,
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $Name = ConvertTo-PSIHtmlEncoded -Value $Record.Name
    $IconName = if ($Kind -eq 'Category') { [string] $Record.Icon } else { 'Rules' }
    $Icon = Get-PSIIcon -Name $IconName
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">$Kind investigation</p><h4>$Name</h4></div></header>")
    $Canonical = Resolve-PSIAssessmentStatus -Status ([string] $Record.Status)
    $Class = if ($Canonical -eq 'NotChecked') { 'not-checked' } else { $Canonical.ToLowerInvariant() }
    $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
    $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
    [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span class=`"psi-status-badge psi-status-$Class`">$Status</span><span>Weight $($Record.Weight)</span></div><p class=`"psi-intelligence-summary`">$Description</p>")
    if ($Kind -eq 'Category') {
        $Score = if ($null -eq $Record.Score) { 'N/A' } else { "$($Record.Score)%" }
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Category posture</h5><p>Score: $Score from $(@($Record.CheckIds).Count) linked checks.</p></section><section class=`"psi-intelligence-block`"><h5>Checks</h5>")
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.CheckIds) -Records $Assessment.Checks -View ([string] $LinkViews.Check) -LabelProperty Name))
        [void] $B.AppendLine('</section>')
    }
    else {
        $Category = @($Assessment.Categories | Where-Object { $_.Id -ieq $Record.CategoryId })[0]
        $CategoryName = ConvertTo-PSIHtmlEncoded -Value $Category.Name
        $Observed = ConvertTo-PSIHtmlEncoded -Value $Record.ObservedState
        $Expected = ConvertTo-PSIHtmlEncoded -Value $Record.ExpectedState
        $Blocking = if ($Record.IsBlocking) { '<strong class="psi-assessment-blocker">Blocking check</strong>' } else { '' }
        [void] $B.AppendLine("<p class=`"psi-intelligence-summary`">Category: $CategoryName $Blocking</p><section class=`"psi-intelligence-block`"><h5>Observed / Expected</h5><dl><div><dt>Observed</dt><dd>$Observed</dd></div><div><dt>Expected</dt><dd>$Expected</dd></div></dl></section>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Affected resources</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View ([string] $LinkViews.Resource) -LabelProperty Name))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View ([string] $LinkViews.Finding) -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View ([string] $LinkViews.Evidence) -LabelProperty Title))
        [void] $B.AppendLine('</section>')
        $Action = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Action -DefaultValue 'No provider recommendation supplied.')
        $Method = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name Method -DefaultValue 'No validation method supplied.')
        $ExpectedResult = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name ExpectedResult -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Recommendation</h5><p>$Action</p></section><section class=`"psi-intelligence-block`"><h5>Validation</h5><p>$Method</p><small>$ExpectedResult</small></section>")
        if (@($Record.Frameworks).Count -gt 0) {
            $Frameworks = ConvertTo-PSIHtmlEncoded -Value (@($Record.Frameworks) -join ', ')
            [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Framework / source</h5><p>$Frameworks</p></section>")
        }
    }
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIAssessmentExceptionHtml.ps1
function ConvertTo-PSIAssessmentExceptionHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $Icon = Get-PSIIcon -Name 'SeverityInfo'
    $Title = ConvertTo-PSIHtmlEncoded -Value $Record.Title
    $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
    $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
    $Reason = ConvertTo-PSIHtmlEncoded -Value $Record.Reason
    $Owner = ConvertTo-PSIHtmlEncoded -Value $Record.Owner
    $Approver = ConvertTo-PSIHtmlEncoded -Value $Record.ApprovedBy
    $Approved = if ($Record.ApprovedAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.ApprovedAt).ToString('yyyy-MM-dd') } else { 'Not supplied' }
    $Expiry = if ($Record.ExpiresAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.ExpiresAt).ToString('yyyy-MM-dd') } else { 'Not supplied' }
    $Expiring = $Record.Status -eq 'Approved' -and $Record.ExpiresAt -and
        $Record.ExpiresAt -gt $Assessment.GeneratedAt -and $Record.ExpiresAt -le $Assessment.GeneratedAt.AddDays(7)
    $ExpiryFlag = if ($Expiring) { '<strong class="psi-assessment-blocker">Expires within seven days</strong>' } else { '' }
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">Assessment exception</p><h4>$Title</h4></div></header><div class=`"psi-intelligence-meta`"><span>$Status</span>$ExpiryFlag</div><p class=`"psi-intelligence-summary`">$Description</p><section class=`"psi-intelligence-block`"><h5>Reason and ownership</h5><dl><div><dt>Reason</dt><dd>$Reason</dd></div><div><dt>Owner</dt><dd>$Owner</dd></div><div><dt>Approved by</dt><dd>$Approver</dd></div><div><dt>Approved at</dt><dd>$Approved</dd></div><div><dt>Expires at</dt><dd>$Expiry</dd></div></dl></section>")
    [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Linked check</h5>')
    $CheckIds = if ($Record.CheckId) { @($Record.CheckId) } else { @() }
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids $CheckIds -Records $Assessment.Checks -View ([string] $LinkViews.Check) -LabelProperty Name))
    [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Linked finding</h5>')
    $FindingIds = if ($Record.FindingId) { @($Record.FindingId) } else { @() }
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids $FindingIds -Records $Model.Findings -View ([string] $LinkViews.Finding) -LabelProperty Title))
    [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Affected resources</h5>')
    [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View ([string] $LinkViews.Resource) -LabelProperty Name))
    [void] $B.AppendLine('</section><p class="psi-intelligence-muted">Exceptions are documented here; they do not automatically change the posture decision.</p>')
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIAssessmentOverviewHtml.ps1
function ConvertTo-PSIAssessmentOverviewHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Properties)
    $A = $Properties.Assessment
    $Model = $Properties.Model
    $B = [System.Text.StringBuilder]::new()
    $SafeName = ConvertTo-PSIHtmlEncoded -Value $A.Name
    $SafeType = ConvertTo-PSIHtmlEncoded -Value $A.AssessmentType
    $SafeTarget = ConvertTo-PSIHtmlEncoded -Value $A.Target
    $SafeProfile = ConvertTo-PSIHtmlEncoded -Value $A.Profile
    $SafeDescription = ConvertTo-PSIHtmlEncoded -Value $A.Description
    $DecisionLabel = ([string] $A.Decision -creplace '([a-z])([A-Z])','$1 $2').ToUpperInvariant()
    $SafeDecision = ConvertTo-PSIHtmlEncoded -Value $DecisionLabel
    $StatusClass = if ($A.OverallStatus -eq 'NotChecked') { 'not-checked' } else { ([string] $A.OverallStatus).ToLowerInvariant() }
    $ScoreNumber = if ($null -eq $A.Score) { 0 } else { [math]::Max(0,[math]::Min(100,[double] $A.Score)) }
    $ScoreText = if ($null -eq $A.Score) { 'N/A' } else { "$($A.Score)%" }
    $SafeScore = ConvertTo-PSIHtmlEncoded -Value $ScoreText
    $Counts = $A.ScoreExplanation.Counts
    $Icon = Get-PSIIcon -Name 'SecurityShield' -Size 22
    $ReasonText = @($A.ScoreExplanation.Reasons | Select-Object -First 2 | ForEach-Object { ConvertTo-PSIHtmlEncoded -Value $_ }) -join ' '
    $CoverageMarkup = ''
    if ($null -ne $A.Metadata -and $null -ne $A.Metadata.EvidenceCoveragePercent) {
        $Coverage = ConvertTo-PSIHtmlEncoded -Value "$($A.Metadata.EvidenceCoveragePercent)%"
        $CoverageMarkup = "<div class=`"psi-assessment-coverage`"><strong>$Coverage</strong><span>Evidence coverage</span></div>"
    }
    [void] $B.AppendLine("<section class=`"psi-assessment-overview`" data-psi-assessment-overview><div class=`"psi-assessment-hero psi-status-$StatusClass`"><div class=`"psi-assessment-hero-copy`"><p class=`"psi-assessment-eyebrow`">$Icon $SafeType assessment</p><h3>$SafeName</h3><p>$SafeDescription</p><div class=`"psi-assessment-identity`"><span>Target: $SafeTarget</span><span>Profile: $SafeProfile</span></div><div class=`"psi-assessment-verdict`"><strong class=`"psi-assessment-decision`">$SafeDecision</strong><p class=`"psi-assessment-decision-reason`">$ReasonText</p></div></div><div class=`"psi-assessment-measures`"><div class=`"psi-assessment-gauge`" role=`"img`" aria-label=`"Posture score $SafeScore`" style=`"--psi-posture-score:$ScoreNumber`"><div><strong>$SafeScore</strong><small>Posture score</small></div></div>$CoverageMarkup</div></div>")
    [void] $B.AppendLine('<div class="psi-assessment-counts">')
    foreach ($Metric in @(
        @{ Label='Blockers'; Value=($Counts.Blockers + $Counts.CriticalFindings); Class='critical' },
        @{ Label='Review'; Value=$Counts.Review; Class='warning' },
        @{ Label='Ready'; Value=$Counts.Ready; Class='healthy' },
        @{ Label='Not tested'; Value=$Counts.NotTested; Class='not-checked' }
    )) {
        [void] $B.AppendLine("<div class=`"psi-assessment-count psi-status-$($Metric.Class)`"><strong>$($Metric.Value)</strong><span>$($Metric.Label)</span></div>")
    }
    [void] $B.AppendLine('</div><div class="psi-assessment-overview-grid"><section class="psi-assessment-panel"><header><h4>Category posture</h4><span>Weighted score</span></header><div class="psi-assessment-categories">')
    $CheckView = ConvertTo-PSIHtmlEncoded -Value $Properties.CheckViewId
    foreach ($Category in $A.Categories) {
        $CategoryName = ConvertTo-PSIHtmlEncoded -Value $Category.Name
        $CategoryId = ConvertTo-PSIHtmlEncoded -Value $Category.Id
        $CategoryScore = if ($null -eq $Category.Score) { 'N/A' } else { "$($Category.Score)%" }
        $CategoryProgress = if ($null -eq $Category.Score) { 0 } else { [double] $Category.Score }
        $IconMarkup = Get-PSIIcon -Name $Category.Icon -Size 19
        $CheckCount = @($Category.CheckIds).Count
        $CategoryStatus = ConvertTo-PSIHtmlEncoded -Value $Category.Status
        $CategoryClass = switch ([string] $Category.Status) { Ready { 'healthy' } Review { 'warning' } Blocked { 'critical' } NotTested { 'not-checked' } default { 'neutral' } }
        $CategoryCounts = @($A.ScoreExplanation.CategoryScores | Where-Object { $_.Id -eq $Category.Id } | Select-Object -First 1)
        $CategoryCountText = if ($CategoryCounts.Count -gt 0) { "$($CategoryCounts[0].Counts.Ready) Ready | $($CategoryCounts[0].Counts.Review) Review | $($CategoryCounts[0].Counts.Blocked) Blocked | $($CategoryCounts[0].Counts.NotTested) Not Tested" } else { "$CheckCount checks" }
        $SafeCountText = ConvertTo-PSIHtmlEncoded -Value $CategoryCountText
        [void] $B.AppendLine("<button type=`"button`" class=`"psi-assessment-category psi-status-$CategoryClass`" data-psi-category-target=`"$CheckView`" data-psi-category-id=`"$CategoryId`" aria-label=`"$CategoryName, $CategoryScore, $CategoryStatus, $SafeCountText. View checks`"><span class=`"psi-assessment-category-icon`">$IconMarkup</span><span class=`"psi-assessment-category-copy`"><strong>$CategoryName</strong><small>$SafeCountText</small><span class=`"psi-assessment-progress`" style=`"--psi-progress:$CategoryProgress`"></span></span><span class=`"psi-assessment-category-result`"><strong>$CategoryScore</strong><small>$CategoryStatus</small></span></button>")
    }
    [void] $B.AppendLine('</div></section><section class="psi-assessment-panel"><header><h4>Why this decision</h4><span>Score and verdict</span></header><ul class="psi-assessment-reasons">')
    foreach ($Reason in $A.ScoreExplanation.Reasons) { [void] $B.AppendLine('<li>' + (ConvertTo-PSIHtmlEncoded -Value $Reason) + '</li>') }
    [void] $B.AppendLine('</ul><p class="psi-assessment-explanation">Ready = 100 points; Review = 50; Blocked, Not Tested and Unknown = 0. Not Applicable is excluded. Applicable check scores are weighted within each category, then category scores are weighted overall. The decision is evaluated separately.</p></section></div>')
    [void] $B.AppendLine('<div class="psi-assessment-overview-grid"><section class="psi-assessment-panel"><header><h4>Top blockers</h4><span>Action required</span></header><div class="psi-assessment-actions">')
    foreach ($Check in @($A.Checks | Where-Object { $_.Status -eq 'Blocked' -or ($_.IsBlocking -and $_.Status -eq 'Review') } | Select-Object -First 5)) {
        $Title = ConvertTo-PSIHtmlEncoded -Value $Check.Name
        $Id = ConvertTo-PSIHtmlEncoded -Value $Check.Id
        [void] $B.AppendLine("<button type=`"button`" data-psi-cross-view=`"$CheckView`" data-psi-cross-id=`"$Id`">$Title <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $B.AppendLine('</div></section><section class="psi-assessment-panel"><header><h4>Priority findings</h4><span>Linked evidence</span></header><div class="psi-assessment-actions">')
    $FindingView = ConvertTo-PSIHtmlEncoded -Value $Properties.FindingViewId
    $FindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @($A.FindingIds)) { [void] $FindingIds.Add([string] $Id) }
    foreach ($Finding in @($Model.Findings | Where-Object { $FindingIds.Contains([string] $_.Id) -and $_.Status -notin @('Resolved','AcceptedRisk','NotApplicable') } | Sort-Object { switch ($_.Severity) { Critical { 0 } Warning { 1 } default { 2 } } } | Select-Object -First 5)) {
        $Title = ConvertTo-PSIHtmlEncoded -Value $Finding.Title
        $Id = ConvertTo-PSIHtmlEncoded -Value $Finding.Id
        [void] $B.AppendLine("<button type=`"button`" data-psi-cross-view=`"$FindingView`" data-psi-cross-id=`"$Id`">$Title <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $B.AppendLine('</div></section></div>')
    $Scope = ConvertTo-PSIHtmlEncoded -Value $A.Scope
    [void] $B.AppendLine("<div class=`"psi-assessment-overview-grid`"><section class=`"psi-assessment-panel`"><header><h4>Recommended next actions</h4><span>Provider supplied</span></header><ul class=`"psi-assessment-reasons`">")
    foreach ($Recommendation in @($A.Recommendations)) { [void] $B.AppendLine('<li>' + (ConvertTo-PSIHtmlEncoded -Value $Recommendation) + '</li>') }
    [void] $B.AppendLine("</ul></section><section class=`"psi-assessment-panel`"><header><h4>Scope &amp; evidence</h4><span>Assessment coverage</span></header><p>$Scope</p><p>$(@($A.ResourceIds).Count) linked resources &middot; $(@($A.EvidenceIds).Count) linked evidence records &middot; $($Counts.NotApplicable) not applicable checks</p></section></div></section>")
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIChartMarkup.ps1
function ConvertTo-PSIChartMarkup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [hashtable] $Properties
    )

    $ChartType = [string] $Properties['ChartType']
    if ($ChartType -notin @('Bar', 'Line', 'Doughnut', 'Pie')) {
        throw "Unsupported chart type '$ChartType'."
    }

    $Width = [int] $Properties['Width']
    $Height = [int] $Properties['Height']
    $Title = [System.Net.WebUtility]::HtmlEncode([string] $Properties['Title'])
    $Data = @($Properties['Data'])
    $CategoryProperty = [string] $Properties['CategoryProperty']
    $ValueProperty = [string] $Properties['ValueProperty']
    $SeriesProperty = [string] $Properties['SeriesProperty']
    $StatusProperty = [string] $Properties['StatusProperty']
    $ShowLabels = [bool] $Properties['ShowLabels']
    $ShowLegend = [bool] $Properties['ShowLegend']
    $EmptyMessage = [System.Net.WebUtility]::HtmlEncode([string] $Properties['EmptyMessage'])
    $FilterMetadata = $Properties['FilterMetadata']

    $Categories = [System.Collections.Generic.List[string]]::new()
    $CategoryIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $Series = [System.Collections.Generic.List[object]]::new()
    $SeriesIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $PointCount = 0
    $NullValueCount = 0
    $FilterValueByCategory = @{}
    $AmbiguousFilterCategories = @{}

    if ($FilterMetadata -is [hashtable] -and $FilterMetadata.Count -gt 0) {
        $FilterValueProperty = [string] $FilterMetadata['ValueProperty']
        foreach ($Item in $Data) {
            $RawCategory = Get-PSITableValue -InputObject $Item -Name $CategoryProperty
            if ($null -eq $RawCategory) { $Category = 'Not specified' }
            elseif ($RawCategory -is [string] -or $RawCategory.GetType().IsValueType) { $Category = [string] $RawCategory }
            else { $Category = ConvertTo-Json -InputObject $RawCategory -Depth 5 -Compress }

            $RawFilterValue = Get-PSITableValue -InputObject $Item -Name $FilterValueProperty
            if ($null -eq $RawFilterValue) { continue }
            if ($RawFilterValue -is [string] -or $RawFilterValue.GetType().IsValueType) {
                $FilterValue = [string] $RawFilterValue
            }
            else {
                $FilterValue = ConvertTo-Json -InputObject $RawFilterValue -Depth 5 -Compress
            }
            if ($FilterValueByCategory.ContainsKey($Category) -and
                -not [string]::Equals([string] $FilterValueByCategory[$Category], $FilterValue, [System.StringComparison]::Ordinal)) {
                $AmbiguousFilterCategories[$Category] = $true
            }
            else {
                $FilterValueByCategory[$Category] = $FilterValue
            }
        }
    }

    $GetFilterAttributes = {
        param([string] $Category)
        if (-not ($FilterMetadata -is [hashtable]) -or $FilterMetadata.Count -eq 0 -or
            -not $FilterValueByCategory.ContainsKey($Category) -or $AmbiguousFilterCategories.ContainsKey($Category)) {
            return ''
        }
        $FilterAction = @{
            tableId  = [string] $FilterMetadata['Table']
            property = [string] $FilterMetadata['Property']
            value    = [string] $FilterValueByCategory[$Category]
        }
        $FilterJson = ConvertTo-Json -InputObject $FilterAction -Compress -Depth 4
        $SafeFilterJson = [System.Net.WebUtility]::HtmlEncode($FilterJson)
        $SafeAriaLabel = [System.Net.WebUtility]::HtmlEncode("Filter table by $($FilterMetadata['Property']): $($FilterValueByCategory[$Category])")
        " role=`"button`" tabindex=`"0`" aria-label=`"$SafeAriaLabel`" data-psi-chart-filter=`"$SafeFilterJson`""
    }

    foreach ($Item in $Data) {
        $RawCategory = Get-PSITableValue -InputObject $Item -Name $CategoryProperty
        if ($null -eq $RawCategory) {
            $Category = 'Not specified'
        }
        elseif ($RawCategory -is [string] -or $RawCategory.GetType().IsValueType) {
            $Category = [string] $RawCategory
        }
        else {
            $Category = ConvertTo-Json -InputObject $RawCategory -Depth 5 -Compress
        }

        if (-not $CategoryIndex.ContainsKey($Category)) {
            $CategoryIndex.Add($Category, $Categories.Count)
            $Categories.Add($Category)
        }

        if ([string]::IsNullOrWhiteSpace($SeriesProperty)) {
            $SeriesName = $ValueProperty
        }
        else {
            $RawSeriesName = Get-PSITableValue -InputObject $Item -Name $SeriesProperty
            if ($null -eq $RawSeriesName) {
                $SeriesName = 'Unspecified series'
            }
            elseif ($RawSeriesName -is [string] -or $RawSeriesName.GetType().IsValueType) {
                $SeriesName = [string] $RawSeriesName
            }
            else {
                $SeriesName = ConvertTo-Json -InputObject $RawSeriesName -Depth 5 -Compress
            }
        }

        if (-not $SeriesIndex.ContainsKey($SeriesName)) {
            $SeriesIndex.Add($SeriesName, $Series.Count)
            $Series.Add([pscustomobject]@{
                Name     = $SeriesName
                Values   = @{}
                Statuses = @{}
            })
        }

        $RawValue = Get-PSITableValue -InputObject $Item -Name $ValueProperty
        $Number = $null
        if ($null -eq $RawValue) {
            $NullValueCount++
        }
        else {
            try {
                $Number = [System.Convert]::ToDouble($RawValue, [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                throw "Chart value '$ValueProperty' must contain numeric values or null. Found '$RawValue'."
            }
            $PointCount++
        }

        $PointStatus = $null
        if (-not [string]::IsNullOrWhiteSpace($StatusProperty)) {
            $RawStatus = Get-PSITableValue -InputObject $Item -Name $StatusProperty
            $PointStatus = Resolve-PSIStatus -Status ([string] $RawStatus) -AllowInvalid
        }
        if ($null -eq $PointStatus) {
            $PointStatus = Resolve-PSIStatus -Status $Category -AllowInvalid
        }

        $SeriesItem = $Series[$SeriesIndex[$SeriesName]]
        if ($SeriesItem.Values.ContainsKey($Category) -and $null -ne $Number) {
            $ExistingValue = $SeriesItem.Values[$Category]
            if ($null -eq $ExistingValue) {
                $SeriesItem.Values[$Category] = $Number
            }
            else {
                $SeriesItem.Values[$Category] = [double] $ExistingValue + $Number
            }
        }
        elseif (-not $SeriesItem.Values.ContainsKey($Category)) {
            $SeriesItem.Values[$Category] = $Number
        }
        if ($null -ne $PointStatus) {
            $SeriesItem.Statuses[$Category] = $PointStatus
        }
    }

    $Palette = @(
        'var(--psi-chart-1)'
        'var(--psi-chart-2)'
        'var(--psi-chart-3)'
        'var(--psi-chart-4)'
        'var(--psi-chart-5)'
        'var(--psi-chart-6)'
        'var(--psi-chart-7)'
        'var(--psi-chart-8)'
    )

    $GetColor = {
        param([int] $Index, [string] $Status)
        if ($Status -and $PSIStatusValues -contains $Status) {
            $StatusToken = $Status.ToLowerInvariant()
            if ($Status -eq 'NotChecked') {
                $StatusToken = 'not-checked'
            }
            return "var(--psi-status-$StatusToken)"
        }
        $Palette[$Index % $Palette.Count]
    }

    $GetPoint = {
        param([double] $CenterX, [double] $CenterY, [double] $Radius, [double] $Angle)
        $Radians = ($Angle * [math]::PI) / 180
        [pscustomobject]@{
            X = [int] [math]::Round($CenterX + ($Radius * [math]::Cos($Radians)))
            Y = [int] [math]::Round($CenterY + ($Radius * [math]::Sin($Radians)))
        }
    }

    $Svg = [System.Text.StringBuilder]::new()
    $LegendItems = [System.Collections.Generic.List[object]]::new()
    $SvgRole = if ($FilterMetadata -is [hashtable] -and $FilterMetadata.Count -gt 0) { 'group' } else { 'img' }
    [void] $Svg.AppendLine("<svg class=`"psi-chart-svg`" viewBox=`"0 0 $Width $Height`" role=`"$SvgRole`" aria-label=`"$Title`" xmlns=`"http://www.w3.org/2000/svg`">")
    [void] $Svg.AppendLine("  <title>$Title</title>")

    $RenderablePoints = 0
    foreach ($SeriesItem in $Series) {
        foreach ($Category in $Categories) {
            if ($SeriesItem.Values.ContainsKey($Category) -and $null -ne $SeriesItem.Values[$Category]) {
                $RenderablePoints++
            }
        }
    }

    if ($PointCount -eq 0 -or $RenderablePoints -eq 0) {
        [void] $Svg.AppendLine("  <text class=`"psi-chart-empty-text`" x=`"$([int]($Width / 2))`" y=`"$([int]($Height / 2))`" text-anchor=`"middle`">$EmptyMessage</text>")
        [void] $Svg.AppendLine('</svg>')
        return [pscustomobject]@{
            Svg            = $Svg.ToString()
            Legend          = ''
            DataPointCount  = 0
            NullValueCount  = $NullValueCount
        }
    }

    if ($ChartType -in @('Doughnut', 'Pie')) {
        if ($Series.Count -gt 1) {
            $AggregateValues = @{}
            $AggregateStatuses = @{}
            foreach ($SeriesItem in $Series) {
                foreach ($Category in $Categories) {
                    if (-not $SeriesItem.Values.ContainsKey($Category) -or $null -eq $SeriesItem.Values[$Category]) {
                        continue
                    }
                    $AggregateValues[$Category] = [double] $AggregateValues[$Category] + [double] $SeriesItem.Values[$Category]
                    if ($SeriesItem.Statuses.ContainsKey($Category)) {
                        $AggregateStatuses[$Category] = $SeriesItem.Statuses[$Category]
                    }
                }
            }
        }
        else {
            $AggregateValues = $Series[0].Values
            $AggregateStatuses = $Series[0].Statuses
        }

        $Total = 0.0
        foreach ($Category in $Categories) {
            if ($AggregateValues.ContainsKey($Category)) {
                $Value = [double] $AggregateValues[$Category]
                if ($Value -lt 0) {
                    throw "Chart type '$ChartType' requires non-negative values. Category '$Category' has value '$Value'."
                }
                $Total += $Value
            }
        }

        if ($Total -le 0) {
            [void] $Svg.AppendLine("  <text class=`"psi-chart-empty-text`" x=`"$([int]($Width / 2))`" y=`"$([int]($Height / 2))`" text-anchor=`"middle`">$EmptyMessage</text>")
            [void] $Svg.AppendLine('</svg>')
            return [pscustomobject]@{
                Svg            = $Svg.ToString()
                Legend          = ''
                DataPointCount  = 0
                NullValueCount  = $NullValueCount
            }
        }

        $CenterX = [int] ($Width / 2)
        $CenterY = [int] ($Height / 2)
        $OuterRadius = [int] ([math]::Min(($Width * 0.25), ($Height * 0.39)))
        $InnerRadius = if ($ChartType -eq 'Doughnut') { [int] ($OuterRadius * 0.58) } else { 0 }
        $Angle = -90.0
        $SliceIndex = 0
        foreach ($Category in $Categories) {
            if (-not $AggregateValues.ContainsKey($Category)) {
                continue
            }
            $Value = [double] $AggregateValues[$Category]
            if ($Value -le 0) {
                continue
            }
            $Sweep = ($Value / $Total) * 360.0
            $ColorStatus = if ($AggregateStatuses.ContainsKey($Category)) { [string] $AggregateStatuses[$Category] } else { $null }
            if ($null -eq $ColorStatus) {
                $ColorStatus = Resolve-PSIStatus -Status $Category -AllowInvalid
            }
            $Color = & $GetColor $SliceIndex $ColorStatus
            $SafeCategory = [System.Net.WebUtility]::HtmlEncode($Category)
            $SafeValue = [System.Net.WebUtility]::HtmlEncode([string] $Value)
            $FilterAttributes = & $GetFilterAttributes $Category

            if ($Sweep -ge 359.999) {
                $PointClass = if ($FilterAttributes) { ' class="psi-chart-filter-point"' } else { '' }
                [void] $Svg.AppendLine("  <circle$PointClass$FilterAttributes cx=`"$CenterX`" cy=`"$CenterY`" r=`"$OuterRadius`" fill=`"$Color`"><title>${SafeCategory}: $SafeValue</title></circle>")
                if ($InnerRadius -gt 0) {
                    [void] $Svg.AppendLine("  <circle cx=`"$CenterX`" cy=`"$CenterY`" r=`"$InnerRadius`" fill=`"var(--psi-surface)`" />")
                }
            }
            else {
                $Start = & $GetPoint $CenterX $CenterY $OuterRadius $Angle
                $End = & $GetPoint $CenterX $CenterY $OuterRadius ($Angle + $Sweep)
                $LargeArc = if ($Sweep -gt 180) { 1 } else { 0 }
                if ($InnerRadius -gt 0) {
                    $InnerEnd = & $GetPoint $CenterX $CenterY $InnerRadius ($Angle + $Sweep)
                    $InnerStart = & $GetPoint $CenterX $CenterY $InnerRadius $Angle
                    $PathData = "M $($Start.X) $($Start.Y) A $OuterRadius $OuterRadius 0 $LargeArc 1 $($End.X) $($End.Y) L $($InnerEnd.X) $($InnerEnd.Y) A $InnerRadius $InnerRadius 0 $LargeArc 0 $($InnerStart.X) $($InnerStart.Y) Z"
                }
                else {
                    $PathData = "M $CenterX $CenterY L $($Start.X) $($Start.Y) A $OuterRadius $OuterRadius 0 $LargeArc 1 $($End.X) $($End.Y) Z"
                }
                $PointClass = if ($FilterAttributes) { ' class="psi-chart-filter-point"' } else { '' }
                [void] $Svg.AppendLine("  <path$PointClass$FilterAttributes d=`"$PathData`" fill=`"$Color`"><title>${SafeCategory}: $SafeValue</title></path>")
            }

            if ($ShowLabels) {
                $MidAngle = $Angle + ($Sweep / 2)
                $LabelRadius = if ($InnerRadius -gt 0) { ($InnerRadius + $OuterRadius) / 2 } else { $OuterRadius * 0.66 }
                $LabelPoint = & $GetPoint $CenterX $CenterY $LabelRadius $MidAngle
                $PercentText = [System.Net.WebUtility]::HtmlEncode(('{0:0.#}%' -f (($Value / $Total) * 100)))
                [void] $Svg.AppendLine("  <text class=`"psi-chart-data-label`" x=`"$($LabelPoint.X)`" y=`"$($LabelPoint.Y)`" text-anchor=`"middle`">$PercentText</text>")
            }

            $LegendItems.Add([pscustomobject]@{
                Label  = $Category
                Color  = $Color
                Value  = $Value
            })
            $Angle += $Sweep
            $SliceIndex++
        }
    }
    else {
        $Left = 64
        $Right = 22
        $Top = 20
        $Bottom = 62
        $PlotWidth = $Width - $Left - $Right
        $PlotHeight = $Height - $Top - $Bottom
        $Minimum = 0.0
        $Maximum = 0.0
        foreach ($SeriesItem in $Series) {
            foreach ($Category in $Categories) {
                if ($SeriesItem.Values.ContainsKey($Category) -and $null -ne $SeriesItem.Values[$Category]) {
                    $Value = [double] $SeriesItem.Values[$Category]
                    $Minimum = [math]::Min($Minimum, $Value)
                    $Maximum = [math]::Max($Maximum, $Value)
                }
            }
        }
        if ($Maximum -eq $Minimum) {
            $Maximum = $Minimum + 1
        }
        $Scale = $Maximum - $Minimum
        $GetY = {
            param([double] $Value)
            [int] [math]::Round($Top + (($Maximum - $Value) / $Scale * $PlotHeight))
        }
        $ZeroY = & $GetY ([math]::Max($Minimum, [math]::Min($Maximum, 0.0)))

        for ($Tick = 0; $Tick -le 4; $Tick++) {
            $TickValue = $Minimum + ($Scale * $Tick / 4)
            $Y = & $GetY $TickValue
            $TickLabel = [System.Net.WebUtility]::HtmlEncode(('{0:0.##}' -f $TickValue))
            [void] $Svg.AppendLine("  <line x1=`"$Left`" y1=`"$Y`" x2=`"$($Width - $Right)`" y2=`"$Y`" stroke=`"var(--psi-chart-grid)`" />")
            [void] $Svg.AppendLine("  <text class=`"psi-chart-axis-label`" x=`"$($Left - 10)`" y=`"$($Y + 4)`" text-anchor=`"end`">$TickLabel</text>")
        }
        [void] $Svg.AppendLine("  <line x1=`"$Left`" y1=`"$Top`" x2=`"$Left`" y2=`"$($Height - $Bottom)`" stroke=`"var(--psi-chart-axis)`" />")
        [void] $Svg.AppendLine("  <line x1=`"$Left`" y1=`"$ZeroY`" x2=`"$($Width - $Right)`" y2=`"$ZeroY`" stroke=`"var(--psi-chart-axis)`" />")

        $CategoryWidth = $PlotWidth / [math]::Max(1, $Categories.Count)
        for ($CategoryIndex = 0; $CategoryIndex -lt $Categories.Count; $CategoryIndex++) {
            $Category = $Categories[$CategoryIndex]
            $X = [int] [math]::Round($Left + ($CategoryWidth * ($CategoryIndex + 0.5)))
            $LabelText = $Category
            if ($LabelText.Length -gt 18) {
                $LabelText = $LabelText.Substring(0, 17) + [char] 0x2026
            }
            $SafeLabel = [System.Net.WebUtility]::HtmlEncode($LabelText)
            $SafeTitle = [System.Net.WebUtility]::HtmlEncode($Category)
            [void] $Svg.AppendLine("  <text class=`"psi-chart-axis-label`" x=`"$X`" y=`"$($Height - 28)`" text-anchor=`"middle`"><title>$SafeTitle</title>$SafeLabel</text>")
        }

        for ($SeriesNumber = 0; $SeriesNumber -lt $Series.Count; $SeriesNumber++) {
            $SeriesItem = $Series[$SeriesNumber]
            $SeriesName = [System.Net.WebUtility]::HtmlEncode([string] $SeriesItem.Name)
            $SeriesColor = & $GetColor $SeriesNumber $null
            $LegendItems.Add([pscustomobject]@{
                Label = [string] $SeriesItem.Name
                Color = $SeriesColor
                Value = $null
            })

            if ($ChartType -eq 'Bar') {
                $GroupWidth = $CategoryWidth * 0.76
                $BarWidth = [math]::Max(1, $GroupWidth / [math]::Max(1, $Series.Count))
                for ($CategoryIndex = 0; $CategoryIndex -lt $Categories.Count; $CategoryIndex++) {
                    $Category = $Categories[$CategoryIndex]
                    if (-not $SeriesItem.Values.ContainsKey($Category) -or $null -eq $SeriesItem.Values[$Category]) {
                        continue
                    }
                    $Value = [double] $SeriesItem.Values[$Category]
                    $ValueY = & $GetY $Value
                    $BarX = [int] [math]::Round($Left + ($CategoryWidth * $CategoryIndex) + (($CategoryWidth - $GroupWidth) / 2) + ($SeriesNumber * $BarWidth))
                    $BarY = [int] [math]::Min($ZeroY, $ValueY)
                    $BarHeight = [math]::Max(1, [int] [math]::Abs($ZeroY - $ValueY))
                    $Status = if ($SeriesItem.Statuses.ContainsKey($Category)) { [string] $SeriesItem.Statuses[$Category] } else { $null }
                    $Color = & $GetColor $SeriesNumber $Status
                    $SafeValue = [System.Net.WebUtility]::HtmlEncode([string] $Value)
                    $SafeTitle = [System.Net.WebUtility]::HtmlEncode($Category)
                    $FilterAttributes = & $GetFilterAttributes $Category
                    $PointClass = if ($FilterAttributes) { ' class="psi-chart-filter-point"' } else { '' }
                    [void] $Svg.AppendLine("  <rect$PointClass$FilterAttributes x=`"$BarX`" y=`"$BarY`" width=`"$([int][math]::Ceiling($BarWidth - 3))`" height=`"$BarHeight`" rx=`"4`" fill=`"$Color`"><title>${SafeTitle}: $SafeValue</title></rect>")
                    if ($ShowLabels) {
                        [void] $Svg.AppendLine("  <text class=`"psi-chart-data-label`" x=`"$([int]($BarX + ($BarWidth / 2)))`" y=`"$([int]($BarY - 6))`" text-anchor=`"middle`">$SafeValue</text>")
                    }
                }
            }
            else {
                $PathBuilder = [System.Text.StringBuilder]::new()
                $SegmentHasPoint = $false
                for ($CategoryIndex = 0; $CategoryIndex -lt $Categories.Count; $CategoryIndex++) {
                    $Category = $Categories[$CategoryIndex]
                    if (-not $SeriesItem.Values.ContainsKey($Category) -or $null -eq $SeriesItem.Values[$Category]) {
                        $SegmentHasPoint = $false
                        continue
                    }
                    $Value = [double] $SeriesItem.Values[$Category]
                    $PointX = [int] [math]::Round($Left + ($CategoryWidth * ($CategoryIndex + 0.5)))
                    $PointY = & $GetY $Value
                    if ($SegmentHasPoint) {
                        [void] $PathBuilder.Append(" L $PointX $PointY")
                    }
                    else {
                        [void] $PathBuilder.Append(" M $PointX $PointY")
                        $SegmentHasPoint = $true
                    }
                    $Status = if ($SeriesItem.Statuses.ContainsKey($Category)) { [string] $SeriesItem.Statuses[$Category] } else { $null }
                    $PointColor = & $GetColor $SeriesNumber $Status
                    $FilterAttributes = & $GetFilterAttributes $Category
                    $PointClass = if ($FilterAttributes) { 'psi-chart-point psi-chart-filter-point' } else { 'psi-chart-point' }
                    [void] $Svg.AppendLine("  <circle class=`"$PointClass`"$FilterAttributes cx=`"$PointX`" cy=`"$PointY`" r=`"5`" fill=`"$PointColor`" stroke=`"var(--psi-surface)`" stroke-width=`"2`"><title>$($SeriesName): $([System.Net.WebUtility]::HtmlEncode($Category)) $([System.Net.WebUtility]::HtmlEncode([string]$Value))</title></circle>")
                    if ($ShowLabels) {
                        $SafeValue = [System.Net.WebUtility]::HtmlEncode([string] $Value)
                        [void] $Svg.AppendLine("  <text class=`"psi-chart-data-label`" x=`"$PointX`" y=`"$($PointY - 10)`" text-anchor=`"middle`">$SafeValue</text>")
                    }
                }
                if ($PathBuilder.Length -gt 0) {
                    [void] $Svg.AppendLine("  <path d=`"$($PathBuilder.ToString().Trim())`" fill=`"none`" stroke=`"$SeriesColor`" stroke-width=`"3`" stroke-linecap=`"round`" stroke-linejoin=`"round`" />")
                }
            }
        }
    }

    [void] $Svg.AppendLine('</svg>')
    $LegendMarkup = ''
    if ($ShowLegend -and $LegendItems.Count -gt 0) {
        $LegendBuilder = [System.Text.StringBuilder]::new()
        [void] $LegendBuilder.AppendLine('<ul class="psi-chart-legend" aria-label="Chart legend">')
        foreach ($LegendItem in $LegendItems) {
            $LegendLabel = [System.Net.WebUtility]::HtmlEncode([string] $LegendItem.Label)
            $LegendColor = [System.Net.WebUtility]::HtmlEncode([string] $LegendItem.Color)
            $LegendValue = if ($null -ne $LegendItem.Value) { ' ' + [System.Net.WebUtility]::HtmlEncode([string] $LegendItem.Value) } else { '' }
            [void] $LegendBuilder.AppendLine("  <li><span class=`"psi-chart-legend-swatch`" style=`"--psi-chart-swatch: $LegendColor`" aria-hidden=`"true`"></span>$LegendLabel$LegendValue</li>")
        }
        [void] $LegendBuilder.AppendLine('</ul>')
        $LegendMarkup = $LegendBuilder.ToString()
    }

    [pscustomobject]@{
        Svg           = $Svg.ToString()
        Legend        = $LegendMarkup
        DataPointCount = $PointCount
        NullValueCount = $NullValueCount
    }
}
#endregion

#region Private/ConvertTo-PSICssString.ps1
function ConvertTo-PSICssString {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][string] $Value)
    if ($null -eq $Value) { return '' }
    $Clean = $Value.Replace([char] 13, ' ').Replace([char] 10, ' ').Replace([char] 9, ' ')
    if ($Clean.Length -gt 90) { $Clean = $Clean.Substring(0, 87) + '...' }
    $B = [System.Text.StringBuilder]::new()
    for ($I = 0; $I -lt $Clean.Length; $I++) {
        $CodePoint = [int] [char] $Clean[$I]
        if ([char]::IsHighSurrogate($Clean[$I]) -and $I + 1 -lt $Clean.Length -and [char]::IsLowSurrogate($Clean[$I + 1])) {
            $CodePoint = [char]::ConvertToUtf32($Clean[$I], $Clean[$I + 1])
            $I++
        }
        [void] $B.Append('\')
        [void] $B.Append($CodePoint.ToString('x'))
        [void] $B.Append(' ')
    }
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIExplorerHtml.ps1
function ConvertTo-PSIExplorerHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Properties)

    $Id = [string] $Properties.Id
    if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Explorer ID '$Id' is invalid." }
    $Title = ConvertTo-PSIHtmlEncoded -Value $Properties.Title
    $Empty = ConvertTo-PSIHtmlEncoded -Value $Properties.EmptyMessage
    $Data = @($Properties.Data)
    $EntityType = [string] $Properties.EntityType
    $FilterMarkup = [System.Text.StringBuilder]::new()
    foreach ($FilterProperty in @($Properties.FilterProperties)) {
        $SafeProperty = ConvertTo-PSIHtmlEncoded -Value $FilterProperty
        $SafeLabel = ConvertTo-PSIHtmlEncoded -Value (([string] $FilterProperty) -creplace '([a-z])([A-Z])', '$1 $2')
        [void] $FilterMarkup.Append("<label>$SafeLabel<select data-psi-explorer-filter=`"$SafeProperty`"><option value=`"`">All</option>")
        $Values = @($Data | ForEach-Object { Get-PSITableValue -InputObject $_ -Name ([string] $FilterProperty) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) } | Sort-Object -Unique)
        foreach ($Value in $Values) {
            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $Value
            [void] $FilterMarkup.Append("<option value=`"$SafeValue`">$SafeValue</option>")
        }
        [void] $FilterMarkup.Append('</select></label>')
    }
    $Labels = $Properties.ColumnLabels
    $Details = @($Properties.DetailProperties)
    if ($Details.Count -eq 0 -and $Data.Count -gt 0) {
        if ($Data[0] -is [System.Collections.IDictionary]) { $Details = @($Data[0].Keys) }
        else { $Details = @($Data[0].PSObject.Properties.Name) }
    }
    $List = [System.Text.StringBuilder]::new()
    $Panels = [System.Text.StringBuilder]::new()
    for ($Index = 0; $Index -lt $Data.Count; $Index++) {
        $Record = $Data[$Index]
        $RawTitle = Get-PSITableValue -InputObject $Record -Name ([string] $Properties.TitleProperty)
        $RawSubtitle = if ($Properties.SubtitleProperty) { Get-PSITableValue -InputObject $Record -Name ([string] $Properties.SubtitleProperty) } else { '' }
        $RawStatus = if ($Properties.StatusProperty) { Get-PSITableValue -InputObject $Record -Name ([string] $Properties.StatusProperty) } else { '' }
        $Name = if ($null -eq $RawTitle -or [string]::IsNullOrWhiteSpace([string] $RawTitle)) { '(unnamed)' } else { [string] $RawTitle }
        $SafeName = ConvertTo-PSIHtmlEncoded -Value $Name
        $SafeSubtitle = ConvertTo-PSIHtmlEncoded -Value $RawSubtitle
        $CanonicalStatus = if ($EntityType -in @('Check','Category') -and $RawStatus) { Resolve-PSIAssessmentStatus -Status ([string] $RawStatus) }
            elseif ($EntityType -eq 'Exception' -and $RawStatus) { switch ([string] $RawStatus) { Approved { 'Informational' } Pending { 'Warning' } Expired { 'Critical' } Revoked { 'Neutral' } } }
            else { Resolve-PSIStatus -Status ([string] $RawStatus) -AllowInvalid }
        $Badge = ''
        if ($CanonicalStatus) {
            $Suffix = if ($CanonicalStatus -eq 'NotChecked') { 'not-checked' } else { $CanonicalStatus.ToLowerInvariant() }
            $SafeStatus = ConvertTo-PSIHtmlEncoded -Value $CanonicalStatus
            $DisplayStatus = if ($EntityType -in @('Check','Category','Exception')) { ConvertTo-PSIHtmlEncoded -Value $RawStatus } else { $SafeStatus }
            $Badge = "<span class=`"psi-status-badge psi-status-$Suffix`">$DisplayStatus</span>"
        }
        $Selected = if ($Index -eq 0) { ' aria-selected="true" tabindex="0"' } else { ' aria-selected="false" tabindex="-1"' }
        $EntityAttribute = if ($EntityType) { ' data-psi-entity-id="' + (ConvertTo-PSIHtmlEncoded -Value $Record.Id) + '"' } else { '' }
        if ($EntityType -eq 'Check') { $EntityAttribute += ' data-psi-category-id="' + (ConvertTo-PSIHtmlEncoded -Value $Record.CategoryId) + '"' }
        foreach ($FilterProperty in @($Properties.FilterProperties)) {
            $AttributeName = ([string] $FilterProperty).ToLowerInvariant()
            $EntityAttribute += ' data-psi-filter-' + $AttributeName + '="' + (ConvertTo-PSIHtmlEncoded -Value (Get-PSITableValue -InputObject $Record -Name ([string] $FilterProperty))) + '"'
        }
        [void] $List.AppendLine("<button type=`"button`" class=`"psi-app-explorer-item`" id=`"$Id-item-$Index`" role=`"tab`" data-psi-explorer-item=`"$Index`" aria-controls=`"$Id-detail-$Index`"$EntityAttribute$Selected><span class=`"psi-app-explorer-item-copy`"><strong>$SafeName</strong><small>$SafeSubtitle</small></span>$Badge</button>")
        $Hidden = if ($Index -eq 0) { '' } else { ' hidden' }
        [void] $Panels.AppendLine("<article class=`"psi-app-explorer-detail`" id=`"$Id-detail-$Index`" role=`"tabpanel`" aria-labelledby=`"$Id-item-$Index`" data-psi-explorer-detail=`"$Index`"$Hidden>")
        if ($EntityType -in @('Finding','Resource','Evidence')) {
            [void] $Panels.AppendLine((ConvertTo-PSIIntelligenceDetailHtml -Kind $EntityType -Record $Record -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        elseif ($EntityType -in @('Check','Category')) {
            [void] $Panels.AppendLine((ConvertTo-PSIAssessmentDetailHtml -Kind $EntityType -Record $Record -Assessment $Properties.Assessment -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        elseif ($EntityType -eq 'Exception') {
            [void] $Panels.AppendLine((ConvertTo-PSIAssessmentExceptionHtml -Record $Record -Assessment $Properties.Assessment -Model $Properties.Model -LinkViews $Properties.LinkViews))
        }
        else {
            [void] $Panels.AppendLine("<p class=`"psi-app-explorer-detail-eyebrow`">Selected record</p><h4>$SafeName</h4><dl>")
            foreach ($PropertyName in $Details) {
                $Label = if ($Labels.ContainsKey($PropertyName)) { [string] $Labels[$PropertyName] } else { ([string] $PropertyName -creplace '([a-z])([A-Z])', '$1 $2') }
                $Value = Get-PSITableValue -InputObject $Record -Name ([string] $PropertyName)
                if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { $ValueText = [string] [char] 0x2014 }
                elseif ($Value -is [string] -or $Value.GetType().IsValueType) { $ValueText = [string] $Value }
                else { $ValueText = ConvertTo-Json -InputObject $Value -Depth 5 -Compress }
                $SafeLabel = ConvertTo-PSIHtmlEncoded -Value $Label
                $SafeValue = ConvertTo-PSIHtmlEncoded -Value $ValueText
                [void] $Panels.AppendLine("<div><dt>$SafeLabel</dt><dd>$SafeValue</dd></div>")
            }
            [void] $Panels.AppendLine('</dl>')
        }
        [void] $Panels.AppendLine('</article>')
    }
    $Count = $Data.Count
    $EmptyAttribute = if ($Count -eq 0) { '' } else { ' hidden' }
    @"
<section class="psi-app-explorer" id="$Id" data-psi-app-explorer data-psi-entity-type="$EntityType" aria-label="$Title">
  <header class="psi-app-explorer-header"><div><p class="psi-app-explorer-eyebrow">Collection workspace</p><h3>$Title</h3></div><span data-psi-explorer-count aria-live="polite">$Count records</span></header>
  <div class="psi-app-explorer-grid"><div class="psi-app-explorer-master"><label for="$Id-search">Search records</label><input id="$Id-search" type="search" data-psi-explorer-search autocomplete="off" placeholder="Search this collection"><div class="psi-app-explorer-filters">$($FilterMarkup.ToString())</div><div class="psi-app-explorer-list" role="tablist" aria-orientation="vertical" aria-label="$Title records">$($List.ToString())</div><p class="psi-app-explorer-empty" data-psi-explorer-empty$EmptyAttribute>$Empty</p></div><div class="psi-app-explorer-details">$($Panels.ToString())</div></div>
</section>
"@
}
#endregion

#region Private/ConvertTo-PSIFindingId.ps1
function ConvertTo-PSIFindingId {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Id = ''
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        return 'psi-finding-' + [guid]::NewGuid().ToString('N')
    }
    $SafeId = [regex]::Replace($Id.Trim(), '[^A-Za-z0-9_-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($SafeId)) {
        return 'psi-finding-' + [guid]::NewGuid().ToString('N')
    }
    if ($SafeId -notmatch '^[A-Za-z]') { $SafeId = 'psi-finding-' + $SafeId }
    return $SafeId
}
#endregion

#region Private/ConvertTo-PSIFluentHtml.ps1
function ConvertTo-PSIFluentHtml {
    <#
    .SYNOPSIS
    Render a report with the Fluent application renderer.

    .DESCRIPTION
    Runs the same validation as the classic renderer, projects the report into a JSON model
    (ConvertTo-PSIFluentModel) and embeds it with one stylesheet, the shared export helper and
    the Fluent application script into a single standalone HTML file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Report,
        [Parameter()][bool] $EnableReportPrint = $true
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object].'
    }
    if ([string] $Report.Theme -notin @('Light', 'Dark', 'Auto')) { throw "Theme must be Light, Dark, or Auto. Found '$($Report.Theme)'." }
    [void] (Assert-PSIReportIds -Sections $SectionsProperty.Value)
    if ($null -ne $Report.PSObject.Properties['ApplicationModel']) { [void] (Assert-PSIApplicationModel -Model $Report.ApplicationModel) }
    if ($null -ne $Report.PSObject.Properties['ApplicationAssessment']) {
        [void] (Resolve-PSIAssessmentPosture -Assessment $Report.ApplicationAssessment -Model $Report.ApplicationModel)
    }
    if ([string] (Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -eq 'Application') {
        # Validates views, navigation groups and icons exactly as the classic shell does.
        [void] (Resolve-PSIApplicationNavigation -Report $Report)
    }

    $Model = ConvertTo-PSIFluentModel -Report $Report -EnableReportPrint $EnableReportPrint
    $Root = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Assets'
    $Template = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.html'))
    $Css = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.css'))
    $Js = [System.IO.File]::ReadAllText((Join-Path $Root 'Fluent/psi-fluent.js'))
    $ExportJs = [System.IO.File]::ReadAllText((Join-Path $Root 'JavaScript/psi-export.js'))

    # JSON inside <script type="application/json">: neutralise "</", and the two line separators
    # that are valid in JSON but not in older JavaScript parsers.
    $Escape = { param([string] $Text) $Text.Replace('</', '<\/').Replace([string] [char] 0x2028, ('\' + 'u2028')).Replace([string] [char] 0x2029, ('\' + 'u2029')) }
    $Json = & $Escape (ConvertTo-Json -InputObject $Model -Depth 24 -Compress)
    $Icons = & $Escape (ConvertTo-Json -InputObject (Get-PSIFluentIconSet) -Depth 3 -Compress)

    $Template.Replace('{{THEME}}', [string] $Report.Theme).
        Replace('{{VERSION}}', (ConvertTo-PSIHtmlEncoded -Value ([string] $Report.ModuleVersion))).
        Replace('{{TITLE}}', (ConvertTo-PSIHtmlEncoded -Value ([string] $Report.Title))).
        Replace('/*{{CSS}}*/', $Css).
        Replace('{{DATA}}', $Json).
        Replace('{{ICONS}}', $Icons).
        Replace('/*{{EXPORTJS}}*/', $ExportJs).
        Replace('/*{{JS}}*/', $Js)
}

function Test-PSIFluentSupport {
    # Component types and report features the Fluent renderer does not draw yet. Auto
    # rendering falls back to the classic renderer when any are present.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    $Missing = [System.Collections.Generic.List[string]]::new()
    $Supported = @('Text', 'KeyValue', 'KPI', 'Sparkline', 'EmptyState', 'Insight', 'Finding', 'Status', 'Alert', 'Recommendation', 'Table', 'Chart',
        'Explorer', 'AssessmentOverview', 'Tree', 'Topology', 'RelationshipExplorer')
    foreach ($Section in $Report.Sections) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ([string] $Component.Type -notin $Supported -and -not $Missing.Contains([string] $Component.Type)) { $Missing.Add([string] $Component.Type) }
            }
        }
    }
    , $Missing.ToArray()
}
#endregion

#region Private/ConvertTo-PSIFluentModel.ps1
function ConvertTo-PSIFluentModel {
    <#
    .SYNOPSIS
    Project a PSInsightHTML report object into the JSON model consumed by the Fluent renderer.

    .DESCRIPTION
    The model is a clean, de-duplicated projection: every section appears once, tables carry
    their rendered cell text (the same text the classic renderer emits, so evidence filters and
    exports keep their semantics), conditions are evaluated here, and pages/navigation are
    derived from Views, NavigationGroups, composed assessments or plain sections.
    Hot paths (table cells) avoid helper-function calls: per-call binding dominated the classic
    renderer's cost on large tables.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Report,
        [Parameter()][bool] $EnableReportPrint = $true
    )

    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $Sections = @($Report.Sections)
    $StatusMap = @{}
    # Canonical status contract (PSInsightHTML.psm1). Kept local: $script: resolves to the
    # caller's script scope when a provider report script invokes the export.
    $CanonicalStatuses = @('Healthy', 'Warning', 'Critical', 'Informational', 'Neutral', 'Unknown', 'NotChecked')
    foreach ($Value in $CanonicalStatuses) { $StatusMap[$Value] = $Value }
    $StatusMap['Info'] = 'Informational'
    $Unsupported = [System.Collections.Generic.List[string]]::new()

    function Get-FluentStatus([object] $Value, [string] $Default = 'Unknown') {
        if ($null -eq $Value) { return $Default }
        $Key = ([string] $Value).Trim()
        if ($Key -and $StatusMap.ContainsKey($Key)) { return $StatusMap[$Key] }
        return $Default
    }
    function Format-FluentValue([object] $Value) {
        # Same projection as the classic renderer: null -> em dash for display values,
        # strings and value types -> [string], anything else -> compact JSON.
        if ($null -eq $Value) { return $null }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm', $Invariant) }
        if ($Value.GetType().IsValueType) { return [string] $Value }
        return (ConvertTo-Json -InputObject $Value -Depth 5 -Compress)
    }
    function Get-Prop([object] $Object, [string] $Name, [object] $Default = $null) {
        if ($null -eq $Object) { return $Default }
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return , $Object[$Name] }
            foreach ($Key in $Object.Keys) { if ([string]::Equals([string] $Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return , $Object[$Key] } }
            return $Default
        }
        $P = $Object.PSObject.Properties[$Name]
        if ($null -eq $P) { return $Default }
        return , $P.Value
    }
    function Get-PropList([object] $Object, [string] $Name) {
        # List-valued property without null entries (an unset property must not become @($null)).
        $Value = Get-Prop $Object $Name $null
        if ($null -eq $Value) { return , @() }
        if ($Value -is [string] -or $Value -is [System.Collections.IDictionary] -or $Value -isnot [System.Collections.IEnumerable]) { return , @($Value) }
        return , @($Value | Where-Object { $null -ne $_ })
    }
    function ConvertTo-FluentPlain([object] $Value, [int] $Depth = 0) {
        # Records for KPI drill-down / key-value data: plain JSON-safe values with ISO dates.
        if ($null -eq $Value -or $Depth -gt 12) { return $null }
        if ($Value -is [string] -or $Value -is [bool]) { return $Value }
        if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-ddTHH:mm:ssK', $Invariant) }
        if ($Value -is [System.DateTimeOffset]) { return $Value.ToString('yyyy-MM-ddTHH:mm:ssK', $Invariant) }
        if ($Value.GetType().IsPrimitive -or $Value -is [decimal]) { return $Value }
        if ($Value.GetType().IsValueType -or $Value -is [enum]) { return [string] $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $Out = [ordered]@{}
            foreach ($Key in $Value.Keys) { $Out[[string] $Key] = ConvertTo-FluentPlain $Value[$Key] ($Depth + 1) }
            return $Out
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            return , @(foreach ($Item in $Value) { ConvertTo-FluentPlain $Item ($Depth + 1) })
        }
        $Out = [ordered]@{}
        foreach ($P in $Value.PSObject.Properties) {
            if ($P.MemberType -in @('NoteProperty', 'Property', 'AliasProperty')) { $Out[$P.Name] = ConvertTo-FluentPlain $P.Value ($Depth + 1) }
        }
        return $Out
    }

    # ------------------------------------------------------------------ finding anchors (same algorithm as classic)
    $Anchors = Get-PSIFindingAnchors -Sections $Sections
    $AnchorIndex = 0

    # ------------------------------------------------------------------ table conversion
    function ConvertTo-FluentTable([object] $P) {
        $Data = (Get-PropList $P 'Data')
        $Columns = (Get-PropList $P 'Columns')
        if ($Columns.Count -eq 0) { $Columns = @(Get-PSITableColumnNames -Data $Data) }
        $Columns = @($Columns | ForEach-Object { [string] $_ })
        $Labels = Get-Prop $P 'ColumnLabels' @{}
        $LabelOut = [ordered]@{}
        foreach ($Column in $Columns) {
            $Label = $null
            if ($Labels -is [System.Collections.IDictionary] -and $Labels.Contains($Column)) { $Label = [string] $Labels[$Column] }
            $LabelOut[$Column] = if ([string]::IsNullOrWhiteSpace($Label)) { $Column } else { $Label }
        }
        $Conditions = (Get-PropList $P 'Conditions')
        $RowConditions = @($Conditions | Where-Object { [string] (Get-Prop $_ 'Scope' 'Cell') -eq 'Row' })
        $CellConditions = @($Conditions | Where-Object { [string] (Get-Prop $_ 'Scope' 'Cell') -ne 'Row' })
        $CellConditionsByColumn = @{}
        foreach ($Condition in $CellConditions) {
            $Property = [string] (Get-Prop $Condition 'Property')
            for ($Ci = 0; $Ci -lt $Columns.Count; $Ci++) {
                if ([string]::Equals($Columns[$Ci], $Property, [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $CellConditionsByColumn.ContainsKey($Ci)) { $CellConditionsByColumn[$Ci] = [System.Collections.Generic.List[object]]::new() }
                    $CellConditionsByColumn[$Ci].Add($Condition)
                }
            }
        }

        $ColumnCount = $Columns.Count
        $Numeric = New-Object bool[] $ColumnCount
        $NonNull = New-Object int[] $ColumnCount
        $NumericCount = New-Object int[] $ColumnCount
        $Rows = [System.Collections.Generic.List[object]]::new($Data.Count)
        $RowStatus = [ordered]@{}
        $CellStatus = [ordered]@{}
        $RowIndex = 0
        foreach ($Record in $Data) {
            $Cells = New-Object object[] $ColumnCount
            $IsDictionary = $Record -is [System.Collections.IDictionary]
            # Direct assignment: routing the collection through an if-expression would enumerate
            # it into an object[] and break the by-name indexer below.
            $PsProperties = $null
            if (-not $IsDictionary -and $null -ne $Record) { $PsProperties = $Record.PSObject.Properties }
            for ($Ci = 0; $Ci -lt $ColumnCount; $Ci++) {
                $Raw = $null
                if ($IsDictionary) { if ($Record.Contains($Columns[$Ci])) { $Raw = $Record[$Columns[$Ci]] } else { $Raw = Get-Prop $Record $Columns[$Ci] } }
                elseif ($null -ne $PsProperties) { $Prop = $PsProperties[$Columns[$Ci]]; if ($null -ne $Prop) { $Raw = $Prop.Value } }
                if ($null -eq $Raw) { $Cells[$Ci] = $null; continue }
                $NonNull[$Ci]++
                if ($Raw -is [string]) { $Text = $Raw }
                elseif ($Raw -is [bool]) { $Text = [string] $Raw }
                elseif ($Raw.GetType().IsValueType) {
                    $Text = [string] $Raw
                    if ($Raw -is [int] -or $Raw -is [long] -or $Raw -is [double] -or $Raw -is [decimal] -or $Raw -is [single] -or $Raw -is [int16] -or $Raw -is [byte] -or $Raw -is [uint32] -or $Raw -is [uint64]) { $NumericCount[$Ci]++ }
                }
                else { $Text = ConvertTo-Json -InputObject $Raw -Depth 5 -Compress }
                $Cells[$Ci] = $Text
            }
            if ($RowConditions.Count) {
                foreach ($Condition in $RowConditions) {
                    if (Test-PSICondition -InputObject $Record -Condition $Condition) { $RowStatus[[string] $RowIndex] = Get-FluentStatus (Get-Prop $Condition 'Status'); break }
                }
            }
            if ($CellConditionsByColumn.Count) {
                foreach ($Ci in $CellConditionsByColumn.Keys) {
                    foreach ($Condition in $CellConditionsByColumn[$Ci]) {
                        if (Test-PSICondition -InputObject $Record -Condition $Condition) {
                            $Key = [string] $RowIndex
                            if (-not $CellStatus.Contains($Key)) { $CellStatus[$Key] = [ordered]@{} }
                            $CellStatus[$Key][[string] $Ci] = Get-FluentStatus (Get-Prop $Condition 'Status')
                            break
                        }
                    }
                }
            }
            # Classic normal-mode text: a status-like value becomes its canonical spelling
            # unless a cell condition already styled the cell.
            for ($Ci = 0; $Ci -lt $ColumnCount; $Ci++) {
                $Text = $Cells[$Ci]
                if ($null -eq $Text -or $Text.Length -gt 14) { continue }
                $Key = $Text.Trim()
                if ($StatusMap.ContainsKey($Key) -and -not ($CellStatus.Contains([string] $RowIndex) -and $CellStatus[[string] $RowIndex].Contains([string] $Ci))) { $Cells[$Ci] = $StatusMap[$Key] }
            }
            $Rows.Add($Cells)
            $RowIndex++
        }
        for ($Ci = 0; $Ci -lt $ColumnCount; $Ci++) { $Numeric[$Ci] = $NonNull[$Ci] -gt 0 -and $NumericCount[$Ci] -eq $NonNull[$Ci] }

        $Filters = @(foreach ($Filter in (Get-PropList $P 'Filters')) {
            [ordered]@{
                property = [string] (Get-Prop $Filter 'Property')
                label    = [string] (Get-Prop $Filter 'Label' (Get-Prop $Filter 'Property'))
                type     = [string] (Get-Prop $Filter 'Type' 'Select')
                values   = @((Get-PropList $Filter 'Values') | ForEach-Object { [string] $_ })
            }
        })
        $EmptyMessage = [string] (Get-Prop $P 'EmptyMessage' 'No records match your filters.')
        if ($Data.Count -eq 0 -and $EmptyMessage -eq 'No records match your filters.') { $EmptyMessage = 'No data available.' }
        $ExportColumns = (Get-PropList $P 'ExportColumns')
        [string[]] $ExportList = $Columns
        if ($ExportColumns.Count) { $ExportList = @($ExportColumns | ForEach-Object { [string] $_ }) }
        [ordered]@{
            t          = 'Table'
            id         = [string] (Get-Prop $P 'Id')
            title      = [string] (Get-Prop $P 'Title')
            span       = [int] (Get-Prop $P 'Span' 12)
            columns    = $Columns
            labels     = $LabelOut
            numeric    = [bool[]] $Numeric
            rows       = $Rows.ToArray()
            rowStatus  = $RowStatus
            cellStatus = $CellStatus
            filters    = $Filters
            pageSize   = [int] (Get-Prop $P 'PageSize' 10)
            search     = [bool] (Get-Prop $P 'EnableSearch' $true)
            sort       = [bool] (Get-Prop $P 'EnableSorting' $true)
            paging     = [bool] (Get-Prop $P 'EnablePagination' $true)
            empty      = $EmptyMessage
            nullText   = [string] (Get-Prop $P 'NullValueText' ([string] [char] 0x2014))
            export     = [ordered]@{
                enabled   = [bool] (Get-Prop $P 'EnableExport' $true)
                columns   = $ExportList
                formats   = @(foreach ($Format in (Get-Prop $P 'ExportFormats' @('Csv', 'Xlsx', 'Print'))) { [string] $Format })
                fileName  = [string] (Get-Prop $P 'ExportFileName' '')
                worksheet = [string] (Get-Prop $P 'WorksheetName' '')
            }
        }
    }

    # ------------------------------------------------------------------ chart aggregation (classic semantics)
    function ConvertTo-FluentChart([object] $P) {
        $Data = (Get-PropList $P 'Data')
        $CategoryProperty = [string] (Get-Prop $P 'CategoryProperty')
        $ValueProperty = [string] (Get-Prop $P 'ValueProperty')
        $SeriesProperty = [string] (Get-Prop $P 'SeriesProperty' '')
        $StatusProperty = [string] (Get-Prop $P 'StatusProperty' '')
        $FilterMeta = Get-Prop $P 'FilterMetadata' @{}
        $FilterValueProperty = [string] (Get-Prop $FilterMeta 'ValueProperty' $CategoryProperty)
        $Categories = [System.Collections.Generic.List[string]]::new()
        $CategoryIndex = @{}
        $SeriesNames = [System.Collections.Generic.List[string]]::new()
        $SeriesValues = @{}
        $PointStatus = @{}
        $FilterValues = @{}
        $FilterConflict = @{}
        $NullCount = 0
        foreach ($Record in $Data) {
            $CategoryRaw = Get-Prop $Record $CategoryProperty
            $Category = if ($null -eq $CategoryRaw) { 'Not specified' } else { Format-FluentValue $CategoryRaw }
            if (-not $CategoryIndex.ContainsKey($Category)) { $CategoryIndex[$Category] = $Categories.Count; $Categories.Add($Category) }
            $Series = if ($SeriesProperty) { $S = Get-Prop $Record $SeriesProperty; if ($null -eq $S) { 'Unspecified series' } else { [string] $S } } else { $ValueProperty }
            if (-not $SeriesValues.ContainsKey($Series)) { $SeriesValues[$Series] = @{}; $SeriesNames.Add($Series) }
            $Raw = Get-Prop $Record $ValueProperty
            if ($null -eq $Raw) { $NullCount++ }
            else {
                $Number = 0.0
                if (-not [double]::TryParse([string]::Format($Invariant, '{0}', $Raw), [System.Globalization.NumberStyles]::Float, $Invariant, [ref] $Number)) {
                    throw "Chart '$((Get-Prop $P 'Title'))' value '$Raw' in '$ValueProperty' is not numeric."
                }
                $Bucket = $SeriesValues[$Series]
                $Bucket[$Category] = [double] (Get-Prop $Bucket $Category 0.0) + $Number
            }
            if ($StatusProperty -and -not $PointStatus.ContainsKey($Category)) {
                $StatusValue = Get-Prop $Record $StatusProperty
                if ($null -ne $StatusValue) { $PointStatus[$Category] = Get-FluentStatus $StatusValue $null }
            }
            if ($FilterMeta -is [System.Collections.IDictionary] -and $FilterMeta.Count) {
                $FilterRaw = Get-Prop $Record $FilterValueProperty
                $FilterText = if ($null -eq $FilterRaw) { $null } else { [string] $FilterRaw }
                if ($null -eq $FilterText) { $FilterConflict[$Category] = $true }
                elseif ($FilterValues.ContainsKey($Category) -and -not [string]::Equals($FilterValues[$Category], $FilterText, [System.StringComparison]::Ordinal)) { $FilterConflict[$Category] = $true }
                else { $FilterValues[$Category] = $FilterText }
            }
        }
        $Status = @(foreach ($Category in $Categories) {
            if ($PointStatus.ContainsKey($Category)) { $PointStatus[$Category] } else { Get-FluentStatus $Category $null }
        })
        $Filter = $null
        if ($FilterMeta -is [System.Collections.IDictionary] -and $FilterMeta.Count) {
            $Filter = [ordered]@{
                table    = [string] (Get-Prop $FilterMeta 'Table')
                property = [string] (Get-Prop $FilterMeta 'Property')
                values   = @(foreach ($Category in $Categories) { if ($FilterValues.ContainsKey($Category) -and -not $FilterConflict.ContainsKey($Category)) { $FilterValues[$Category] } else { $null } })
            }
        }
        [ordered]@{
            t          = 'Chart'
            title      = [string] (Get-Prop $P 'Title')
            chartType  = [string] (Get-Prop $P 'ChartType' 'Bar')
            categories = $Categories.ToArray()
            series     = @(foreach ($Name in $SeriesNames) { [ordered]@{ name = $Name; values = @(foreach ($Category in $Categories) { $V = $SeriesValues[$Name]; if ($V.ContainsKey($Category)) { [double] $V[$Category] } else { $null } }) } })
            status     = $Status
            filter     = $Filter
            legend     = [bool] (Get-Prop $P 'ShowLegend' $true)
            labels     = [bool] (Get-Prop $P 'ShowLabels' $false)
            empty      = [string] (Get-Prop $P 'EmptyMessage' 'No chart data is available.')
            nullCount  = $NullCount
            valueName  = $ValueProperty
        }
    }

    function ConvertTo-FluentEvidence([object] $Definition) {
        if ($null -eq $Definition) { return $null }
        [ordered]@{
            table      = [string] $Definition.tableId
            conditions = @(foreach ($C in @($Definition.conditions)) {
                $Op = [string] (Get-Prop $C 'Operator' 'Equals')
                $Out = [ordered]@{ property = [string] (Get-Prop $C 'Property'); operator = $Op }
                if ($Op -eq 'In') { $Out.values = @((Get-PropList $C 'Values') | ForEach-Object { if ($null -eq $_) { $null } else { [string] $_ } }) }
                else { $V = Get-Prop $C 'Value'; $Out.value = if ($null -eq $V) { $null } else { [string] $V } }
                $Out
            })
            columns    = @($Definition.evidenceColumns)
            export     = @($Definition.exportColumns)
            labels     = ConvertTo-FluentPlain $Definition.labels
            visible    = [bool] $Definition.useVisibleColumns
        }
    }

    # ------------------------------------------------------------------ explorer (list/detail over records or model entities)
    function Get-RecordValue([object] $Record, [string] $Name) {
        # Record property first, then the record's Properties bag (resource custom properties such as Site).
        $Value = Get-Prop $Record $Name
        if ($null -eq $Value) { $Bag = Get-Prop $Record 'Properties'; if ($null -ne $Bag) { $Value = Get-Prop $Bag $Name } }
        $Value
    }
    function ConvertTo-FluentExplorer([object] $P) {
        $Entity = [string] (Get-Prop $P 'EntityType' '')
        $TitleProperty = [string] (Get-Prop $P 'TitleProperty')
        $SubtitleProperty = [string] (Get-Prop $P 'SubtitleProperty' '')
        $StatusProperty = [string] (Get-Prop $P 'StatusProperty' '')
        $FilterProperties = @((Get-PropList $P 'FilterProperties') | ForEach-Object { [string] $_ })
        $DetailProperties = @((Get-PropList $P 'DetailProperties') | ForEach-Object { [string] $_ })
        $Labels = Get-Prop $P 'ColumnLabels' @{}
        $Data = Get-PropList $P 'Data'
        if (-not $Entity -and $DetailProperties.Count -eq 0 -and $Data.Count -gt 0) { $DetailProperties = @(Get-PSITableColumnNames -Data @($Data[0])) }
        $LabelOf = {
            param([string] $Name)
            if ($Labels -is [System.Collections.IDictionary] -and $Labels.Contains($Name)) { return [string] $Labels[$Name] }
            $Name -creplace '([a-z])([A-Z])', '$1 $2'
        }
        $Items = @(foreach ($Record in $Data) {
            $Title = Format-FluentValue (Get-RecordValue $Record $TitleProperty)
            $Item = [ordered]@{
                id       = if ($Entity) { [string] (Get-Prop $Record 'Id') } else { $null }
                title    = if ([string]::IsNullOrWhiteSpace($Title)) { '(unnamed)' } else { $Title }
                subtitle = if ($SubtitleProperty) { Format-FluentValue (Get-RecordValue $Record $SubtitleProperty) } else { $null }
                status   = if ($StatusProperty) { Format-FluentValue (Get-RecordValue $Record $StatusProperty) } else { $null }
                filters  = [ordered]@{}
            }
            foreach ($Name in $FilterProperties) { $Item.filters[$Name] = Format-FluentValue (Get-RecordValue $Record $Name) }
            if (-not $Entity) { $Item.details = @(foreach ($Name in $DetailProperties) { , @((& $LabelOf $Name), (Format-FluentValue (Get-RecordValue $Record $Name))) }) }
            $Item
        })
        [ordered]@{
            t           = 'Explorer'
            id          = [string] (Get-Prop $P 'Id')
            title       = [string] (Get-Prop $P 'Title')
            entity      = $Entity
            items       = $Items
            filterProps = @(foreach ($Name in $FilterProperties) { [ordered]@{ property = $Name; label = (& $LabelOf $Name) } })
            detailProps = $DetailProperties
            linkViews   = ConvertTo-FluentPlain (Get-Prop $P 'LinkViews')
            empty       = [string] (Get-Prop $P 'EmptyMessage' 'No records available.')
        }
    }

    # ------------------------------------------------------------------ components
    $TableIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Section in $Sections) { foreach ($Row in $Section.Rows) { foreach ($C in $Row.Components) { if ($C.Type -eq 'Table') { [void] $TableIds.Add([string] (Get-Prop $C.Properties 'Id')) } } } }

    $SectionModels = [System.Collections.Generic.List[object]]::new()
    $FindingModels = [System.Collections.Generic.List[object]]::new()
    for ($SectionIndex = 0; $SectionIndex -lt $Sections.Count; $SectionIndex++) {
        $Section = $Sections[$SectionIndex]
        $SectionId = "psi-section-$SectionIndex"
        $RowModels = [System.Collections.Generic.List[object]]::new()
        $Kinds = @{}
        foreach ($Row in $Section.Rows) {
            $Columns = [int] $Row.Columns
            $KpiCount = @($Row.Components | Where-Object { $_.Type -eq 'KPI' }).Count
            $InsightCount = @($Row.Components | Where-Object { $_.Type -eq 'Insight' }).Count
            $Items = [System.Collections.Generic.List[object]]::new()
            foreach ($Component in $Row.Components) {
                $P = $Component.Properties
                $Type = [string] $Component.Type
                $Kinds[$Type] = $true
                $Item = switch ($Type) {
                    'Text' { [ordered]@{ t = 'Text'; text = [string] (Get-Prop $P 'Text'); size = [string] (Get-Prop $P 'Size' 'Normal') } }
                    'KeyValue' {
                        $Data = Get-Prop $P 'Data'
                        [ordered]@{ t = 'KeyValue'; title = [string] (Get-Prop $P 'Title'); span = [int] (Get-Prop $P 'Span' 6)
                            rows = @(if ($Data -is [System.Collections.IDictionary]) { foreach ($Key in $Data.Keys) { , @([string] $Key, (Format-FluentValue $Data[$Key])) } }) }
                    }
                    'KPI' {
                        $Action = Get-Prop $P 'Action'
                        $ActionOut = $null
                        if ($null -ne $Action -and ($Action -isnot [System.Collections.IDictionary] -or $Action.Count -gt 0)) {
                            $ActionType = [string] (Get-Prop $Action 'Type')
                            $ActionTarget = [string] (Get-Prop $Action 'Target')
                            if ($ActionType -in @('ScrollTo', 'FilterTable') -and $ActionTarget) {
                                $ActionOut = [ordered]@{ type = $ActionType; target = $ActionTarget; property = [string] (Get-Prop $Action 'Property'); value = Format-FluentValue (Get-Prop $Action 'Value') }
                            }
                        }
                        $Filter = Get-Prop $P 'Filter'
                        $FilterOut = $null
                        if ($Filter -is [System.Collections.IDictionary] -and $Filter.Count -gt 0) {
                            $FilterOut = [ordered]@{ table = [string] (Get-Prop $Filter 'Table'); property = [string] (Get-Prop $Filter 'Property') }
                            $Values = Get-Prop $Filter 'Values'
                            if ($null -ne $Values) { $FilterOut.values = @(@($Values) | ForEach-Object { [string] $_ }) } else { $FilterOut.values = @([string] (Get-Prop $Filter 'Value')) }
                        }
                        $Drill = @(Get-Prop $P 'DrillDown')
                        $DrillOut = if ($Drill.Count -gt 0 -and $null -ne $Drill[0]) { [ordered]@{ title = [string] (Get-Prop $P 'Title'); records = @(foreach ($R in $Drill) { ConvertTo-FluentPlain $R }) } } else { $null }
                        $Span = Get-Prop $P 'Span'
                        [ordered]@{ t = 'KPI'; title = [string] (Get-Prop $P 'Title'); value = (Format-FluentValue (Get-Prop $P 'Value'))
                            subtitle = [string] (Get-Prop $P 'Subtitle' ''); status = Get-FluentStatus (Get-Prop $P 'Status'); tone = [string] (Get-Prop $P 'VisualTone' 'Status')
                            span = if ($null -ne $Span) { [int] $Span } else { [math]::Max(1, [math]::Floor($Columns / [math]::Max(1, $KpiCount))) }
                            icon = [string] (Get-Prop $P 'Icon' ''); trend = [string] (Get-Prop $P 'Trend' ''); action = $ActionOut; filter = $FilterOut; drill = $DrillOut }
                    }
                    'Sparkline' {
                        [ordered]@{ t = 'Sparkline'; label = [string] (Get-Prop $P 'Label' ''); current = Format-FluentValue (Get-Prop $P 'CurrentValue')
                            values = @((Get-PropList $P 'Values') | ForEach-Object { [double] $_ }); status = Get-FluentStatus (Get-Prop $P 'Status') 'Informational'
                            min = Get-Prop $P 'Minimum'; max = Get-Prop $P 'Maximum'; span = [int] (Get-Prop $P 'Span' 3) }
                    }
                    'EmptyState' {
                        [ordered]@{ t = 'EmptyState'; title = [string] (Get-Prop $P 'Title'); explanation = [string] (Get-Prop $P 'Explanation')
                            icon = [string] (Get-Prop $P 'Icon' 'Document'); actionLabel = [string] (Get-Prop $P 'ActionLabel' ''); targetView = [string] (Get-Prop $P 'TargetView' '') }
                    }
                    'Insight' {
                        $Filter = Get-Prop $P 'Filter'
                        $Evidence = $null
                        if ($Filter -is [System.Collections.IDictionary] -and $Filter.Count -gt 0) {
                            $Labels = Get-Prop $P 'ColumnLabels' @{}
                            if ($Labels -isnot [hashtable]) { $Labels = @{} }
                            $Evidence = ConvertTo-FluentEvidence (Resolve-PSIEvidenceDefinition -Filter $Filter -EvidenceColumns (Get-PropList $P 'EvidenceColumns') -ExportColumns (Get-PropList $P 'ExportColumns') -Labels $Labels)
                        }
                        [ordered]@{ t = 'Insight'; title = [string] (Get-Prop $P 'Title'); value = Format-FluentValue (Get-Prop $P 'Value'); description = [string] (Get-Prop $P 'Description' '')
                            status = Get-FluentStatus (Get-Prop $P 'Status') 'Informational'; icon = [string] (Get-Prop $P 'Icon' '')
                            span = [math]::Max(1, [math]::Floor($Columns / [math]::Max(1, $InsightCount))); evidence = $Evidence }
                    }
                    'Finding' {
                        $Anchor = $Anchors[$AnchorIndex].Id; $AnchorIndex++
                        $Evidence = $null
                        $TableId = [string] (Get-Prop $P 'EvidenceTableId' '')
                        $EvidenceFilter = Get-Prop $P 'EvidenceFilter'
                        if ($TableId -or ($EvidenceFilter -is [System.Collections.IDictionary] -and $EvidenceFilter.Count)) {
                            $Definition = Resolve-PSIEvidenceDefinition -TableId $TableId -Filter $EvidenceFilter -EvidenceColumns (Get-PropList $P 'EvidenceColumns') -ExportColumns (Get-PropList $P 'EvidenceColumns') -UseVisibleColumns
                            if ($null -ne $Definition -and $TableIds.Contains([string] $Definition.tableId)) { $Evidence = ConvertTo-FluentEvidence $Definition }
                            elseif ($null -ne $Definition) { Write-Warning "Finding '$((Get-Prop $P 'Title'))' references missing evidence table '$($Definition.tableId)'. The evidence action was omitted." }
                        }
                        $F = [ordered]@{ t = 'Finding'; id = $Anchor; title = [string] (Get-Prop $P 'Title'); status = Get-FluentStatus (Get-Prop $P 'Status')
                            category = [string] (Get-Prop $P 'Category' ''); description = [string] (Get-Prop $P 'Description' ''); affected = [string] (Get-Prop $P 'AffectedObject' '')
                            impact = [string] (Get-Prop $P 'Impact' ''); recommendation = [string] (Get-Prop $P 'Recommendation' ''); ruleId = [string] (Get-Prop $P 'RuleId' '')
                            source = [string] (Get-Prop $P 'Source' ''); evidence = $Evidence; section = $SectionId }
                        $FindingModels.Add([ordered]@{ id = $Anchor; title = $F.title; status = $F.status; category = $F.category; affected = $F.affected; section = $SectionId; assessment = [string] (Get-Prop $Section 'AssessmentId' '') })
                        $F
                    }
                    'Status' { [ordered]@{ t = 'Status'; status = Get-FluentStatus (Get-Prop $P 'Status'); label = [string] (Get-Prop $P 'Label' ''); message = [string] (Get-Prop $P 'Message' '') } }
                    'Alert' {
                        $Details = Get-Prop $P 'Details'
                        $DetailText = if ($null -eq $Details) { $null } elseif ($Details -is [string] -or $Details.GetType().IsPrimitive) { [string] $Details } else { ConvertTo-Json -InputObject $Details -Depth 5 -Compress }
                        $Stamp = Get-Prop $P 'Timestamp'
                        [ordered]@{ t = 'Alert'; status = Get-FluentStatus (Get-Prop $P 'Status'); title = [string] (Get-Prop $P 'Title'); message = [string] (Get-Prop $P 'Message')
                            timestamp = if ($null -eq $Stamp) { $null } else { Format-FluentValue $Stamp }; details = $DetailText; action = [string] (Get-Prop $P 'Action' '') }
                    }
                    'Recommendation' {
                        [ordered]@{ t = 'Recommendation'; status = Get-FluentStatus (Get-Prop $P 'Status') 'Informational'; title = [string] (Get-Prop $P 'Title')
                            description = [string] (Get-Prop $P 'Description'); action = [string] (Get-Prop $P 'ActionText' '') }
                    }
                    'Table' { ConvertTo-FluentTable $P }
                    'Chart' { ConvertTo-FluentChart $P }
                    'Explorer' { ConvertTo-FluentExplorer $P }
                    'AssessmentOverview' {
                        [ordered]@{ t = 'AssessmentOverview'; checkView = [string] (Get-Prop $P 'CheckViewId' 'checks'); findingView = [string] (Get-Prop $P 'FindingViewId' 'findings') }
                    }
                    { $_ -in @('Tree', 'Topology', 'RelationshipExplorer') } {
                        [ordered]@{ t = $Type; id = [string] (Get-Prop $P 'Id'); title = [string] (Get-Prop $P 'Title')
                            presentation = ConvertTo-FluentPlain (Get-Prop $P 'Presentation'); linkViews = ConvertTo-FluentPlain (Get-Prop $P 'LinkViews')
                            maxNodes = [int] (Get-Prop $P 'MaxNodes' 100); filterProps = @((Get-PropList $P 'FilterProperties') | ForEach-Object { [string] $_ }) }
                    }
                    default {
                        $Unsupported.Add($Type)
                        [ordered]@{ t = 'Unsupported'; type = $Type; title = [string] (Get-Prop $P 'Title' $Type) }
                    }
                }
                if ($null -ne $Item) { $Items.Add($Item) }
            }
            $RowModels.Add([ordered]@{ columns = $Columns; items = $Items.ToArray() })
        }
        $Icon = if ($Kinds.ContainsKey('Finding')) { 'shieldAlert' } elseif ($Kinds.ContainsKey('Table')) { 'grid' } elseif ($Kinds.ContainsKey('Chart')) { 'chart' }
            elseif ($Kinds.ContainsKey('Recommendation')) { 'lightbulb' } elseif ($Kinds.ContainsKey('KPI') -or $Kinds.ContainsKey('Insight')) { 'home' } else { 'document' }
        $SectionModels.Add([ordered]@{
            id = $SectionId; title = [string] $Section.Title; icon = $Icon
            assessmentId = [string] (Get-Prop $Section 'AssessmentId' ''); assessmentName = [string] (Get-Prop $Section 'AssessmentName' '')
            overview = ((Get-Prop $Section 'IsOverview' $false) -eq $true); viewId = [string] (Get-Prop $Section 'ViewId' '')
            rows = $RowModels.ToArray()
        })
    }

    # ------------------------------------------------------------------ pages and navigation
    $Pages = [System.Collections.Generic.List[object]]::new()
    $Nav = [System.Collections.Generic.List[object]]::new()
    $Views = (Get-PropList $Report 'Views')
    $NavigationGroups = (Get-PropList $Report 'NavigationGroups')
    $FindSection = {
        param([object] $Target)
        for ($I = 0; $I -lt $Sections.Count; $I++) { if ([object]::ReferenceEquals($Sections[$I], $Target)) { return $I } }
        return $null
    }
    $AddNav = {
        param([string] $Group, [object] $Item)
        $Existing = $Nav | Where-Object { $_.label -eq $Group } | Select-Object -First 1
        if (-not $Existing) { $Existing = [ordered]@{ label = $Group; items = [System.Collections.Generic.List[object]]::new() }; $Nav.Add($Existing) }
        $Existing.items.Add($Item)
    }
    if ($Views.Count -gt 0) {
        foreach ($View in $Views) {
            $Indexes = @(foreach ($S in $View.Sections) { $Found = & $FindSection $S; if ($null -ne $Found) { $Found } })
            $Initial = (Get-Prop (Get-Prop $View 'State') 'Initial' $false) -eq $true
            $Page = [ordered]@{ id = [string] $View.Id; title = [string] $View.Title; subtitle = [string] (Get-Prop $View 'Subtitle' ''); icon = [string] (Get-Prop $View 'Icon' 'Document')
                sections = $Indexes; initial = $Initial; disabled = ((Get-Prop $View 'Disabled' $false) -eq $true); badge = [string] (Get-Prop $View 'Badge' '')
                commands = @(foreach ($C in (Get-PropList $View 'Commands')) { [ordered]@{ label = [string] (Get-Prop $C 'Label'); icon = [string] (Get-Prop $C 'Icon' ''); target = [string] (Get-Prop $C 'TargetView') } }) }
            $Pages.Add($Page)
            & $AddNav ([string] (Get-Prop $View 'Group' 'Workspace')) $Page.id
        }
    }
    elseif ($NavigationGroups.Count -gt 0) {
        foreach ($Group in $NavigationGroups) {
            foreach ($NavItem in (Get-PropList $Group 'Items')) {
                $Target = [string] (Get-Prop $NavItem 'Target' '')
                if ($Target -notmatch '^psi-section-(\d+)$') { continue }
                $Page = [ordered]@{ id = [string] (Get-Prop $NavItem 'Id' $Target); title = [string] (Get-Prop $NavItem 'Label'); subtitle = ''; icon = [string] (Get-Prop $NavItem 'Icon' 'Document')
                    sections = @([int] $Matches[1]); initial = ((Get-Prop $NavItem 'Selected' $false) -eq $true); disabled = ((Get-Prop $NavItem 'Disabled' $false) -eq $true); badge = [string] (Get-Prop $NavItem 'Badge' ''); commands = @() }
                $Pages.Add($Page)
                & $AddNav ([string] (Get-Prop $Group 'Label' 'Report')) $Page.id
            }
        }
        $Covered = @{}; foreach ($Page in $Pages) { foreach ($I in $Page.sections) { $Covered[$I] = $true } }
        for ($I = 0; $I -lt $SectionModels.Count; $I++) {
            if (-not $Covered.ContainsKey($I)) { $Page = [ordered]@{ id = "page-$I"; title = $SectionModels[$I].title; subtitle = ''; icon = $SectionModels[$I].icon; sections = @($I); initial = $false; disabled = $false; badge = ''; commands = @() }; $Pages.Add($Page); & $AddNav 'More' $Page.id }
        }
    }
    else {
        for ($I = 0; $I -lt $SectionModels.Count; $I++) {
            $S = $SectionModels[$I]
            $Group = if ($S.overview) { 'Overview' } elseif ($S.assessmentName) { $S.assessmentName } else { 'Report' }
            $Page = [ordered]@{ id = "page-$I"; title = $S.title; subtitle = $S.assessmentName; icon = $S.icon; sections = @($I); initial = ($I -eq 0); disabled = $false; badge = ''; commands = @() }
            $Pages.Add($Page)
            & $AddNav $Group $Page.id
        }
    }
    if (-not ($Pages | Where-Object { $_.initial -and -not $_.disabled })) {
        $First = $Pages | Where-Object { -not $_.disabled } | Select-Object -First 1
        if ($First) { $First.initial = $true }
    }

    # ------------------------------------------------------------------ assessments and summary
    $FindingSummary = [ordered]@{}
    foreach ($Value in $CanonicalStatuses) { $FindingSummary[$Value] = 0 }
    foreach ($F in $FindingModels) { $FindingSummary[$F.status]++ }
    # Assessment status is derived from the findings rendered in its sections, using the
    # same precedence as Resolve-PSIOverallStatus (no findings = Neutral).
    $Precedence = @('Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral')
    $AssessmentModels = @(foreach ($Entry in (Get-PropList $Report 'Assessments')) {
        if ($null -eq $Entry) { continue }
        $Id = [string] (Get-Prop $Entry 'Id' '')
        $Own = @($FindingModels | Where-Object { $_.assessment -eq $Id })
        $Overall = 'Neutral'
        foreach ($Candidate in $Precedence) { if ($Own | Where-Object { $_.status -eq $Candidate }) { $Overall = $Candidate; break } }
        [ordered]@{ id = $Id; name = [string] (Get-Prop $Entry 'Name' ''); title = [string] (Get-Prop $Entry 'Title' ''); provider = [string] (Get-Prop $Entry 'Provider' '')
            description = [string] (Get-Prop $Entry 'Description' ''); status = $Overall; findings = $Own.Count
            sections = @($SectionModels | Where-Object { $_.assessmentId -eq $Id }).Count }
    })

    $Generated = [datetime] $Report.GeneratedOn
    [ordered]@{
        schema   = 1
        meta     = [ordered]@{
            title       = [string] $Report.Title
            subtitle    = [string] $Report.Subtitle
            theme       = [string] $Report.Theme
            generated   = $Generated.ToString('yyyy-MM-ddTHH:mm:sszzz', $Invariant)
            version     = [string] $Report.ModuleVersion
            layout      = [string] (Get-Prop $Report 'Layout' 'Report')
            print       = $EnableReportPrint
            unsupported = @($Unsupported | Select-Object -Unique)
        }
        nav         = @(foreach ($G in $Nav) { [ordered]@{ label = $G.label; items = $G.items.ToArray() } })
        pages       = $Pages.ToArray()
        sections    = $SectionModels.ToArray()
        findings    = $FindingModels.ToArray()
        summary     = $FindingSummary
        assessments = $AssessmentModels
        # Application intelligence model and posture, projected once (explorers reference ids).
        app         = if ($null -ne $Report.PSObject.Properties['ApplicationModel']) {
            $AppModel = $Report.ApplicationModel
            # ConvertTo-FluentPlain returns lists with the unary comma: assign directly (no @()).
            [ordered]@{ findings = ConvertTo-FluentPlain (Get-PropList $AppModel 'Findings'); resources = ConvertTo-FluentPlain (Get-PropList $AppModel 'Resources')
                evidence = ConvertTo-FluentPlain (Get-PropList $AppModel 'Evidence'); relationships = ConvertTo-FluentPlain (Get-PropList $AppModel 'Relationships') }
        } else { $null }
        assessment  = if ($null -ne $Report.PSObject.Properties['ApplicationAssessment']) { ConvertTo-FluentPlain $Report.ApplicationAssessment } else { $null }
        workspace   = if ($null -ne $Report.PSObject.Properties['ResourceExplorer']) {
            [ordered]@{ explorer = ConvertTo-FluentPlain $Report.ResourceExplorer
                inspector = if ($null -ne $Report.PSObject.Properties['Inspector']) { ConvertTo-FluentPlain $Report.Inspector } else { $null } }
        } else { $null }
    }
}
#endregion

#region Private/ConvertTo-PSIHtml.ps1
function ConvertTo-PSIHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [bool] $EnableReportPrint = $true
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
        throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object].'
    }
    $TableIds = Assert-PSIReportIds -Sections $SectionsProperty.Value
    if ($null -ne $Report.PSObject.Properties['ApplicationModel']) {
        [void] (Assert-PSIApplicationModel -Model $Report.ApplicationModel)
    }

    $Title = ConvertTo-PSIHtmlEncoded -Value $Report.Title
    $Subtitle = ConvertTo-PSIHtmlEncoded -Value $Report.Subtitle
    $GeneratedOn = ConvertTo-PSIHtmlEncoded -Value ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $Theme = [string] $Report.Theme
    if ($Theme -notin @('Light', 'Dark', 'Auto')) {
        throw "Theme must be Light, Dark, or Auto. Found '$Theme'."
    }
    $Layout = [string] (Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report')
    if ($Layout -notin @('Report', 'Application')) { throw "Unknown report layout '$Layout'." }
    $Navigation = [string] (Get-PSIProperty -InputObject $Report -Name 'Navigation' -DefaultValue 'Sidebar')
    $Density = [string] (Get-PSIProperty -InputObject $Report -Name 'Density' -DefaultValue 'Comfortable')
    $IsCompactFluent = $Layout -eq 'Application' -and $Navigation -eq 'FluentExplorer' -and $Density -eq 'Compact'
    if ($Navigation -notin @('Sidebar', 'FluentExplorer') -or $Density -notin @('Comfortable', 'Compact')) {
        throw 'Unknown Application navigation or density option.'
    }
    if ($Layout -ne 'Application' -and ($Navigation -ne 'Sidebar' -or $Density -ne 'Comfortable')) {
        throw 'Navigation and Density options require Application layout.'
    }
    $ReportViews = Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()
    $IsMultiView = $Layout -eq 'Application' -and $null -ne $ReportViews -and $ReportViews.Count -gt 0
    $HasRelationshipComponents = $false
    foreach ($Part in $SectionsProperty.Value) {
        foreach ($GridRow in $Part.Rows) {
            foreach ($PartComponent in $GridRow.Components) {
                if ($PartComponent.Type -in @('Tree','Topology','RelationshipExplorer')) { $HasRelationshipComponents = $true }
            }
        }
    }
    if ($IsMultiView -and $null -ne $Report.PSObject.Properties['ApplicationModel']) {
        [void] (Assert-PSIApplicationLinks -Report $Report)
    }
    if ($null -ne $Report.PSObject.Properties['ApplicationAssessment']) {
        [void] (Resolve-PSIAssessmentPosture -Assessment $Report.ApplicationAssessment -Model $Report.ApplicationModel)
    }
    $ModuleVersion = ConvertTo-PSIHtmlEncoded -Value $Report.ModuleVersion

    $ThemeStylesheetPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/CSS/psi-theme.css'
    if (-not (Test-Path -LiteralPath $ThemeStylesheetPath -PathType Leaf)) {
        throw "The PSInsightHTML theme stylesheet is missing: '$ThemeStylesheetPath'."
    }
    $ThemeStylesheet = Get-Content -LiteralPath $ThemeStylesheetPath -Raw -ErrorAction Stop
    $VisualStylesheetPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/CSS/PSInsightHTML.css'
    if (-not (Test-Path -LiteralPath $VisualStylesheetPath -PathType Leaf)) {
        throw "The PSInsightHTML visual stylesheet is missing: '$VisualStylesheetPath'."
    }
    $ThemeStylesheet += "`n" + (Get-Content -LiteralPath $VisualStylesheetPath -Raw -ErrorAction Stop)
    if ($Layout -eq 'Application') {
        $AppStylesheetPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/CSS/psi-application.css'
        $ThemeStylesheet += "`n" + (Get-Content -LiteralPath $AppStylesheetPath -Raw -ErrorAction Stop)
        $ThemeStylesheet += "`n" + (Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/CSS/psi-fluent-explorer.css') -Raw -ErrorAction Stop)
        if ($null -ne $Report.PSObject.Properties['ResourceExplorer']) {
            $ThemeStylesheet += "`n" + (Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/CSS/psi-resource-workspace.css') -Raw -ErrorAction Stop)
        }
        if ($HasRelationshipComponents) {
            $ThemeStylesheet += "`n" + (Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/CSS/psi-relationships.css') -Raw -ErrorAction Stop)
        }
        if ($EnableReportPrint) {
            $ThemeStylesheet += "`n" + (Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/CSS/psi-print.css') -Raw -ErrorAction Stop)
        }
    }
    $SectionMarkup = [System.Text.StringBuilder]::new()
    $NavigationMarkup = [System.Text.StringBuilder]::new()
    $HasTableComponents = $false
    $HasSearchableTableComponents = $false
    $HasDrillDownComponents = $false
    $HasInsightComponents = $false
    $SectionIndex = 0
    $FindingAnchors = Get-PSIFindingAnchors -Sections $SectionsProperty.Value
    $FindingIndex = 0
    $AssessmentNavigationMarkup = [System.Text.StringBuilder]::new()
    $SeenAssessmentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ApplicationNavigation = $null
    $ApplicationSectionIcons = @{}
    $OpenViewId = ''
    $InitialViewId = ''
    if ($Layout -eq 'Application') {
        $ApplicationNavigation = Resolve-PSIApplicationNavigation -Report $Report
        foreach ($Group in $ApplicationNavigation) {
            foreach ($Item in $Group.Items) {
                if ($IsMultiView -and $Item.Selected) { $InitialViewId = $Item.Id }
                if ($Item.Target -and -not $ApplicationSectionIcons.ContainsKey($Item.Target)) {
                    $ApplicationSectionIcons[$Item.Target] = $Item.Icon
                }
            }
        }
        if ($IsMultiView) {
            $ViewIcons = @{}
            foreach ($View in $ReportViews) { $ViewIcons[[string] $View.Id] = [string] $View.Icon }
            for ($Index = 0; $Index -lt $SectionsProperty.Value.Count; $Index++) {
                $ViewId = [string] $SectionsProperty.Value[$Index].ViewId
                $ApplicationSectionIcons["psi-section-$Index"] = $ViewIcons[$ViewId]
            }
        }
    }

    foreach ($Section in $SectionsProperty.Value) {
        if ($IsMultiView) {
            $CurrentViewId = [string] $Section.ViewId
            if ($CurrentViewId -cne $OpenViewId) {
                if ($OpenViewId) { [void] $SectionMarkup.AppendLine('      </section>') }
                $View = @($ReportViews | Where-Object { $_.Id -ceq $CurrentViewId })[0]
                $SafeViewTitle = ConvertTo-PSIHtmlEncoded -Value $View.Title
                $SafeViewSubtitle = ConvertTo-PSIHtmlEncoded -Value $View.Subtitle
                $Hidden = if ($CurrentViewId -cne $InitialViewId) { ' hidden' } else { '' }
                $WorkspaceTabRole = if ($Layout -eq 'Application' -and (Get-PSIProperty $Report 'Navigation') -eq 'FluentExplorer' -and (Get-PSIProperty $Report 'Density') -eq 'Compact') { " role=`"tabpanel`" aria-labelledby=`"psi-workspace-tab-$CurrentViewId`"" } else { '' }
                [void] $SectionMarkup.AppendLine("      <section class=`"psi-app-view`" id=`"psi-view-$CurrentViewId`" data-psi-app-view=`"$CurrentViewId`" data-psi-view-label=`"$SafeViewTitle`" data-psi-view-description=`"$SafeViewSubtitle`" aria-label=`"$SafeViewTitle workspace`" tabindex=`"-1`"$WorkspaceTabRole$Hidden>")
                $OpenViewId = $CurrentViewId
            }
        }
        $SectionTitle = ConvertTo-PSIHtmlEncoded -Value $Section.Title
        $SectionId = "psi-section-$SectionIndex"
        [void] $NavigationMarkup.AppendLine("      <a data-psi-nav-section=`"$SectionId`" href=`"#$SectionId`">$SectionTitle</a>")
        $IsOverview = (Get-PSIProperty -InputObject $Section -Name 'IsOverview' -DefaultValue $false) -eq $true
        $AssessmentId = [string] (Get-PSIProperty -InputObject $Section -Name 'AssessmentId')
        $SectionContext = ''
        if ($IsOverview) {
            $SectionContext = ' data-psi-overview="true"'
            [void] $AssessmentNavigationMarkup.AppendLine("      <a data-psi-nav-assessment=`"overview`" href=`"#$SectionId`">Overview</a>")
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($AssessmentId)) {
                $EncodedAssessmentId = ConvertTo-PSIHtmlEncoded -Value $AssessmentId
                $SectionContext = " data-psi-assessment-key=`"$EncodedAssessmentId`""
            }
            if (-not [string]::IsNullOrWhiteSpace($AssessmentId) -and $SeenAssessmentIds.Add($AssessmentId)) {
                $AssessmentName = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Section -Name 'AssessmentName' -DefaultValue $Section.Title)
                [void] $AssessmentNavigationMarkup.AppendLine("      <a data-psi-nav-assessment=`"$EncodedAssessmentId`" href=`"#$SectionId`">$AssessmentName</a>")
            }
        }
        [void] $SectionMarkup.AppendLine("      <section class=`"psi-section`" id=`"$SectionId`" aria-label=`"$SectionTitle`"$SectionContext>")
        if ($Layout -eq 'Application') {
            $SectionIcon = if ($ApplicationSectionIcons.ContainsKey($SectionId)) {
                '<span class="psi-app-section-icon">' + (Get-PSIIcon -Name $ApplicationSectionIcons[$SectionId] -Size 21 -Strict) + '</span>'
            }
            else { '' }
            [void] $SectionMarkup.AppendLine("        <h2>$SectionIcon<span>$SectionTitle</span></h2>")
        }
        else { [void] $SectionMarkup.AppendLine("        <h2>$SectionTitle</h2>") }

        $RowsProperty = $Section.PSObject.Properties['Rows']
        if ($null -eq $RowsProperty -or $RowsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
            throw "Section '$($Section.Title)' does not contain a valid Rows collection."
        }

        $RowIndex = 0
        foreach ($Row in $RowsProperty.Value) {
            $Columns = [int] $Row.Columns
            if ($Columns -lt 1 -or $Columns -gt 12) {
                throw "Row Columns must be between 1 and 12. Found '$Columns'."
            }

            $OverviewRowAttribute = if ($IsOverview) { " data-psi-overview-row=`"$RowIndex`"" } else { '' }
            [void] $SectionMarkup.AppendLine("        <div class=`"psi-row`"$OverviewRowAttribute style=`"--psi-row-columns: $Columns`">")
            $RowIndex++
            $ComponentsProperty = $Row.PSObject.Properties['Components']
            if ($null -eq $ComponentsProperty -or $ComponentsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
                throw "A row in section '$($Section.Title)' does not contain a valid Components collection."
            }

            $KpiCount = @($ComponentsProperty.Value | Where-Object { $_.Type -eq 'KPI' }).Count
            $InsightCount = @($ComponentsProperty.Value | Where-Object { $_.Type -eq 'Insight' }).Count
            $KpiSpan = 12
            if ($KpiCount -gt 0) {
                $KpiSpan = [math]::Max(1, [math]::Floor($Columns / $KpiCount))
            }

            foreach ($Component in $ComponentsProperty.Value) {
                $Properties = $Component.Properties
                $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Properties -Name 'Status')) -AllowInvalid
                if ($null -eq $Status) {
                    $Status = 'Unknown'
                }
                $StatusClass = $Status.ToLowerInvariant()
                if ($Status -eq 'NotChecked') {
                    $StatusClass = 'not-checked'
                }
                $AppStatusIcon = ''
                if ($Layout -eq 'Application' -and $Component.Type -in @('Finding', 'Status', 'Alert', 'Recommendation')) {
                    $StatusIconName = switch ($Status) {
                        'Healthy' { 'SeveritySuccess' }
                        'Warning' { 'SeverityWarning' }
                        'Critical' { 'SeverityError' }
                        default { 'SeverityInfo' }
                    }
                    $AppStatusIcon = '<span class="psi-app-severity-icon">' + (Get-PSIIcon -Name $StatusIconName -Size 20 -Strict) + '</span>'
                }

                switch ([string] $Component.Type) {
                    'AssessmentOverview' {
                        [void] $SectionMarkup.AppendLine((ConvertTo-PSIAssessmentOverviewHtml -Properties $Properties))
                    }
                    'Explorer' {
                        [void] $SectionMarkup.AppendLine((ConvertTo-PSIExplorerHtml -Properties $Properties))
                    }
                    { $_ -in @('Tree','Topology','RelationshipExplorer') } {
                        [void] $SectionMarkup.AppendLine((ConvertTo-PSIRelationshipComponentHtml -Type ([string] $Component.Type) -Properties $Properties))
                    }
                    'Text' {
                        $Text = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Text')
                        $Size = [string] (Get-PSIProperty -InputObject $Properties -Name 'Size')
                        if ($Size -notin @('Small', 'Normal', 'Large')) {
                            $Size = 'Normal'
                        }

                        $SizeClass = $Size.ToLowerInvariant()
                        [void] $SectionMarkup.AppendLine("          <div class=`"psi-text psi-text-$SizeClass`">$Text</div>")
                    }
                    'KeyValue' {
                        $KeyValueTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $KeyValueData = Get-PSIProperty -InputObject $Properties -Name 'Data'
                        $KeyValueSpan = [int] (Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue 6)
                        if ($KeyValueSpan -lt 1 -or $KeyValueSpan -gt 12) { throw 'KeyValue Span must be between 1 and 12.' }
                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-keyvalue-card`" style=`"--psi-component-span: $KeyValueSpan`">")
                        [void] $SectionMarkup.AppendLine("            <h3>$KeyValueTitle</h3>")
                        [void] $SectionMarkup.AppendLine('            <dl class="psi-keyvalue-list">')
                        foreach ($Key in $KeyValueData.Keys) {
                            $SafeKey = ConvertTo-PSIHtmlEncoded -Value $Key
                            $RawValue = Get-PSIProperty -InputObject $KeyValueData -Name ([string] $Key)
                            if ($null -eq $RawValue) { $ValueText = [string] [char] 0x2014 }
                            elseif ($RawValue -is [string] -or $RawValue.GetType().IsValueType) { $ValueText = [string] $RawValue }
                            else { $ValueText = ConvertTo-Json -InputObject $RawValue -Depth 5 -Compress }
                            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $ValueText
                            [void] $SectionMarkup.AppendLine("              <div class=`"psi-keyvalue-row`"><dt>$SafeKey</dt><dd>$SafeValue</dd></div>")
                        }
                        [void] $SectionMarkup.AppendLine('            </dl>')
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                    'KPI' {
                        $KpiTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $RequestedKpiSpan = Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue $null
                        $KpiComponentSpan = if ($null -eq $RequestedKpiSpan) { $KpiSpan } else { [int] $RequestedKpiSpan }
                        if ($KpiComponentSpan -lt 1 -or $KpiComponentSpan -gt 12) { throw 'KPI Span must be between 1 and 12.' }
                        $RawKpiValue = (Get-PSIProperty -InputObject $Properties -Name 'Value')
                        if ($null -eq $RawKpiValue) {
                            $KpiValueText = [string] [char] 0x2014
                        }
                        elseif ($RawKpiValue -is [string] -or $RawKpiValue.GetType().IsValueType) {
                            $KpiValueText = [string] $RawKpiValue
                        }
                        else {
                            $KpiValueText = ConvertTo-Json -InputObject $RawKpiValue -Depth 5 -Compress
                        }
                        $KpiValue = ConvertTo-PSIHtmlEncoded -Value $KpiValueText
                        $KpiSubtitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Subtitle')
                        $KpiTrend = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Trend')
                        $KpiAction = Get-PSIProperty -InputObject $Properties -Name 'Action'
                        $ActionType = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Type')
                        $ActionTarget = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Target')
                        $HasGenericAction = $ActionType -in @('ScrollTo', 'FilterTable') -and -not [string]::IsNullOrWhiteSpace($ActionTarget)
                        if ($ActionType -eq 'FilterTable') {
                            $ActionProperty = [string] (Get-PSIProperty -InputObject $KpiAction -Name 'Property')
                            $ActionValue = Get-PSIProperty -InputObject $KpiAction -Name 'Value'
                            $HasSimpleValue = $null -ne $ActionValue -and ($ActionValue -is [string] -or $ActionValue.GetType().IsValueType)
                            $HasGenericAction = $HasGenericAction -and -not [string]::IsNullOrWhiteSpace($ActionProperty) -and $HasSimpleValue
                        }
                        if ($HasGenericAction) {
                            $NormalizedAction = [ordered]@{ Type = if ($ActionType -eq 'ScrollTo') { 'ScrollTo' } else { 'FilterTable' }; Target = $ActionTarget }
                            if ($ActionType -eq 'FilterTable') {
                                $NormalizedAction['Property'] = $ActionProperty
                                $NormalizedAction['Value'] = $ActionValue
                            }
                            $ActionJson = ConvertTo-Json -InputObject $NormalizedAction -Depth 5 -Compress
                        }
                        else {
                            $ActionJson = ConvertTo-Json -InputObject $KpiAction -Depth 5 -Compress
                        }
                        $ActionAttribute = ConvertTo-PSIHtmlEncoded -Value $ActionJson
                        $KpiFilter = (Get-PSIProperty -InputObject $Properties -Name 'Filter')
                        $KpiFilterAttribute = ''
                        if ($null -ne $KpiFilter -and $KpiFilter.Count -gt 0) {
                            $KpiFilterJson = ConvertTo-Json -InputObject $KpiFilter -Depth 5 -Compress
                            $KpiFilterAttribute = ConvertTo-PSIHtmlEncoded -Value $KpiFilterJson
                        }
                        $KpiIconMarkup = ''
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon'))) {
                            $KpiIconMarkup = Get-PSIIcon -Name ([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon')) -Size 21
                        }
                        $DrillDown = @((Get-PSIProperty -InputObject $Properties -Name 'DrillDown'))
                        $KpiToneClass = if ((Get-PSIProperty -InputObject $Properties -Name 'VisualTone') -eq 'Informational') { ' psi-tone-informational' } else { '' }
                        $IsDrillDown = $DrillDown.Count -gt 0 -and $null -ne $DrillDown[0]
                        $HasFilterAction = -not [string]::IsNullOrEmpty($KpiFilterAttribute)
                        if ($IsDrillDown) {
                            $HasDrillDownComponents = $true
                            $DrillDownJson = ConvertTo-Json -InputObject $DrillDown -Depth 10 -Compress
                            $DrillDownAttribute = ConvertTo-PSIHtmlEncoded -Value $DrillDownJson
                        }
                        if ($IsDrillDown -or $HasFilterAction -or $HasGenericAction) {
                            $DataAttributes = ''
                            if ($IsDrillDown) {
                                $DataAttributes += " data-psi-drilldown data-psi-records=`"$DrillDownAttribute`""
                            }
                            if ($HasFilterAction) {
                                $DataAttributes += " data-psi-filter-action=`"$KpiFilterAttribute`""
                            }
                            $KpiAccessibleText = if ($IsDrillDown) { "View details for {0}: {1}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title'), $KpiValueText } elseif ($HasFilterAction -or $ActionType -eq 'FilterTable') { "Apply filter from {0}: {1}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title'), $KpiValueText } else { "Go to {0}" -f [string] (Get-PSIProperty -InputObject $Properties -Name 'Title') }
                            $KpiAccessibleName = ConvertTo-PSIHtmlEncoded -Value $KpiAccessibleText
                            if ($IsDrillDown) {
                                $DataAttributes += " data-psi-detail-title=`"$KpiTitle`""
                            }
                            [void] $SectionMarkup.AppendLine("          <button type=`"button`" class=`"psi-kpi-card psi-kpi-clickable psi-status-$StatusClass$KpiToneClass`" data-status=`"$Status`" data-action=`"$ActionAttribute`"$DataAttributes aria-label=`"$KpiAccessibleName`" style=`"--psi-component-span: $KpiComponentSpan`">")
                        }
                        else {
                            [void] $SectionMarkup.AppendLine("          <article class=`"psi-kpi-card psi-status-$StatusClass$KpiToneClass`" data-status=`"$Status`" data-action=`"$ActionAttribute`" style=`"--psi-component-span: $KpiComponentSpan`">")
                        }
                        if ($KpiIconMarkup) {
                            [void] $SectionMarkup.AppendLine("            <span class=`"psi-kpi-icon`">$KpiIconMarkup</span>")
                        }
                        [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-title`">$KpiTitle</p>")
                        [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-value`">$KpiValue</p>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Subtitle'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-subtitle`">$KpiSubtitle</p>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Trend'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-kpi-trend`">$KpiTrend</p>")
                        }
                        if ($IsDrillDown -or $HasFilterAction -or $HasGenericAction) {
                            $ViewDetailsIcon = Get-PSIIcon -Name 'arrow' -Size 16
                            $ActionHint = if ($IsDrillDown -or $HasFilterAction) { 'View details' } elseif ($ActionType -eq 'FilterTable') { 'Filter table' } else { 'Go to section' }
                            [void] $SectionMarkup.AppendLine("            <span class=`"psi-kpi-drill-hint`">$ActionHint $ViewDetailsIcon</span>")
                            [void] $SectionMarkup.AppendLine('          </button>')
                        }
                        else {
                            [void] $SectionMarkup.AppendLine('          </article>')
                        }
                    }
                    'Sparkline' {
                        $Series = [double[]] (Get-PSIProperty $Properties 'Values')
                        if ($Series.Count -lt 2) { throw 'Sparkline requires at least two points.' }
                        $Lower = [double] ($Series | Measure-Object -Minimum).Minimum
                        $Upper = [double] ($Series | Measure-Object -Maximum).Maximum
                        $RequestedMinimum = Get-PSIProperty $Properties 'Minimum'
                        $RequestedMaximum = Get-PSIProperty $Properties 'Maximum'
                        if ($null -ne $RequestedMinimum) { $Lower = [double]$RequestedMinimum }
                        if ($null -ne $RequestedMaximum) { $Upper = [double]$RequestedMaximum }
                        if ($Upper -le $Lower) { $Upper = $Lower + 1 }
                        $PointText = [System.Collections.Generic.List[string]]::new()
                        for ($PointIndex = 0; $PointIndex -lt $Series.Count; $PointIndex++) {
                            $X = (100.0 * $PointIndex / ($Series.Count - 1)).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
                            $Clamped = [math]::Max($Lower, [math]::Min($Upper, $Series[$PointIndex]))
                            $Y = (30.0 - (26.0 * ($Clamped - $Lower) / ($Upper - $Lower))).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
                            $PointText.Add("$X,$Y")
                        }
                        $SparkLabel = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty $Properties 'Label')
                        $Current = Get-PSIProperty $Properties 'CurrentValue'
                        if ($null -eq $Current) { $Current = $Series[$Series.Count - 1] }
                        $SparkCurrent = ConvertTo-PSIHtmlEncoded -Value $Current
                        $SparkStatus = Get-PSIStatusPresentation -Status ([string] (Get-PSIProperty $Properties 'Status'))
                        $SparkSpan = [int] (Get-PSIProperty $Properties 'Span')
                        $SparkRange = 'Range: ' + (ConvertTo-PSIHtmlEncoded -Value $Lower) + ' to ' + (ConvertTo-PSIHtmlEncoded -Value $Upper)
                        [void] $SectionMarkup.AppendLine("          <figure class=`"psi-sparkline-panel psi-status-$($SparkStatus.Class)`" style=`"--psi-component-span: $SparkSpan`"><figcaption><span>$SparkLabel</span><strong>$SparkCurrent</strong></figcaption><svg class=`"psi-sparkline-visual`" viewBox=`"0 0 100 34`" preserveAspectRatio=`"none`" role=`"img`" aria-label=`"$SparkLabel trend. $SparkRange`"><polyline points=`"$($PointText -join ' ')`" fill=`"none`" stroke=`"currentColor`" stroke-width=`"2`" vector-effect=`"non-scaling-stroke`" stroke-linecap=`"round`" stroke-linejoin=`"round`"/></svg></figure>")
                    }
                    'EmptyState' {
                        $EmptyTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty $Properties 'Title')
                        $Explanation = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty $Properties 'Explanation')
                        $EmptyIcon = Get-PSIIcon -Name ([string] (Get-PSIProperty $Properties 'Icon')) -Size 24 -Strict
                        $ActionLabel = [string] (Get-PSIProperty $Properties 'ActionLabel')
                        $TargetView = [string] (Get-PSIProperty $Properties 'TargetView')
                        $EmptyAction = ''
                        if ($ActionLabel) {
                            if ($Layout -ne 'Application' -or @($Report.Views | Where-Object { $_.Id -ceq $TargetView }).Count -eq 0) {
                                throw "Empty-state target view '$TargetView' is unavailable."
                            }
                            $SafeAction = ConvertTo-PSIHtmlEncoded -Value $ActionLabel
                            $EmptyAction = "<button type=`"button`" data-psi-empty-target=`"$TargetView`">$SafeAction</button>"
                        }
                        [void] $SectionMarkup.AppendLine("          <div class=`"psi-empty-state`">$EmptyIcon<div><strong>$EmptyTitle</strong><p>$Explanation</p>$EmptyAction</div></div>")
                    }
                    'Insight' {
                        $HasInsightComponents = $true
                        $InsightTitleText = [string] (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $InsightTitle = ConvertTo-PSIHtmlEncoded -Value $InsightTitleText
                        $InsightRawValue = (Get-PSIProperty -InputObject $Properties -Name 'Value')
                        if ($null -eq $InsightRawValue) { $InsightValueText = [string] [char] 0x2014 }
                        elseif ($InsightRawValue -is [string] -or $InsightRawValue.GetType().IsValueType) { $InsightValueText = [string] $InsightRawValue }
                        else { $InsightValueText = ConvertTo-Json -InputObject $InsightRawValue -Depth 5 -Compress }
                        $InsightValue = ConvertTo-PSIHtmlEncoded -Value $InsightValueText
                        $InsightDescription = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $InsightFilter = (Get-PSIProperty -InputObject $Properties -Name 'Filter')
                        $CanOpenEvidence = $null -ne $InsightFilter -and $InsightFilter.Count -gt 0
                        $InsightClasses = "psi-insight-card psi-status-$StatusClass"
                        $InsightSpan = if ($InsightCount -gt 0) { [math]::Max(1, [math]::Floor($Columns / $InsightCount)) } else { 12 }
                        $InsightIcon = ''
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon'))) {
                            $InsightIcon = Get-PSIIcon -Name ([string] (Get-PSIProperty -InputObject $Properties -Name 'Icon')) -Size 20
                        }
                        if ($CanOpenEvidence) {
                            $HasDrillDownComponents = $true
                            $InsightDefinition = Resolve-PSIEvidenceDefinition -Filter $InsightFilter `
                                -EvidenceColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns')) `
                                -ExportColumns @((Get-PSIProperty -InputObject $Properties -Name 'ExportColumns')) `
                                -Labels (Get-PSIProperty -InputObject $Properties -Name 'ColumnLabels')
                            $InsightJson = ConvertTo-Json -InputObject $InsightDefinition -Depth 8 -Compress
                            $InsightAttribute = ConvertTo-PSIHtmlEncoded -Value $InsightJson
                            $InsightAccessibleName = ConvertTo-PSIHtmlEncoded -Value ("View evidence for {0}: {1}" -f $InsightTitleText, $InsightValueText)
                            [void] $SectionMarkup.AppendLine("          <button type=`"button`" class=`"$InsightClasses psi-insight-clickable`" data-status=`"$Status`" data-psi-insight=`"$InsightAttribute`" data-psi-detail-title=`"$InsightTitle`" aria-label=`"$InsightAccessibleName`" style=`"--psi-component-span: $InsightSpan`">")
                        }
                        else {
                            [void] $SectionMarkup.AppendLine("          <article class=`"$InsightClasses`" data-status=`"$Status`" style=`"--psi-component-span: $InsightSpan`">")
                        }
                        if ($InsightIcon) { [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-icon`">$InsightIcon</span>") }
                        [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-title`">$InsightTitle</span>")
                        [void] $SectionMarkup.AppendLine("            <strong class=`"psi-insight-value`">$InsightValue</strong>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Description'))) { [void] $SectionMarkup.AppendLine("            <span class=`"psi-insight-description`">$InsightDescription</span>") }
                        if ($CanOpenEvidence) { [void] $SectionMarkup.AppendLine('            <span class="psi-kpi-drill-hint">View evidence &rarr;</span>') }
                        if ($CanOpenEvidence) { [void] $SectionMarkup.AppendLine('          </button>') } else { [void] $SectionMarkup.AppendLine('          </article>') }
                    }
                    'Finding' {
                        $FindingDomId = $FindingAnchors[$FindingIndex].Id
                        $FindingIndex++
                        $FindingTitleText = [string] (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $FindingTitle = ConvertTo-PSIHtmlEncoded -Value $FindingTitleText
                        $FindingCategory = [string] (Get-PSIProperty -InputObject $Properties -Name 'Category')
                        $FindingDescription = [string] (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $FindingAffectedObject = [string] (Get-PSIProperty -InputObject $Properties -Name 'AffectedObject')
                        $FindingAffectedObjectAttribute = ConvertTo-PSIHtmlEncoded -Value $FindingAffectedObject
                        $FindingImpact = [string] (Get-PSIProperty -InputObject $Properties -Name 'Impact')
                        $FindingRecommendation = [string] (Get-PSIProperty -InputObject $Properties -Name 'Recommendation')
                        $FindingRuleId = [string] (Get-PSIProperty -InputObject $Properties -Name 'RuleId')
                        $FindingSource = [string] (Get-PSIProperty -InputObject $Properties -Name 'Source')
                        $EvidenceDefinition = Resolve-PSIEvidenceDefinition `
                            -TableId ([string] (Get-PSIProperty -InputObject $Properties -Name 'EvidenceTableId')) `
                            -Filter (Get-PSIProperty -InputObject $Properties -Name 'EvidenceFilter') `
                            -EvidenceColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns' -DefaultValue @())) `
                            -ExportColumns @((Get-PSIProperty -InputObject $Properties -Name 'EvidenceColumns' -DefaultValue @())) `
                            -UseVisibleColumns
                        if ($null -ne $EvidenceDefinition -and -not $TableIds.Contains([string] $EvidenceDefinition.tableId)) {
                            Write-Warning "Finding '$FindingTitleText' references missing evidence table '$($EvidenceDefinition.tableId)'; its evidence action was omitted."
                            $EvidenceDefinition = $null
                        }
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-finding-card psi-status-$StatusClass`" id=`"$FindingDomId`" data-status=`"$Status`" data-psi-finding-card data-psi-affected-object=`"$FindingAffectedObjectAttribute`" data-psi-finding-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-finding-heading`">$AppStatusIcon<span class=`"psi-status-badge psi-status-$StatusClass`">$Status</span>")
                        if (-not [string]::IsNullOrWhiteSpace($FindingCategory)) {
                            [void] $SectionMarkup.AppendLine('              <span class="psi-finding-category">' + (ConvertTo-PSIHtmlEncoded -Value $FindingCategory) + '</span>')
                        }
                        [void] $SectionMarkup.AppendLine('            </div>')
                        [void] $SectionMarkup.AppendLine("            <h3>$FindingTitle</h3>")
                        if (-not [string]::IsNullOrWhiteSpace($FindingDescription)) {
                            [void] $SectionMarkup.AppendLine('            <p class="psi-finding-description">' + (ConvertTo-PSIHtmlEncoded -Value $FindingDescription) + '</p>')
                        }
                        if (-not [string]::IsNullOrWhiteSpace($FindingAffectedObject) -or -not [string]::IsNullOrWhiteSpace($FindingImpact)) {
                            [void] $SectionMarkup.AppendLine('            <dl class="psi-finding-details">')
                            if (-not [string]::IsNullOrWhiteSpace($FindingAffectedObject)) {
                                [void] $SectionMarkup.AppendLine('              <div><dt>Affected object</dt><dd>' + (ConvertTo-PSIHtmlEncoded -Value $FindingAffectedObject) + '</dd></div>')
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingImpact)) {
                                [void] $SectionMarkup.AppendLine('              <div><dt>Impact</dt><dd>' + (ConvertTo-PSIHtmlEncoded -Value $FindingImpact) + '</dd></div>')
                            }
                            [void] $SectionMarkup.AppendLine('            </dl>')
                        }
                        if (-not [string]::IsNullOrWhiteSpace($FindingRecommendation)) {
                            [void] $SectionMarkup.AppendLine('            <div class="psi-finding-recommendation"><strong>Recommendation</strong><p>' + (ConvertTo-PSIHtmlEncoded -Value $FindingRecommendation) + '</p></div>')
                        }
                        if ($null -ne $EvidenceDefinition -or -not [string]::IsNullOrWhiteSpace($FindingRuleId) -or -not [string]::IsNullOrWhiteSpace($FindingSource)) {
                            [void] $SectionMarkup.AppendLine('            <footer class="psi-finding-footer">')
                            if ($null -ne $EvidenceDefinition) {
                                $HasDrillDownComponents = $true
                                $HasInsightComponents = $true
                                $EvidenceAttribute = ConvertTo-PSIHtmlEncoded -Value (ConvertTo-Json -InputObject $EvidenceDefinition -Depth 8 -Compress)
                                $EvidenceDescription = ConvertTo-PSIHtmlEncoded -Value $FindingDescription
                                $EvidenceName = ConvertTo-PSIHtmlEncoded -Value ("View evidence for $FindingTitleText")
                                $EvidenceButtonContent = if ($Layout -eq 'Application') { (Get-PSIIcon -Name Document -Size 16 -Strict) + ' View Evidence' } else { 'View Evidence ' + (Get-PSIIcon -Name 'arrow' -Size 15) }
                                [void] $SectionMarkup.AppendLine("              <button type=`"button`" class=`"psi-finding-evidence`" data-psi-insight=`"$EvidenceAttribute`" data-psi-detail-title=`"$FindingTitle`" data-psi-evidence-description=`"$EvidenceDescription`" aria-label=`"$EvidenceName`">$EvidenceButtonContent</button>")
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingRuleId)) {
                                [void] $SectionMarkup.AppendLine('              <span class="psi-finding-meta">Rule: ' + (ConvertTo-PSIHtmlEncoded -Value $FindingRuleId) + '</span>')
                            }
                            if (-not [string]::IsNullOrWhiteSpace($FindingSource)) {
                                [void] $SectionMarkup.AppendLine('              <span class="psi-finding-meta">Source: ' + (ConvertTo-PSIHtmlEncoded -Value $FindingSource) + '</span>')
                            }
                            [void] $SectionMarkup.AppendLine('            </footer>')
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Status' {
                        $Label = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Label')
                        $Message = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Message')
                        [void] $SectionMarkup.AppendLine("          <div class=`"psi-status-panel psi-status-$StatusClass`" data-status=`"$Status`">")
                        if ($Layout -eq 'Application') { [void] $SectionMarkup.AppendLine("            $AppStatusIcon") }
                        else { [void] $SectionMarkup.AppendLine("            <span class=`"psi-status-indicator`" aria-hidden=`"true`"></span>") }
                        [void] $SectionMarkup.AppendLine("            <div><strong>$Status</strong>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Label'))) {
                            [void] $SectionMarkup.AppendLine("              <span class=`"psi-status-label`">$Label</span>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Message'))) {
                            [void] $SectionMarkup.AppendLine("              <p>$Message</p>")
                        }
                        [void] $SectionMarkup.AppendLine('            </div>')
                        [void] $SectionMarkup.AppendLine('          </div>')
                    }
                    'Alert' {
                        $AlertTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $AlertMessage = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Message')
                        $AlertAction = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Action')
                        $Timestamp = (Get-PSIProperty -InputObject $Properties -Name 'Timestamp')
                        $Details = (Get-PSIProperty -InputObject $Properties -Name 'Details')
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-alert psi-status-$StatusClass`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-alert-heading`">$AppStatusIcon<span class=`"psi-alert-severity`">$Status</span><h3>$AlertTitle</h3></div>")
                        [void] $SectionMarkup.AppendLine("            <p>$AlertMessage</p>")
                        if ($null -ne $Timestamp) {
                            $TimestampText = ConvertTo-PSIHtmlEncoded -Value ([string] $Timestamp)
                            [void] $SectionMarkup.AppendLine("            <time class=`"psi-alert-timestamp`">$TimestampText</time>")
                        }
                        if ($null -ne $Details) {
                            if ($Details -is [string] -or $Details.GetType().IsPrimitive) {
                                $DetailsText = [string] $Details
                            }
                            else {
                                $DetailsText = ConvertTo-Json -InputObject $Details -Depth 5 -Compress
                            }
                            $DetailsText = ConvertTo-PSIHtmlEncoded -Value $DetailsText
                            [void] $SectionMarkup.AppendLine("            <details><summary>Details</summary><p>$DetailsText</p></details>")
                        }
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'Action'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-alert-action`"><strong>Suggested action:</strong> $AlertAction</p>")
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Recommendation' {
                        $RecommendationTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $Description = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Description')
                        $ActionText = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'ActionText')
                        [void] $SectionMarkup.AppendLine("          <article class=`"psi-recommendation psi-status-$StatusClass`" data-status=`"$Status`">")
                        [void] $SectionMarkup.AppendLine("            <span class=`"psi-recommendation-severity`">$AppStatusIcon$Status</span>")
                        [void] $SectionMarkup.AppendLine("            <h3>$RecommendationTitle</h3>")
                        [void] $SectionMarkup.AppendLine("            <p>$Description</p>")
                        if (-not [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Properties -Name 'ActionText'))) {
                            [void] $SectionMarkup.AppendLine("            <p class=`"psi-recommendation-action`"><strong>Suggested action:</strong> $ActionText</p>")
                        }
                        [void] $SectionMarkup.AppendLine('          </article>')
                    }
                    'Table' {
                        $HasTableComponents = $true
                        $TableTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $ConfiguredTableId = [string] (Get-PSIProperty -InputObject $Properties -Name 'Id')
                        $TableId = if ([string]::IsNullOrWhiteSpace($ConfiguredTableId)) { 'psi-table-' + [guid]::NewGuid().ToString('N') } else { ConvertTo-PSIHtmlEncoded -Value $ConfiguredTableId }
                        $TableSpan = [int] (Get-PSIProperty -InputObject $Properties -Name 'Span' -DefaultValue 12)
                        if ($TableSpan -lt 1 -or $TableSpan -gt 12) { throw 'Table Span must be between 1 and 12.' }
                        $TableData = @((Get-PSIProperty -InputObject $Properties -Name 'Data'))
                        $TableColumns = @((Get-PSIProperty -InputObject $Properties -Name 'Columns'))
                        $ColumnLabels = (Get-PSIProperty -InputObject $Properties -Name 'ColumnLabels')
                        $Filters = @((Get-PSIProperty -InputObject $Properties -Name 'Filters'))
                        $Conditions = @((Get-PSIProperty -InputObject $Properties -Name 'Conditions' -DefaultValue @()))
                        $NullText = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'NullValueText')
                        $EmptyMessage = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'EmptyMessage')
                        if ($TableData.Count -eq 0 -and $EmptyMessage -eq 'No records match your filters.') { $EmptyMessage = 'No data available.' }
                        $PageSize = [int] (Get-PSIProperty -InputObject $Properties -Name 'PageSize')
                        $SearchEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableSearch')
                        if ($SearchEnabled) { $HasSearchableTableComponents = $true }
                        $SortingEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableSorting')
                        $PaginationEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnablePagination')
                        $ExportEnabled = [bool] (Get-PSIProperty -InputObject $Properties -Name 'EnableExport')
                        $TableExportMarkup = ''
                        $TableExportAttribute = ''
                        if ($ExportEnabled) {
                            $ExportDefinition = [ordered]@{
                                columns = @((Get-PSIProperty -InputObject $Properties -Name 'ExportColumns'))
                                labels = $ColumnLabels
                                formats = @((Get-PSIProperty -InputObject $Properties -Name 'ExportFormats'))
                                fileName = [string] (Get-PSIProperty -InputObject $Properties -Name 'ExportFileName')
                                worksheetName = [string] (Get-PSIProperty -InputObject $Properties -Name 'WorksheetName')
                            }
                            $TableExportAttribute = ' data-psi-export-config="' + (ConvertTo-PSIHtmlEncoded -Value (ConvertTo-Json -InputObject $ExportDefinition -Depth 5 -Compress)) + '"'
                            $TableExportMarkup = Get-PSIExportToolbar -Scope Table -Formats @((Get-PSIProperty -InputObject $Properties -Name 'ExportFormats'))
                        }
                        $ColumnCount = [math]::Max(1, $TableColumns.Count)
                        $EmptyRowHidden = if ($TableData.Count -eq 0) { '' } else { ' hidden' }

                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-table-card`" id=`"$TableId`" data-psi-table=`"true`" data-page-size=`"$PageSize`" data-search-enabled=`"$($SearchEnabled.ToString().ToLowerInvariant())`" data-sort-enabled=`"$($SortingEnabled.ToString().ToLowerInvariant())`" data-pagination-enabled=`"$($PaginationEnabled.ToString().ToLowerInvariant())`"$TableExportAttribute style=`"--psi-component-span: $TableSpan`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-table-heading`"><h3>$TableTitle</h3><span class=`"psi-table-result-count`" data-psi-result-count aria-live=`"polite`">$($TableData.Count) results</span></div>")
                        [void] $SectionMarkup.AppendLine('            <div class="psi-table-toolbar">')
                        if ($SearchEnabled) {
                            [void] $SectionMarkup.AppendLine('              <label class="psi-table-search"><span class="psi-visually-hidden">Search this table</span><input type="search" data-psi-search placeholder="Search records" autocomplete="off"></label>')
                        }
                        if ($Filters.Count -gt 0) {
                            if ($Filters.Count -gt 2) {
                                [void] $SectionMarkup.AppendLine("              <details class=`"psi-table-filter-disclosure`"><summary>Filters ($($Filters.Count))</summary>")
                                [void] $SectionMarkup.AppendLine('                <div class="psi-table-filterbar" data-psi-filterbar>')
                            }
                            else {
                                [void] $SectionMarkup.AppendLine('              <div class="psi-table-filterbar psi-table-filterbar-inline" data-psi-filterbar>')
                            }
                            [void] $SectionMarkup.AppendLine('              <div class="psi-table-filter-controls">')
                            for ($FilterIndex = 0; $FilterIndex -lt $Filters.Count; $FilterIndex++) {
                                $FilterDefinition = $Filters[$FilterIndex]
                                $FilterProperty = ConvertTo-PSIHtmlEncoded -Value $FilterDefinition.Property
                                $FilterLabel = ConvertTo-PSIHtmlEncoded -Value $FilterDefinition.Label
                                $FilterType = [string] $FilterDefinition.Type
                                $FilterElementId = "$TableId-filter-$FilterIndex"
                                $MultipleAttribute = if ($FilterType -eq 'MultiSelect') { ' multiple aria-describedby="psi-filter-help-' + $FilterElementId + '"' } else { '' }
                                [void] $SectionMarkup.AppendLine("                <label class=`"psi-filter-control`" for=`"$FilterElementId`"><span>$FilterLabel</span><select id=`"$FilterElementId`" data-psi-filter-property=`"$FilterProperty`" data-psi-filter-label=`"$FilterLabel`" data-psi-filter-type=`"$FilterType`"$MultipleAttribute>")
                                if ($FilterType -eq 'Select') {
                                    [void] $SectionMarkup.AppendLine('                  <option value="" selected>All</option>')
                                }
                                foreach ($FilterValue in $FilterDefinition.Values) {
                                    $FilterValueText = ConvertTo-PSIHtmlEncoded -Value $FilterValue
                                    [void] $SectionMarkup.AppendLine("                  <option value=`"$FilterValueText`">$FilterValueText</option>")
                                }
                                [void] $SectionMarkup.AppendLine('                </select></label>')
                                if ($FilterType -eq 'MultiSelect') {
                                    [void] $SectionMarkup.AppendLine("                <span class=`"psi-visually-hidden`" id=`"psi-filter-help-$FilterElementId`">Use the selection list to choose one or more values.</span>")
                                }
                            }
                            [void] $SectionMarkup.AppendLine('              </div>')
                            [void] $SectionMarkup.AppendLine('              </div>')
                            if ($Filters.Count -gt 2) { [void] $SectionMarkup.AppendLine('              </details>') }
                        }
                        [void] $SectionMarkup.AppendLine("              $TableExportMarkup")
                        [void] $SectionMarkup.AppendLine('            </div>')
                        if ($Filters.Count -gt 0) {
                            [void] $SectionMarkup.AppendLine('            <div class="psi-active-filter-row" hidden><span class="psi-active-filter-heading">Active filters</span><div class="psi-active-filter-list" data-psi-active-filters aria-live="polite"><span class="psi-active-filter-none">None</span></div><button type="button" class="psi-filter-clear-all" data-psi-clear-filters hidden>Clear all</button></div>')
                        }
                        [void] $SectionMarkup.AppendLine('            <div class="psi-table-scroll" role="region" aria-label="Scrollable table" tabindex="0">')
                        [void] $SectionMarkup.AppendLine("              <table data-psi-table-element id=`"$TableId-data`">")
                        [void] $SectionMarkup.AppendLine('                <thead><tr>')
                        if ($TableColumns.Count -eq 0) {
                            [void] $SectionMarkup.AppendLine('                  <th scope="col">Results</th>')
                        }
                        else {
                            for ($ColumnIndex = 0; $ColumnIndex -lt $TableColumns.Count; $ColumnIndex++) {
                                $ColumnName = [string] $TableColumns[$ColumnIndex]
                                $DisplayName = $ColumnName
                                if ($null -ne $ColumnLabels -and $ColumnLabels.ContainsKey($ColumnName)) {
                                    $DisplayName = [string] $ColumnLabels[$ColumnName]
                                }
                                $DisplayName = ConvertTo-PSIHtmlEncoded -Value $DisplayName
                                $SafeColumnName = ConvertTo-PSIHtmlEncoded -Value $ColumnName
                                if ($SortingEnabled) {
                                    [void] $SectionMarkup.AppendLine("                  <th scope=`"col`" data-psi-column=`"$SafeColumnName`" data-psi-sort-cell aria-sort=`"none`"><button type=`"button`" data-psi-sort=`"$ColumnIndex`">$DisplayName<span class=`"psi-sort-indicator`" aria-hidden=`"true`"></span></button></th>")
                                }
                                else {
                                    [void] $SectionMarkup.AppendLine("                  <th scope=`"col`" data-psi-column=`"$SafeColumnName`">$DisplayName</th>")
                                }
                            }
                        }
                        [void] $SectionMarkup.AppendLine('                </tr></thead>')
                        [void] $SectionMarkup.AppendLine('                <tbody data-psi-table-body>')

                        foreach ($Item in $TableData) {
                            $RowStatus = $null
                            foreach ($Condition in $Conditions) {
                                if ((Get-PSIProperty -InputObject $Condition -Name 'Scope') -eq 'Row' -and (Test-PSICondition -InputObject $Item -Condition $Condition)) {
                                    $RowStatus = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
                                    break
                                }
                            }
                            $RowClass = ''
                            if ($null -ne $RowStatus) {
                                $RowStatusClass = if ($RowStatus -eq 'NotChecked') { 'not-checked' } else { $RowStatus.ToLowerInvariant() }
                                $RowClass = " class=`"psi-row-status-$RowStatusClass`""
                            }
                            [void] $SectionMarkup.AppendLine("                  <tr data-psi-data-row$RowClass>")
                            foreach ($ColumnName in $TableColumns) {
                                $ExplicitCellStatus = $null
                                foreach ($Condition in $Conditions) {
                                    if ((Get-PSIProperty -InputObject $Condition -Name 'Scope') -eq 'Cell' -and
                                        [string]::Equals([string] (Get-PSIProperty -InputObject $Condition -Name 'Property'), [string] $ColumnName, [System.StringComparison]::OrdinalIgnoreCase) -and
                                        (Test-PSICondition -InputObject $Item -Condition $Condition)) {
                                        $ExplicitCellStatus = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
                                        break
                                    }
                                }
                                $ExplicitCellClass = ''
                                if ($null -ne $ExplicitCellStatus) {
                                    $ExplicitCellStatusClass = if ($ExplicitCellStatus -eq 'NotChecked') { 'not-checked' } else { $ExplicitCellStatus.ToLowerInvariant() }
                                    $ExplicitCellClass = "psi-cell-status-$ExplicitCellStatusClass"
                                }
                                $CellValue = Get-PSITableValue -InputObject $Item -Name ([string] $ColumnName)
                                if ($null -eq $CellValue) {
                                    $NullClass = if ($ExplicitCellClass) { "psi-null-value $ExplicitCellClass" } else { 'psi-null-value' }
                                    [void] $SectionMarkup.AppendLine("                    <td class=`"$NullClass`">$NullText</td>")
                                    continue
                                }

                                if ($CellValue -is [string] -or $CellValue.GetType().IsValueType) {
                                    $CellText = [string] $CellValue
                                }
                                else {
                                    $CellText = ConvertTo-Json -InputObject $CellValue -Depth 5 -Compress
                                }

                                if ($ExplicitCellClass) {
                                    $SafeCellText = ConvertTo-PSIHtmlEncoded -Value $CellText
                                    $CellType = [System.Type]::GetTypeCode($CellValue.GetType())
                                    $NumericClass = if ($CellType -in @([System.TypeCode]::Byte, [System.TypeCode]::SByte, [System.TypeCode]::Int16, [System.TypeCode]::UInt16, [System.TypeCode]::Int32, [System.TypeCode]::UInt32, [System.TypeCode]::Int64, [System.TypeCode]::UInt64, [System.TypeCode]::Single, [System.TypeCode]::Double, [System.TypeCode]::Decimal)) { 'psi-numeric-cell ' } else { '' }
                                    $CellTitle = if ($IsCompactFluent) { " title=`"$SafeCellText`"" } else { '' }
                                    [void] $SectionMarkup.AppendLine("                    <td class=`"$NumericClass$ExplicitCellClass`"$CellTitle>$SafeCellText</td>")
                                    continue
                                }

                                $CellStatus = if ($IsCompactFluent) { Get-PSIStatusPresentation -Status $CellText } else { Resolve-PSIStatus -Status $CellText -AllowInvalid }

                                if ($null -ne $CellStatus) {
                                    if ($IsCompactFluent) {
                                        $CellText = ConvertTo-PSIHtmlEncoded -Value $CellStatus.Label
                                        $BadgeIcon = Get-PSIIcon -Name $CellStatus.Icon -Size 12 -Strict
                                        [void] $SectionMarkup.AppendLine("                    <td><span class=`"psi-status-badge psi-status-$($CellStatus.Class)`">$BadgeIcon$CellText</span></td>")
                                    }
                                    else {
                                        $CellStatusClass = if ($CellStatus -eq 'NotChecked') { 'not-checked' } else { $CellStatus.ToLowerInvariant() }
                                        $CellText = ConvertTo-PSIHtmlEncoded -Value $CellStatus
                                        [void] $SectionMarkup.AppendLine("                    <td><span class=`"psi-status-badge psi-status-$CellStatusClass`">$CellText</span></td>")
                                    }
                                }
                                else {
                                    $CellText = ConvertTo-PSIHtmlEncoded -Value $CellText
                                    $CellType = [System.Type]::GetTypeCode($CellValue.GetType())
                                    $NumericTypes = @(
                                        [System.TypeCode]::Byte, [System.TypeCode]::SByte,
                                        [System.TypeCode]::Int16, [System.TypeCode]::UInt16,
                                        [System.TypeCode]::Int32, [System.TypeCode]::UInt32,
                                        [System.TypeCode]::Int64, [System.TypeCode]::UInt64,
                                        [System.TypeCode]::Single, [System.TypeCode]::Double,
                                        [System.TypeCode]::Decimal
                                    )
                                    $CellClass = if ($CellType -in $NumericTypes) { ' class="psi-numeric-cell"' } else { '' }
                                    $CellTitle = if ($IsCompactFluent) { " title=`"$CellText`"" } else { '' }
                                    [void] $SectionMarkup.AppendLine("                    <td$CellClass$CellTitle>$CellText</td>")
                                }
                            }
                            [void] $SectionMarkup.AppendLine('                  </tr>')
                        }

                        $ColSpan = [math]::Max(1, $TableColumns.Count)
                        if ($IsCompactFluent) {
                            $TableEmptyIcon = Get-PSIIcon -Name NavigationSearch -Size 18 -Strict
                            [void] $SectionMarkup.AppendLine("                  <tr class=`"psi-table-empty`" data-psi-empty$EmptyRowHidden><td colspan=`"$ColSpan`"><span class=`"psi-table-empty-content`">$TableEmptyIcon<strong>No results</strong><span>$EmptyMessage</span></span></td></tr>")
                        }
                        else {
                            [void] $SectionMarkup.AppendLine("                  <tr class=`"psi-table-empty`" data-psi-empty$EmptyRowHidden><td colspan=`"$ColSpan`">$EmptyMessage</td></tr>")
                        }
                        [void] $SectionMarkup.AppendLine('                </tbody>')
                        [void] $SectionMarkup.AppendLine('              </table>')
                        [void] $SectionMarkup.AppendLine('            </div>')
                        if ($PaginationEnabled) {
                            [void] $SectionMarkup.AppendLine("            <nav class=`"psi-table-pagination`" data-psi-pagination aria-label=`"Table pages`"><button type=`"button`" data-psi-previous disabled>Previous</button><span data-psi-page-info>Page 1 of 1</span><button type=`"button`" data-psi-next disabled>Next</button></nav>")
                        }
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                    'Chart' {
                        $ChartTitle = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Properties -Name 'Title')
                        $ChartType = [string] (Get-PSIProperty -InputObject $Properties -Name 'ChartType')
                        $ChartResult = ConvertTo-PSIChartMarkup -Properties $Properties
                        $ChartPoints = [int] $ChartResult.DataPointCount
                        $NullValues = [int] $ChartResult.NullValueCount
                        $ChartSummary = "$ChartPoints points"
                        if ($NullValues -gt 0) {
                            $ChartSummary += "; $NullValues null values omitted"
                        }
                        $SafeSummary = ConvertTo-PSIHtmlEncoded -Value $ChartSummary

                        [void] $SectionMarkup.AppendLine("          <section class=`"psi-chart-card`" data-chart-type=`"$ChartType`">")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-chart-heading`"><h3>$ChartTitle</h3><span class=`"psi-chart-summary`">$SafeSummary</span></div>")
                        [void] $SectionMarkup.AppendLine("            <div class=`"psi-chart-visualization`">$($ChartResult.Svg)</div>")
                        if (-not [string]::IsNullOrEmpty([string] $ChartResult.Legend)) {
                            [void] $SectionMarkup.AppendLine("            $($ChartResult.Legend)")
                        }
                        [void] $SectionMarkup.AppendLine('          </section>')
                    }
                }
            }

            [void] $SectionMarkup.AppendLine('        </div>')
        }

        [void] $SectionMarkup.AppendLine('      </section>')
        $SectionIndex++
    }
    if ($IsMultiView -and $OpenViewId) { [void] $SectionMarkup.AppendLine('      </section>') }

    $InteractionScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-interactions.js'
    if (-not (Test-Path -LiteralPath $InteractionScriptPath -PathType Leaf)) {
        throw "The PSInsightHTML interaction script is missing: '$InteractionScriptPath'."
    }
    $TableScript = ''
    if ($HasTableComponents) {
        $TableScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-table.js'
        if (-not (Test-Path -LiteralPath $TableScriptPath -PathType Leaf)) {
            throw "The PSInsightHTML table script is missing: '$TableScriptPath'."
        }
        $TableScript = Get-Content -LiteralPath $TableScriptPath -Raw -ErrorAction Stop
        $TableScript = "  <script>`n$TableScript`n  </script>"
    }
    $InteractionScript = Get-Content -LiteralPath $InteractionScriptPath -Raw -ErrorAction Stop
    $InteractionScript = "  <script>`n$InteractionScript`n  </script>"
    $StatusContractJson = ConvertTo-Json -InputObject ([ordered]@{ values = @($PSIStatusValues); aliases = $PSIStatusAliases }) -Depth 3 -Compress
    $StatusRegistryScript = @"
  <script>
  (function () {
    'use strict';
    var contract = $StatusContractJson;
    window.PSIStatus = {
      normalize: function (value) {
        if (typeof value !== 'string') { return null; }
        var candidate = value.trim().toLowerCase();
        var canonical = contract.values.filter(function (item) { return item.toLowerCase() === candidate; })[0];
        if (canonical) { return canonical; }
        var alias = Object.keys(contract.aliases).filter(function (item) { return item.toLowerCase() === candidate; })[0];
        return alias ? contract.aliases[alias] : null;
      },
      classSuffix: function (status) {
        return status === 'NotChecked' ? 'not-checked' : status.toLowerCase();
      }
    };
  }());
  </script>
"@

    $ExportScript = ''
    if ($HasTableComponents -or $HasInsightComponents -or $EnableReportPrint) {
        $ExportScriptPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets/JavaScript/psi-export.js'
        if (-not (Test-Path -LiteralPath $ExportScriptPath -PathType Leaf)) {
            throw "The PSInsightHTML export script is missing: '$ExportScriptPath'."
        }
        $ExportScript = Get-Content -LiteralPath $ExportScriptPath -Raw -ErrorAction Stop
        $ExportScript = "  <script>`n$ExportScript`n  </script>"
    }

    $DrillDownMarkup = ''
    if ($HasDrillDownComponents) {
        $DrillDownMarkup = @'
    <div class="psi-dialog-backdrop" data-psi-dialog-backdrop hidden>
      <section class="psi-dialog" role="dialog" aria-modal="true" aria-labelledby="psi-dialog-title" aria-describedby="psi-dialog-description psi-dialog-summary" tabindex="-1">
        <header class="psi-dialog-header"><div><p class="psi-eyebrow">Record details</p><h2 id="psi-dialog-title" data-psi-dialog-title>Details</h2></div><button type="button" class="psi-dialog-close" data-psi-dialog-close aria-label="Close details">__CLOSE_ICON__</button></header>
        <p id="psi-dialog-description" class="psi-dialog-description" data-psi-dialog-description></p>
        <p class="psi-dialog-summary" data-psi-dialog-summary aria-live="polite"></p>
        <div class="psi-dialog-tools"><label class="psi-dialog-search"><span>Search evidence</span><input type="search" data-psi-dialog-search autocomplete="off" placeholder="Search these records"></label><details class="psi-dialog-filter-disclosure" data-psi-dialog-filter-disclosure><summary data-psi-dialog-filter-summary>Filters</summary><div class="psi-dialog-filters" data-psi-dialog-filters></div></details></div>
        <div class="psi-dialog-actions"><button type="button" data-psi-dialog-apply hidden>Apply these filters to inventory</button>__EVIDENCE_EXPORT_TOOLBAR__</div>
        <div class="psi-dialog-table-scroll" role="region" aria-label="Evidence records" tabindex="0"><table class="psi-dialog-table"><thead data-psi-dialog-head></thead><tbody data-psi-dialog-body></tbody></table></div>
        <nav class="psi-dialog-pagination" data-psi-dialog-pagination aria-label="Evidence pages"><button type="button" data-psi-dialog-previous>Previous</button><span data-psi-dialog-page></span><button type="button" data-psi-dialog-next>Next</button></nav>
        <p class="psi-dialog-empty" data-psi-dialog-empty hidden>No records match this filter.</p>
      </section>
    </div>
'@
        $CloseIcon = if ($Layout -eq 'Application') { Get-PSIIcon -Name AppClose -Size 20 -Strict } else { Get-PSIIcon -Name 'close' -Size 20 }
        $DrillDownMarkup = $DrillDownMarkup.Replace('__CLOSE_ICON__', $CloseIcon)
        $DrillDownMarkup = $DrillDownMarkup.Replace('__EVIDENCE_EXPORT_TOOLBAR__', (Get-PSIExportToolbar -Scope Evidence))
    }

    $ReportExportMarkup = if ($EnableReportPrint) {
        if ($Layout -eq 'Application') { Get-PSIExportToolbar -Scope Report -Formats @('Print') -UseFluentIcons }
        else { Get-PSIExportToolbar -Scope Report -Formats @('Print') }
    } else { '' }

    if ($Layout -eq 'Application') {
        return ConvertTo-PSIApplicationShell -Report $Report -Styles $ThemeStylesheet -Sections $SectionMarkup.ToString() `
            -Navigation $ApplicationNavigation -Dialog $DrillDownMarkup -ExportToolbar $ReportExportMarkup `
            -ExportScript $ExportScript -StatusScript $StatusRegistryScript -InteractionScript $InteractionScript `
            -EnableReportPrint $EnableReportPrint `
            -TableScript $TableScript -HasTableSearch $HasSearchableTableComponents -IsMultiView $IsMultiView `
            -HasRelationshipComponents $HasRelationshipComponents
    }

    if ($null -ne $Report.PSObject.Properties['Assessments'] -and $Report.Assessments.Count -gt 0) {
        $NavigationContainerMarkup = @"
    <div class="psi-navigation-stack" data-psi-navigation-stack>
      <nav class="psi-assessment-nav" aria-label="Assessment groups">
$($AssessmentNavigationMarkup.ToString())    </nav>
      <details class="psi-section-nav-details">
        <summary>All sections ($($SectionsProperty.Value.Count))</summary>
        <nav class="psi-report-nav" aria-label="Report sections">
$($NavigationMarkup.ToString())        </nav>
      </details>
    </div>
"@
    }
    else {
        $NavigationContainerMarkup = @"
    <div class="psi-navigation-stack" data-psi-navigation-stack>
      <nav class="psi-report-nav" aria-label="Report sections">
$($NavigationMarkup.ToString())      </nav>
    </div>
"@
    }

    @"
<!DOCTYPE html>
<html lang="en" data-theme="$Theme">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$Title</title>
  <style>
    $ThemeStylesheet
  </style>
</head>
<body>
  <main class="psi-shell">
    <header class="psi-header">
      <div class="psi-header-main">
        <div class="psi-header-copy">
          <p class="psi-eyebrow">PSInsightHTML Report</p>
          <h1>$Title</h1>
          <p class="psi-subtitle">$Subtitle</p>
          <div class="psi-report-meta" aria-label="Report metadata">
            <span>Generated $GeneratedOn</span>
            <span>Module v$ModuleVersion</span>
            <span>Theme <span data-psi-theme-value>$Theme</span></span>
          </div>
        </div>
        <div class="psi-brand" aria-label="PSInsightHTML">
          <svg class="psi-brand-mark" viewBox="0 0 48 48" role="img" aria-label="PSInsightHTML abstract logo"><path d="M24 3 43 14v20L24 45 5 34V14L24 3Z" fill="none" stroke="var(--psi-logo-primary)" stroke-width="2.5"/><path d="M15 31V17h8a5 5 0 0 1 0 10h-4M27 31h7M27 31a4 4 0 0 1 0-8h7" fill="none" stroke="var(--psi-logo-secondary)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><circle cx="35" cy="17" r="2" fill="var(--psi-logo-primary)"/></svg>
          <span>PSInsightHTML</span>
        </div>
      </div>
      <div class="psi-header-actions">
      <div class="psi-theme-control" role="group" aria-label="Report color theme">
        <button type="button" data-psi-theme="Light" aria-pressed="false">$(Get-PSIIcon -Name 'theme/light' -Size 16)<span>Light</span></button>
        <button type="button" data-psi-theme="Dark" aria-pressed="false">$(Get-PSIIcon -Name 'theme/dark' -Size 16)<span>Dark</span></button>
        <button type="button" data-psi-theme="Auto" aria-pressed="false"><span class="psi-theme-auto-icon">$(Get-PSIIcon -Name 'settings' -Size 16)</span><span>Auto</span></button>
      </div>
      $ReportExportMarkup
      </div>
    </header>
    $NavigationContainerMarkup
$($SectionMarkup.ToString())
    <footer class="psi-footer"><span>Generated by PSInsightHTML</span><span>Module v$ModuleVersion &middot; Theme <span data-psi-theme-footer>$Theme</span></span></footer>
  </main>
    $DrillDownMarkup
    $ExportScript
    $StatusRegistryScript
    $InteractionScript
    $TableScript
</body>
</html>
"@
}
#endregion

#region Private/ConvertTo-PSIHtmlEncoded.ps1
function ConvertTo-PSIHtmlEncoded {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object] $Value
    )

    process {
        if ($null -eq $Value) { return '' }
        [System.Net.WebUtility]::HtmlEncode([string] $Value)
    }
}
#endregion

#region Private/ConvertTo-PSIIntelligenceDetailHtml.ps1
function ConvertTo-PSIIntelligenceDetailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Finding','Resource','Evidence')][string] $Kind,
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $TitleField = switch ($Kind) { Finding { 'Title' } Resource { 'Name' } Evidence { 'Title' } }
    $Title = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record -Name $TitleField)
    $IconName = switch ($Kind) { Finding { 'SeverityWarning' } Resource { 'ResourceServer' } Evidence { 'Document' } }
    $Icon = Get-PSIIcon -Name $IconName
    $FindingView = [string] $LinkViews.Finding
    $ResourceView = [string] $LinkViews.Resource
    $EvidenceView = [string] $LinkViews.Evidence
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">$Kind investigation</p><h4>$Title</h4></div></header>")
    if ($Kind -eq 'Finding') {
        $Severity = ConvertTo-PSIHtmlEncoded -Value $Record.Severity
        $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
        $Category = ConvertTo-PSIHtmlEncoded -Value $Record.Category
        $Summary = ConvertTo-PSIHtmlEncoded -Value $Record.Summary
        $BadgeClass = if ($Record.Severity -eq 'Info') { 'informational' } else { ([string] $Record.Severity).ToLowerInvariant() }
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span class=`"psi-status-badge psi-status-$BadgeClass`">$Severity</span><span>$Status</span><span>$Category</span></div><p class=`"psi-intelligence-summary`">$Summary</p>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Affected resources</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.AffectedResourceIds) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        [void] $B.AppendLine('</section>')
        $Expected = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name ExpectedState -DefaultValue 'Not specified')
        $Observed = ConvertTo-PSIHtmlEncoded -Value $Record.ReadinessImpact
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Observed / Expected</h5><dl><div><dt>Observed impact</dt><dd>$Observed</dd></div><div><dt>Expected state</dt><dd>$Expected</dd></div></dl></section>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View $EvidenceView -LabelProperty Title))
        [void] $B.AppendLine('</section>')
        $Action = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Action -DefaultValue 'Not specified')
        $Rationale = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Rationale -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Recommendation</h5><p>$Action</p><small>$Rationale</small></section>")
        $Method = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name Method -DefaultValue 'Not specified')
        $Result = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name ExpectedResult -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Validation</h5><p>$Method</p><small>$Result</small></section>")
        if (@($Record.Relationships).Count) {
            [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Relationships</h5>')
            foreach ($Id in @($Record.Relationships)) {
                $Relationship = @($Model.Relationships | Where-Object { $_.Id -ieq [string] $Id })[0]
                if ($null -ne $Relationship) { [void] $B.AppendLine('<p>' + (ConvertTo-PSIHtmlEncoded -Value "$($Relationship.Type): $($Relationship.SourceResourceId) -> $($Relationship.TargetResourceId)") + '</p>') }
            }
            [void] $B.AppendLine('</section>')
        }
    }
    elseif ($Kind -eq 'Resource') {
        $Type = ConvertTo-PSIHtmlEncoded -Value $Record.Type
        $Status = Resolve-PSIStatus -Status ([string] $Record.Status)
        $BadgeClass = if ($Status -eq 'NotChecked') { 'not-checked' } else { $Status.ToLowerInvariant() }
        $SafeStatus = ConvertTo-PSIHtmlEncoded -Value $Status
        $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span>$Type</span><span class=`"psi-status-badge psi-status-$BadgeClass`">$SafeStatus</span></div><p class=`"psi-intelligence-summary`">$Description</p>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Properties</h5><dl>')
        foreach ($Key in @($Record.Properties.Keys | Sort-Object)) {
            $SafeKey = ConvertTo-PSIHtmlEncoded -Value $Key
            $SafeValue = ConvertTo-PSIHtmlEncoded -Value $Record.Properties[$Key]
            [void] $B.AppendLine("<div><dt>$SafeKey</dt><dd>$SafeValue</dd></div>")
        }
        [void] $B.AppendLine('</dl></section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View $FindingView -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View $EvidenceView -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Relationships</h5>')
        foreach ($Id in @($Record.RelationshipIds)) {
            $Relationship = @($Model.Relationships | Where-Object { $_.Id -ieq [string] $Id })[0]
            if ($null -eq $Relationship) { continue }
            $OtherId = if ($Relationship.SourceResourceId -ieq $Record.Id) { $Relationship.TargetResourceId } else { $Relationship.SourceResourceId }
            [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($OtherId) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        }
        [void] $B.AppendLine('</section>')
    }
    else {
        $Type = ConvertTo-PSIHtmlEncoded -Value $Record.Type
        $Source = ConvertTo-PSIHtmlEncoded -Value $Record.Source
        $Summary = ConvertTo-PSIHtmlEncoded -Value $Record.Summary
        $Timestamp = if ($Record.CollectedAt) { ConvertTo-PSIHtmlEncoded -Value ([datetime] $Record.CollectedAt).ToString('yyyy-MM-dd HH:mm') } else { 'Not supplied' }
        [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span>$Type</span><span>$Source</span><span>$Timestamp</span></div><p class=`"psi-intelligence-summary`">$Summary</p>")
        $RawData = if ($Record.Data -is [string]) { [string] $Record.Data } else { ConvertTo-Json -InputObject $Record.Data -Depth 8 }
        $SafeData = ConvertTo-PSIHtmlEncoded -Value $RawData
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Observed data</h5><pre>$SafeData</pre></section><section class=`"psi-intelligence-block`"><h5>Resources</h5>")
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View $ResourceView -LabelProperty Name))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View $FindingView -LabelProperty Title))
        [void] $B.AppendLine('</section>')
    }
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIIntelligenceLinksHtml.ps1
function ConvertTo-PSIIntelligenceLinksHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Ids,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Records,
        [Parameter(Mandatory = $true)][string] $View,
        [Parameter(Mandatory = $true)][string] $LabelProperty
    )
    if ($Ids.Count -eq 0) { return '<p class="psi-intelligence-muted">None linked in this sample.</p>' }
    $Builder = [System.Text.StringBuilder]::new()
    [void] $Builder.Append('<div class="psi-intelligence-links">')
    foreach ($Id in $Ids) {
        $Record = @($Records | Where-Object { $_.Id -ieq [string] $Id })[0]
        if ($null -eq $Record) { continue }
        $SafeId = ConvertTo-PSIHtmlEncoded -Value $Id
        $Label = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record -Name $LabelProperty)
        [void] $Builder.Append("<button type=`"button`" class=`"psi-intelligence-link`" data-psi-cross-view=`"$View`" data-psi-cross-id=`"$SafeId`">$Label <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $Builder.Append('</div>')
    $Builder.ToString()
}
#endregion

#region Private/ConvertTo-PSIPrintProjection.ps1
function ConvertTo-PSIPrintProjection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    function E($Value) { ConvertTo-PSIHtmlEncoded -Value $Value }
    function V($Object, $Name, $Fallback = '') {
        $Value = Get-PSIProperty -InputObject $Object -Name $Name -DefaultValue $Fallback
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) { return $Fallback }
        return $Value
    }
    function Status($Value) {
        '<span class="psi-print-status">' + (E $Value) + '</span>'
    }
    function ReasonText($Value) {
        $Text = [string] $Value
        $Text = $Text.Replace('1 blocking checks require action.', '1 blocking check requires action.')
        $Text = $Text.Replace('1 open critical findings affect this assessment.', '1 open critical finding affects this assessment.')
        $Text = $Text.Replace('1 checks are blocked.', '1 check is blocked.')
        $Text = $Text.Replace('1 checks were not tested', '1 check was not tested')
        $Text = $Text.Replace('1 checks have unknown results', '1 check has an unknown result')
        $Text = $Text.Replace('1 checks require review and contribute half credit.', '1 check requires review and contributes half credit.')
        $Text = $Text.Replace('1 not-applicable checks are excluded', '1 not-applicable check is excluded')
        return $Text
    }
    function TextLine($Label, $Value) {
        if ([string]::IsNullOrWhiteSpace([string] $Value)) { return '' }
        '<div><dt>' + (E $Label) + '</dt><dd>' + (E $Value) + '</dd></div>'
    }
    function Section($Id, $Number, $Title) {
        '<section class="psi-print-section" id="psi-print-' + $Id + '"><header class="psi-print-section-heading"><span>' + $Number + '</span><h2>' + (E $Title) + '</h2></header>'
    }
    function Row($Cells) {
        '<tr>' + ((@($Cells) | ForEach-Object { '<td>' + $_ + '</td>' }) -join '') + '</tr>'
    }
    function Table($Headers, $Rows) {
        '<table><thead><tr>' + ((@($Headers) | ForEach-Object { '<th scope="col">' + (E $_) + '</th>' }) -join '') + '</tr></thead><tbody>' + ($Rows -join "`n") + '</tbody></table>'
    }

    $B = [System.Text.StringBuilder]::new()
    $Assessment = V $Report 'ApplicationAssessment' $null
    $Model = V $Report 'ApplicationModel' $null
    $Meta = if ($null -ne $Assessment) { V $Assessment 'Metadata' @{} } else { @{} }
    $PrintConfig = V $Meta 'Print' @{}
    $ReportPrintConfig = if ($null -eq $Assessment) { V $Report 'PrintDisplay' $null } else { $null }
    $PrintDisplay = Resolve-PSIPrintDisplay -Configuration $(if ($null -ne $Assessment) { V $Meta 'PrintDisplay' $null } else { $ReportPrintConfig }) -LegacyConfiguration $PrintConfig
    $ReportTitle = [string] (V $Report 'Title')
    $Target = if ($null -ne $Assessment) { [string] (V $Assessment 'Target') } else { '' }
    $Generated = ([datetime] $Report.GeneratedOn).ToString('yyyy-MM-dd HH:mm zzz')
    $Version = [string] (V $Report 'ModuleVersion')
    $Decision = if ($null -ne $Assessment) { [string] (V $Assessment 'Decision' 'Unknown') } else { 'Report' }
    $Score = if ($null -ne $Assessment -and $null -ne $Assessment.Score) { "$($Assessment.Score)%" } else { 'Not scored' }
    $ScoreLabel=if ($null -eq $Assessment) { 'Assessment score' } else { switch ([string](V $Assessment 'AssessmentType')) { 'Readiness' { 'Readiness score' } 'Health' { 'Health score' } 'Security' { 'Security score' } default { 'Assessment score' } } }
    $Coverage = if ($null -ne $Assessment) { V $Meta 'EvidenceCoveragePercent' $null } else { V $ReportPrintConfig 'CoveragePercent' $null }
    $CoverageText = if ($null -ne $Coverage) { "$Coverage%" } else { 'Not supplied' }
    $FindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ResourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $EvidenceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Assessment) {
        foreach ($Id in @($Assessment.FindingIds)) { [void] $FindingIds.Add([string] $Id) }
        foreach ($Id in @($Assessment.ResourceIds)) { [void] $ResourceIds.Add([string] $Id) }
        foreach ($Id in @($Assessment.EvidenceIds)) { [void] $EvidenceIds.Add([string] $Id) }
    }
    $Findings = if ($null -ne $Model) { @($Model.Findings | Where-Object { $null -eq $Assessment -or $FindingIds.Contains([string] $_.Id) } | Sort-Object @{ Expression = { if ($_.Status -eq 'NotTested') { 4 } elseif ($_.Status -in @('Resolved','AcceptedRisk','NotApplicable')) { 5 } else { switch ($_.Severity) { Critical { 0 } Warning { 1 } Info { 2 } default { 3 } } } } }, Title) } else { @() }
    $Resources = if ($null -ne $Model) { @($Model.Resources | Where-Object { $null -eq $Assessment -or $ResourceIds.Contains([string] $_.Id) }) } else { @() }
    $Evidence = if ($null -ne $Model) { @($Model.Evidence | Where-Object { $null -eq $Assessment -or $EvidenceIds.Contains([string] $_.Id) }) } else { @() }
    $Checks = if ($null -ne $Assessment) { @($Assessment.Checks) } else { @() }
    $EvidenceChecks = @{}
    foreach ($Check in $Checks) {
        foreach ($Id in @($Check.EvidenceIds)) {
            if (-not $EvidenceChecks.ContainsKey([string] $Id)) { $EvidenceChecks[[string] $Id] = [System.Collections.Generic.List[string]]::new() }
            $EvidenceChecks[[string] $Id].Add([string] $Check.Id)
        }
    }
    $Categories = if ($null -ne $Assessment) { @($Assessment.Categories) } else { @() }
    $Exceptions = if ($null -ne $Assessment) { @($Assessment.Exceptions) } else { @() }
    $Sections = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Assessment) {
        foreach ($Entry in @(@('summary','Executive summary'),@('posture','Assessment posture'),@('scope','Scope'),@('top-findings','Top findings'),@('categories','Category summary'),@('checks','Checks summary'),@('findings','Detailed findings'),@('resources','Resources summary'),@('evidence','Evidence appendix'),@('exceptions','Exceptions'),@('methodology','Methodology and coverage'),@('metadata','Report metadata'))) {
            if ($Entry[0] -eq 'top-findings' -and $Findings.Count -eq 0) { continue }
            if ($Entry[0] -eq 'findings' -and $Findings.Count -eq 0) { continue }
            if ($Entry[0] -eq 'resources' -and $Resources.Count -eq 0) { continue }
            if ($Entry[0] -eq 'evidence' -and ($Evidence.Count -eq 0 -or (V $PrintConfig 'IncludeEvidenceAppendix' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'checks' -and ($Checks.Count -eq 0 -or (V $PrintConfig 'IncludeChecks' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'exceptions' -and ($Exceptions.Count -eq 0 -or (V $PrintConfig 'IncludeExceptions' $true) -eq $false)) { continue }
            if ($Entry[0] -eq 'categories' -and $Categories.Count -eq 0) { continue }
            $Sections.Add($Entry)
        }
    }
    else {
        foreach ($Entry in @(@('summary','Report summary'),@('scope','Sections'))) { $Sections.Add($Entry) }
        if (@(V $ReportPrintConfig 'Tables' @()).Count -gt 0) { $Sections.Add(@('inventory-tables',[string](V $ReportPrintConfig 'TableSectionTitle' 'Inventory tables'))) }
        $Sections.Add(@('metadata','Report metadata'))
    }

    [void] $B.AppendLine('<article class="psi-print-document" id="psi-print-document" aria-label="Printable report" hidden>')
    [void] $B.AppendLine('<header class="psi-print-running"><strong>' + (E $ReportTitle) + '</strong><span>' + (E $Target) + ' | ' + (E $Generated) + ' | PSInsightHTML v' + (E $Version) + '</span></header>')
    [void] $B.AppendLine('<section class="psi-print-cover"><p class="psi-print-kicker">' + (E $PrintDisplay.ReportIdentity) + '</p><h1>' + (E $ReportTitle) + '</h1><p class="psi-print-subtitle">' + (E (V $Report 'Subtitle')) + '</p>')
    if ($null -ne $Assessment) { [void] $B.AppendLine('<p class="psi-print-assessment">' + (E (V $Assessment 'Name')) + '</p>') }
    if ($null -ne $Assessment) {
        [void] $B.AppendLine('<dl class="psi-print-cover-grid">' + (TextLine 'Target' $Target) + (TextLine 'Scope' (V $Assessment 'Scope')) + (TextLine 'Decision' $Decision) + (TextLine $ScoreLabel $Score) + (TextLine 'Evidence coverage' $CoverageText) + (TextLine 'Generated' $Generated) + (TextLine 'Module version' $Version) + '</dl><p class="psi-print-cover-foot">Standalone report | Complete assessment snapshot</p></section>')
    } else {
        [void] $B.AppendLine('<dl class="psi-print-cover-grid">' + (TextLine 'Scope' (V $ReportPrintConfig 'Scope')) + (TextLine 'Collection profile' (V $ReportPrintConfig 'Profile')) + (TextLine 'Evidence coverage' $CoverageText) + (TextLine 'Generated' $Generated) + (TextLine 'Module version' $Version) + '</dl><p class="psi-print-cover-foot">' + (E (V $ReportPrintConfig 'CoverFoot' 'Standalone report | Inventory observations')) + '</p></section>')
    }
    [void] $B.AppendLine('<nav class="psi-print-contents" aria-label="Document contents"><h2>Contents</h2><ol>')
    for ($I=0; $I -lt $Sections.Count; $I++) { [void] $B.AppendLine('<li><a href="#psi-print-' + $Sections[$I][0] + '"><span>' + ($I+1) + '</span>' + (E $Sections[$I][1]) + '</a></li>') }
    [void] $B.AppendLine('</ol></nav>')
    $Number = 0
    foreach ($Entry in $Sections) {
        $Number++
        $Id = $Entry[0]
        [void] $B.AppendLine((Section $Id ('{0:d2}' -f $Number) $Entry[1]))
        switch ($Id) {
            'summary' {
                if ($null -ne $Assessment) {
                    $Counts = $Assessment.ScoreExplanation.Counts
                    [void] $B.AppendLine('<p class="psi-print-lead">' + (E (V $Assessment 'Description')) + '</p><dl class="psi-print-metrics">' + (TextLine 'Decision' $Decision) + (TextLine 'Score' $Score) + (TextLine 'Coverage' $CoverageText) + (TextLine 'Blockers' $Counts.Blockers) + (TextLine 'Review' $Counts.Review) + (TextLine 'Ready' $Counts.Ready) + (TextLine 'Not Tested' $Counts.NotTested) + '</dl>')
                    [void] $B.AppendLine('<h3>Primary reasons</h3><ul>')
                    foreach ($Reason in @($Assessment.ScoreExplanation.Reasons)) { [void] $B.AppendLine('<li>' + (E (ReasonText $Reason)) + '</li>') }
                    [void] $B.AppendLine('</ul><h3>Recommended next actions</h3><ul>')
                    foreach ($Action in @($Assessment.Recommendations)) { [void] $B.AppendLine('<li>' + (E $Action) + '</li>') }
                    [void] $B.AppendLine('</ul>')
                } else { [void] $B.AppendLine('<p class="psi-print-lead">' + (E (V $Report 'Subtitle')) + '</p><p>Observed records are presented without an assessment score or health verdict.</p>') }
            }
            'posture' { [void] $B.AppendLine('<dl class="psi-print-facts">' + (TextLine 'Overall decision' $Decision) + (TextLine 'Score' $Score) + (TextLine 'Assessment profile' (V $Assessment 'Profile')) + (TextLine 'Applicable checks' ($Checks.Count - $Assessment.ScoreExplanation.Counts.NotApplicable)) + (TextLine 'Not applicable' $Assessment.ScoreExplanation.Counts.NotApplicable) + '</dl><p>' + (E $Assessment.ScoreExplanation.CategoryFormula) + '</p>') }
            'scope' {
                if ($null -ne $Assessment) { [void] $B.AppendLine('<p>' + (E (V $Assessment 'Scope')) + '</p><dl class="psi-print-facts">' + (TextLine 'Target' $Target) + (TextLine 'Assessment type' (V $Assessment 'AssessmentType')) + (TextLine 'Profile' (V $Assessment 'Profile')) + (TextLine 'Linked resources' $Resources.Count) + (TextLine 'Linked evidence records' $Evidence.Count) + '</dl>') }
                else { [void] $B.AppendLine('<ul>'); foreach ($Part in $Report.Sections) { [void] $B.AppendLine('<li>' + (E $Part.Title) + '</li>') }; [void] $B.AppendLine('</ul>') }
            }
            'inventory-tables' {
                $SelectedIds = @(V $ReportPrintConfig 'Tables' @())
                foreach ($Part in $Report.Sections) {
                    foreach ($ReportRow in $Part.Rows) {
                        foreach ($Component in $ReportRow.Components) {
                            if ($Component.Type -ne 'Table' -or $Component.Properties.Id -notin $SelectedIds) { continue }
                            $Properties=$Component.Properties
                            $Columns=@($Properties.Columns | Select-Object -First 7)
                            [void] $B.AppendLine('<h3>' + (E $Properties.Title) + '</h3>')
                            $Headers=@(foreach ($Column in $Columns) { if ($Properties.ColumnLabels.ContainsKey([string]$Column)) { [string]$Properties.ColumnLabels[[string]$Column] } else { [string]$Column } })
                            $TableRows=@(foreach ($Record in @($Properties.Data)) {
                                $Cells=@(foreach ($Column in $Columns) {
                                    $Value=Get-PSIProperty -InputObject $Record -Name ([string]$Column) -DefaultValue $null
                                    if ($null -eq $Value) { '' } elseif ($Value -is [array]) { E ($Value -join ', ') } else { E $Value }
                                })
                                Row $Cells
                            })
                            [void] $B.AppendLine((Table $Headers $TableRows))
                        }
                    }
                }
            }
            'top-findings' {
                [void] $B.AppendLine('<ol class="psi-print-priority">')
                foreach ($Finding in @($Findings | Select-Object -First 6)) { [void] $B.AppendLine('<li><strong>' + (E $Finding.Title) + '</strong> ' + (Status $Finding.Severity) + '<span>' + (E $Finding.Category) + '</span><p>' + (E $Finding.Summary) + '</p></li>') }
                [void] $B.AppendLine('</ol>')
            }
            'categories' {
                $Rows = @()
                foreach ($Category in $Categories) {
                    $Members = @($Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
                    $Cells = @((E $Category.Name), (E $(if ($null -eq $Category.Score) { 'N/A' } else { "$($Category.Score)%" })), (Status $Category.Status))
                    foreach ($State in @('Ready','Review','Blocked','NotTested')) { $Cells += [string] @($Members | Where-Object { $_.Status -eq $State }).Count }
                    $Rows += Row $Cells
                }
                [void] $B.AppendLine((Table @('Category','Score','Status','Ready','Review','Blocked','Not Tested') $Rows))
            }
            'checks' {
                [void] $B.AppendLine('<p>' + $Checks.Count + ' checks in the complete assessment. Status labels remain readable in grayscale.</p>')
                foreach ($Category in $Categories) {
                    $Members = @($Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
                    if ($Members.Count -eq 0) { continue }
                    [void] $B.AppendLine('<h3>' + (E $Category.Name) + '</h3>')
                    $Rows = @()
                    foreach ($Check in $Members) {
                        $Cells = foreach ($Field in $PrintDisplay.Checks) {
                            $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Checks -Record $Check -Property $Field.Property) -Format $Field.Format
                            if ($Field.Format -eq 'Status' -and $Value) { Status $Value } else { E $Value }
                        }
                        $Rows += Row $Cells
                    }
                    [void] $B.AppendLine((Table @($PrintDisplay.Checks | ForEach-Object { $_.Label }) $Rows))
                }
            }
            'findings' {
                foreach ($Finding in $Findings) {
                    $Facts = [System.Text.StringBuilder]::new()
                    foreach ($Field in $PrintDisplay.Findings) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Findings -Record $Finding -Property $Field.Property) -Format $Field.Format
                        if ($Value) { [void] $Facts.Append((TextLine $Field.Label $Value)) }
                    }
                    [void] $B.AppendLine('<article class="psi-print-finding"><h3>' + (E $Finding.Title) + '</h3><p class="psi-print-record-meta">' + (E $Finding.Id) + ' | ' + (E $Finding.Category) + ' | ' + (Status $Finding.Severity) + ' | ' + (Status $Finding.Status) + '</p><p>' + (E $Finding.Summary) + '</p><dl class="psi-print-facts">' + $Facts.ToString() + '</dl></article>')
                }
            }
            'resources' {
                $Columns = @($PrintDisplay.Resources)
                $Rows = @()
                foreach ($Resource in $Resources) {
                    $Cells = foreach ($Column in $Columns) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Resources -Record $Resource -Property $Column.Property) -Format $Column.Format
                        if ($Column.Format -eq 'Status' -and $Value) { Status $Value } else { E $Value }
                    }
                    $Rows += Row $Cells
                }
                [void] $B.AppendLine((Table @($Columns | ForEach-Object { $_.Label }) $Rows))
            }
            'evidence' {
                [void] $B.AppendLine('<p>Summaries and references only. Raw evidence Data payloads are excluded.</p>')
                foreach ($Item in $Evidence) {
                    $CheckIds = if ($EvidenceChecks.ContainsKey([string] $Item.Id)) { @($EvidenceChecks[[string] $Item.Id]) } else { @() }
                    $Facts = [System.Text.StringBuilder]::new()
                    foreach ($Field in $PrintDisplay.Evidence) {
                        $Value = Format-PSIPrintField -Value (Get-PSIPrintFieldValue -Kind Evidence -Record $Item -Property $Field.Property -CheckIds $CheckIds) -Format $Field.Format
                        if ($Value) { [void] $Facts.Append((TextLine $Field.Label $Value)) }
                    }
                    [void] $B.AppendLine('<article class="psi-print-evidence"><h3>' + (E $Item.Title) + '</h3><dl class="psi-print-facts">' + $Facts.ToString() + '</dl></article>')
                }
            }
            'exceptions' {
                foreach ($Item in $Exceptions) { [void] $B.AppendLine('<article class="psi-print-finding"><h3>' + (E $Item.Title) + '</h3><dl class="psi-print-facts">' + (TextLine 'Status' $Item.Status) + (TextLine 'Scope' (@($Item.ResourceIds) -join ', ')) + (TextLine 'Reason' $Item.Reason) + (TextLine 'Owner' $Item.Owner) + (TextLine 'Expires' $(if ($null -ne $Item.ExpiresAt) { ([datetime] $Item.ExpiresAt).ToString('yyyy-MM-dd') } else { '' })) + (TextLine 'Check' $Item.CheckId) + (TextLine 'Finding' $Item.FindingId) + '</dl></article>') }
            }
            'methodology' {
                [void] $B.AppendLine('<p>Evidence coverage: <strong>' + (E $CoverageText) + '</strong>. Coverage describes requested observations available for review; it is separate from ' + (E $ScoreLabel.ToLowerInvariant()) + '. Missing or partial evidence limits interpretation and should be reviewed before approval.</p>')
                $Collection = V $Meta 'CollectionCounts' $null
                if ($null -ne $Collection) { [void] $B.AppendLine('<dl class="psi-print-facts">'); foreach ($Field in @('Requested','Collected','Partial','Failed','NotSupported','NotTested','NotRequested')) { [void] $B.AppendLine((TextLine $Field (V $Collection $Field))) }; [void] $B.AppendLine('</dl>') }
                [void] $B.AppendLine('<p>Scoring: ' + (E $Assessment.ScoreExplanation.CategoryFormula) + ' Not Applicable checks are excluded. Not Tested and Unknown checks score zero until assessed.</p>')
                $Method = V $PrintConfig 'MethodologyText' ''
                if ($Method) { [void] $B.AppendLine('<p>' + (E $Method) + '</p>') }
            }
            'metadata' {
                [void] $B.AppendLine('<dl class="psi-print-facts">' + (TextLine 'Report' $ReportTitle) + (TextLine 'Assessment' (V $Assessment 'Name')) + (TextLine 'Target' $Target) + (TextLine 'Generated' $Generated) + (TextLine 'PSInsightHTML' $Version) + (TextLine 'Profile' (V $Assessment 'Profile')) + '</dl>')
            }
        }
        [void] $B.AppendLine('</section>')
    }
    [void] $B.AppendLine('<footer class="psi-print-end">' + (E $ReportTitle) + ' | ' + (E $Target) + ' | PSInsightHTML v' + (E $Version) + '</footer></article>')
    $B.ToString()
}
#endregion

#region Private/ConvertTo-PSIRelationshipComponentHtml.ps1
function ConvertTo-PSIRelationshipComponentHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Tree','Topology','RelationshipExplorer')][string] $Type,
          [Parameter(Mandatory)][hashtable] $Properties)

    function E($Value) { ConvertTo-PSIHtmlEncoded -Value $Value }
    function Branch($ParentId, $Level, $Children, $Counter) {
        $Output = [System.Text.StringBuilder]::new()
        if (-not $Children.ContainsKey([string] $ParentId)) { return '' }
        foreach ($Node in @($Children[$ParentId])) {
            $Counter.Value++
            $First = $Counter.Value -eq 1
            $Kids = if ($Children.ContainsKey([string] $Node.Id)) { @($Children[[string] $Node.Id]) } else { @() }
            $Expanded = if ($Kids.Count -gt 0) { ' aria-expanded="true"' } else { '' }
            $Selected = if ($First) { 'true' } else { 'false' }
            $TabIndex = if ($First) { '0' } else { '-1' }
            $Suffix = if ($Node.Status -eq 'NotChecked') { 'not-checked' } else { $Node.Status.ToLowerInvariant() }
            $External = if ($Node.External) { '<small class="psi-rel-external">External / evidence only</small>' } else { '' }
            $Icon = Get-PSIIcon -Name $Node.Icon -Size 18 -Strict
            $Label = E $Node.Name
            $NodeType = E $Node.Type
            $Id = E $Node.Id
            $Status = E $Node.Status
            $Count = if ($Kids.Count -gt 0) { '<small class="psi-rel-count">' + $Kids.Count + '</small>' } else { '' }
            [void] $Output.AppendLine("<li role=`"treeitem`" class=`"psi-rel-treeitem`" data-psi-rel-node=`"$Id`" aria-selected=`"$Selected`" aria-level=`"$Level`" tabindex=`"$TabIndex`"$Expanded><span class=`"psi-rel-tree-row`"><span class=`"psi-rel-twisty`" aria-hidden=`"true`">$([char]0x25BE)</span><span class=`"psi-rel-icon`">$Icon</span><span class=`"psi-rel-node-copy`"><strong>$Label</strong><small>$NodeType</small></span>$Count<span class=`"psi-status-badge psi-status-$Suffix`">$Status</span>$External</span>")
            if ($Kids.Count -gt 0) { [void] $Output.AppendLine('<ul role="group">' + (Branch $Node.Id ($Level+1) $Children $Counter) + '</ul>') }
            [void] $Output.AppendLine('</li>')
        }
        $Output.ToString()
    }

    $Id = [string] $Properties.Id
    $Title = E $Properties.Title
    $Presentation = $Properties.Presentation
    $Nodes = @($Presentation.Nodes)
    $Edges = @($Presentation.Edges)
    $Json = ConvertTo-Json -InputObject @{ Nodes=$Nodes; Edges=$Edges; LinkViews=$Properties.LinkViews; Diagnostics=@($Presentation.Diagnostics) } -Depth 12 -Compress
    $Json = $Json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
    $Icons = [System.Text.StringBuilder]::new()
    foreach ($IconName in @($Nodes | ForEach-Object { $_.Icon } | Sort-Object -Unique)) {
        [void] $Icons.AppendLine('<template data-psi-rel-icon="' + (E $IconName) + '">' + (Get-PSIIcon -Name $IconName -Size 20 -Strict) + '</template>')
    }
    $Types = @($Nodes | ForEach-Object { $_.Type } | Where-Object { $_ } | Sort-Object -Unique)
    $Statuses = @($Nodes | ForEach-Object { $_.Status } | Where-Object { $_ } | Sort-Object -Unique)
    $EdgeTypes = @($Edges | ForEach-Object { $_.Type } | Where-Object { $_ } | Sort-Object -Unique)
    $Categories = @($Edges | ForEach-Object { $_.Category } | Where-Object { $_ } | Sort-Object -Unique)
    $Filters = [System.Text.StringBuilder]::new()
    foreach ($Definition in @(@('type','Node type',$Types),@('status','Status',$Statuses),@('edge-type','Relationship type',$EdgeTypes),@('category','Category',$Categories))) {
        if ($Definition[2].Count -eq 0) { continue }
        $Key = $Definition[0]; $Label = $Definition[1]
        [void] $Filters.Append('<label>' + (E $Label) + '<select data-psi-rel-filter="' + $Key + '"><option value="">All</option>')
        foreach ($Value in @($Definition[2])) { $Safe = E $Value; [void] $Filters.Append('<option value="' + $Safe + '">' + $Safe + '</option>') }
        [void] $Filters.AppendLine('</select></label>')
        if ($Key -eq 'status') {
            foreach ($Property in @($Properties.FilterProperties)) {
                $DetailLabel=$Property -creplace '([a-z])([A-Z])', '$1 $2'
                $Values=@($Nodes | ForEach-Object { $_.Details } | Where-Object { $_.Label -eq $DetailLabel -and $_.Value } | ForEach-Object { $_.Value } | Sort-Object -Unique)
                if (-not $Values.Count) { continue }
                [void] $Filters.Append('<label>' + (E $DetailLabel) + '<select data-psi-rel-filter-detail="' + (E $DetailLabel) + '"><option value="">All</option>')
                foreach ($Value in $Values) { $Safe=E $Value; [void] $Filters.Append('<option value="' + $Safe + '">' + $Safe + '</option>') }
                [void] $Filters.AppendLine('</select></label>')
            }
        }
    }
    $Main = ''
    if ($Type -eq 'Tree') {
        $Children = @{}
        foreach ($Node in $Nodes) {
            $Parent = [string] $Node.ParentId
            if (-not $Children.ContainsKey($Parent)) { $Children[$Parent] = [System.Collections.Generic.List[object]]::new() }
            $Children[$Parent].Add($Node)
        }
        $Counter = [ref] 0
        $Tree = Branch '' 1 $Children $Counter
        $Main = '<div class="psi-rel-tree-scroll"><ul class="psi-rel-tree" role="tree" aria-label="' + $Title + '">' + $Tree + '</ul></div>'
    }
    elseif ($Type -eq 'Topology') {
        $Main = '<div class="psi-rel-graph-actions"><button type="button" data-psi-rel-zoom="in" aria-label="Zoom in">+</button><button type="button" data-psi-rel-zoom="out" aria-label="Zoom out">-</button><button type="button" data-psi-rel-zoom="fit">Fit</button><button type="button" data-psi-rel-zoom="reset">Reset</button></div><div class="psi-rel-viewport" tabindex="0" role="region" aria-label="Scrollable topology graph"><svg class="psi-rel-graph" data-psi-rel-svg role="group" aria-label="' + $Title + ' graph"></svg></div>'
    }
    $Links = [System.Text.StringBuilder]::new()
    foreach ($Edge in $Edges) {
        $Source = @($Nodes | Where-Object { $_.Id -eq $Edge.SourceId })[0]
        $Target = @($Nodes | Where-Object { $_.Id -eq $Edge.TargetId })[0]
        $Arrow = if ($Edge.Direction -eq 'Bidirectional') { ' &harr; ' } else { ' &rarr; ' }
        [void] $Links.AppendLine('<button type="button" class="psi-rel-edge-item" data-psi-rel-edge="' + (E $Edge.Id) + '"><strong>' + (E $Source.Name) + $Arrow + (E $Target.Name) + '</strong><span>' + (E $Edge.Label) + ' | ' + (E $Edge.Status) + '</span></button>')
    }
    $Empty = if ($Edges.Count -eq 0) { '<p class="psi-rel-empty">No relationships are available in this scope.</p>' } else { '' }
    $List = '<div class="psi-rel-relationship-list" aria-label="Relationship list"><h4>Relationships</h4><div data-psi-rel-edge-list>' + $Links.ToString() + '</div>' + $Empty + '</div>'
    $Diagnostics = if (@($Presentation.Diagnostics).Count) { '<p class="psi-rel-diagnostic" role="status">' + (E (@($Presentation.Diagnostics) -join ' ')) + '</p>' } else { '' }
    $InitialEmpty = if ($Nodes.Count -eq 0) { '<p class="psi-rel-empty">No nodes are available in this scope.</p>' } else { '' }
    $Mode = if ($Type -eq 'RelationshipExplorer') { 'Explorer' } else { $Type }
    $Max = [int] $Properties.MaxNodes
    @"
<section class="psi-rel-component psi-rel-$($Mode.ToLowerInvariant())" id="$Id" data-psi-rel-component data-psi-rel-mode="$Mode" data-psi-rel-max="$Max" aria-label="$Title">
  <header class="psi-rel-header"><div><p class="psi-app-explorer-eyebrow">Relationship workspace</p><h3>$Title</h3></div><span data-psi-rel-count>$($Nodes.Count) nodes / $($Edges.Count) relationships</span></header>
  $Diagnostics
  <div class="psi-rel-toolbar"><label>Search nodes<input type="search" data-psi-rel-search autocomplete="off" placeholder="Find a name"></label>$($Filters.ToString())</div>
  <div class="psi-rel-layout"><div class="psi-rel-main">$InitialEmpty$Main$List<p class="psi-rel-empty" data-psi-rel-filter-empty hidden>No nodes or relationships match these filters.</p></div><aside class="psi-rel-detail" data-psi-rel-detail aria-label="Selected relationship detail" aria-live="polite"><p>Select a node or relationship to inspect details.</p></aside></div>
  $($Icons.ToString())<script type="application/json" data-psi-rel-data>$Json</script>
</section>
"@
}
#endregion

#region Private/ConvertTo-PSIResourceWorkspace.ps1
function ConvertTo-PSIResourceWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Report)

    $Explorer = Get-PSIProperty $Report 'ResourceExplorer'
    $Inspector = Get-PSIProperty $Report 'Inspector'
    if ($null -eq $Explorer) { return [pscustomobject]@{ Explorer=''; Header=''; Inspector=''; Controls=''; Data=''; Script='' } }
    if ((Get-PSIProperty $Report 'Navigation') -ne 'FluentExplorer') { throw 'Shell Resource Explorer requires FluentExplorer navigation.' }

    $Nodes = @($Explorer.Nodes)
    $ById = @{}
    $Children = @{}
    foreach ($Node in $Nodes) {
        $ById[$Node.Id] = $Node
        $Parent = [string]$Node.ParentId
        if (-not $Children.ContainsKey($Parent)) { $Children[$Parent] = [System.Collections.Generic.List[object]]::new() }
        $Children[$Parent].Add($Node)
        if ($Node.Target -and @($Report.Views | Where-Object { $_.Id -eq $Node.Target }).Count -eq 0) {
            throw "Resource node '$($Node.Id)' targets missing view '$($Node.Target)'."
        }
    }
    $Tree = [System.Text.StringBuilder]::new()
    $Stack = [System.Collections.Generic.Stack[object]]::new()
    if ($Children.ContainsKey('')) {
        $Roots = @($Children[''])
        for ($Index=$Roots.Count-1; $Index -ge 0; $Index--) { $Stack.Push($Roots[$Index]) }
    }
    while ($Stack.Count -gt 0) {
        $Node = $Stack.Pop()
        $NodeId = [string]$Node.Id
        $Label = ConvertTo-PSIHtmlEncoded -Value $Node.Label
        $Type = ConvertTo-PSIHtmlEncoded -Value $Node.Type
        $Status = ConvertTo-PSIHtmlEncoded -Value $Node.Status
        $ParentId = [string]$Node.ParentId
        $Target = [string]$Node.Target
        $Selected = if ($NodeId -eq $Explorer.SelectedId) { 'true' } else { 'false' }
        $HasChildren = $Children.ContainsKey($NodeId) -and $Children[$NodeId].Count -gt 0
        $Expanded = if ($HasChildren) { ' aria-expanded="true"' } else { '' }
        $Disabled = if ($Node.Selectable) { '' } else { ' aria-disabled="true"' }
        $Regular = (Get-PSIIcon -Name $Node.Icon -Variant Regular -Size 18 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-regular"')
        $Filled = (Get-PSIIcon -Name $Node.Icon -Variant Filled -Size 18 -Strict).Replace('class="psi-icon psi-icon-fluent"', 'class="psi-icon psi-icon-fluent psi-icon-filled"')
        $Chevron = if ($HasChildren) { '<span class="psi-resource-chevron" aria-hidden="true">' + (Get-PSIIcon -Name AppChevron -Size 14 -Strict) + '</span>' } else { '<span class="psi-resource-chevron" aria-hidden="true"></span>' }
        $Count = if ($null -ne $Node.Count) { '<span class="psi-resource-count">' + [int]$Node.Count + '</span>' } else { '' }
        $StatusPresentation = Get-PSIStatusPresentation -Status $Node.Status
        $StatusIconName = if ($null -ne $StatusPresentation) { $StatusPresentation.Icon } else { 'SeverityInfo' }
        $StatusIcon = Get-PSIIcon -Name $StatusIconName -Size 13 -Strict
        [void]$Tree.AppendLine("<button type=`"button`" class=`"psi-resource-node`" role=`"treeitem`" data-psi-resource-node=`"$NodeId`" data-psi-resource-parent=`"$ParentId`" data-psi-resource-target=`"$Target`" data-psi-resource-type=`"$Type`" data-psi-resource-status=`"$Status`" style=`"--psi-resource-depth:$($Node.Depth)`" aria-level=`"$($Node.Depth+1)`" aria-selected=`"$Selected`"$Expanded$Disabled tabindex=`"-1`">$Chevron<span class=`"psi-resource-icon`">$Regular$Filled</span><span class=`"psi-resource-label`">$Label</span>$Count<span class=`"psi-resource-status psi-status-$($Node.Status.ToLowerInvariant())`" title=`"Status: $Status`" aria-label=`"Status: $Status`">$StatusIcon</span></button>")
        if ($HasChildren) {
            $ChildNodes = @($Children[$NodeId])
            for ($Index=$ChildNodes.Count-1; $Index -ge 0; $Index--) { $Stack.Push($ChildNodes[$Index]) }
        }
    }
    $ExplorerTitle = ConvertTo-PSIHtmlEncoded -Value $Explorer.Title
    $SearchIcon = Get-PSIIcon -Name NavigationSearch -Size 17 -Strict
    $CloseIcon = Get-PSIIcon -Name AppClose -Size 17 -Strict
    $ExplorerMarkup = @"
    <aside class="psi-resource-explorer" id="psi-resource-explorer" data-psi-resource-explorer data-psi-explorer-id="$($Explorer.Id)" aria-label="$ExplorerTitle">
      <div class="psi-resource-explorer-head"><h2>$ExplorerTitle</h2><button type="button" data-psi-resource-collapse aria-label="Hide Resource Explorer" aria-controls="psi-resource-explorer" aria-expanded="true">$CloseIcon</button></div>
      <label class="psi-resource-search" for="psi-resource-search-input">$SearchIcon<span class="psi-sr-only">Search resources</span><input id="psi-resource-search-input" type="search" data-psi-resource-search placeholder="Find a resource" autocomplete="off"></label>
      <div class="psi-resource-tree" role="tree" aria-label="$ExplorerTitle" data-psi-resource-tree>
$($Tree.ToString())      </div>
      <p class="psi-resource-empty" data-psi-resource-empty hidden>No matching resources.</p>
    </aside>
"@
    $HeaderIcons = '<template data-psi-resource-status-icon="healthy">' + (Get-PSIIcon -Name SeveritySuccess -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="warning">' + (Get-PSIIcon -Name SeverityWarning -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="critical">' + (Get-PSIIcon -Name SeverityError -Size 13 -Strict) + '</template>' +
        '<template data-psi-resource-status-icon="info">' + (Get-PSIIcon -Name SeverityInfo -Size 13 -Strict) + '</template>'
    $Header = $HeaderIcons + '<div class="psi-resource-header" id="psi-resource-header" data-psi-resource-header aria-live="polite"><span class="psi-resource-header-icon" data-psi-resource-header-icon></span><div class="psi-resource-header-copy"><p data-psi-resource-header-breadcrumb></p><h2 data-psi-resource-header-title></h2><span data-psi-resource-header-subtitle></span><div class="psi-resource-header-tags" data-psi-resource-header-tags></div></div><div class="psi-resource-header-side"><span class="psi-resource-header-status" data-psi-resource-header-status></span><div class="psi-resource-header-actions" data-psi-resource-header-actions></div></div></div>'
    $InspectorMarkup = ''
    $Data = ''
    if ($null -ne $Inspector) {
        $InspectorTitle = ConvertTo-PSIHtmlEncoded -Value $Inspector.Title
        $InspectorMarkup = @"
        <aside class="psi-context-inspector" id="psi-context-inspector" data-psi-context-inspector data-psi-inspector-id="$($Inspector.Id)" aria-label="$InspectorTitle">
          <div class="psi-context-inspector-head"><div><p>RESOURCE CONTEXT</p><h2>$InspectorTitle</h2></div><button type="button" data-psi-inspector-collapse aria-label="Hide Context Inspector" aria-controls="psi-context-inspector" aria-expanded="true">$CloseIcon</button></div>
          <div class="psi-context-inspector-identity"><strong data-psi-inspector-title></strong><span data-psi-inspector-subtitle></span><span data-psi-inspector-status></span></div>
          <div class="psi-context-inspector-tabs" role="tablist" aria-label="Resource details" data-psi-inspector-tabs></div>
          <div class="psi-context-inspector-body" data-psi-inspector-body></div>
        </aside>
"@
        $Lookup = @{}
        foreach ($Item in $Inspector.Items) { $Lookup[$Item.ResourceId] = $Item }
        $Json = (ConvertTo-Json -InputObject $Lookup -Depth 8 -Compress).Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
        $Data = '<script type="application/json" id="psi-resource-data">' + $Json + '</script>'
    }
    $Controls = '<button type="button" class="psi-resource-restore" data-psi-resource-restore aria-label="Show Resource Explorer" aria-controls="psi-resource-explorer" aria-expanded="true">Resources</button>'
    if ($null -ne $Inspector) { $Controls += '<button type="button" class="psi-inspector-restore" data-psi-inspector-restore aria-label="Show Context Inspector" aria-controls="psi-context-inspector" aria-expanded="true">Inspector</button>' }
    $Script = Get-Content -LiteralPath (Join-Path $script:ModuleRoot 'Assets/JavaScript/psi-resource-workspace.js') -Raw -ErrorAction Stop
    [pscustomobject]@{ Explorer=$ExplorerMarkup; Header=$Header; Inspector=$InspectorMarkup; Controls=$Controls; Data=$Data; Script=$Script }
}
#endregion

#region Private/Get-PSIApplicationSearchIndex.ps1
function Get-PSIApplicationSearchIndex {
    <# .SYNOPSIS Build a small, allowlisted discovery index for application views. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    $Items = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Types = @('Check','Finding','Resource','Evidence','Exception')
    $Icons = @{ Check='Rules'; Finding='SeverityWarning'; Resource='ResourceServer'; Evidence='Document'; Exception='SeverityInfo' }
    $CategoryNames = @{}
    $Assessment = Get-PSIProperty -InputObject $Report -Name 'ApplicationAssessment'
    if ($Assessment) {
        foreach ($Category in @($Assessment.Categories)) { $CategoryNames[[string] $Category.Id] = [string] $Category.Name }
    }
    foreach ($View in @($Report.Views)) {
        $ViewId = [string] $View.Id
        $Items.Add([pscustomobject]@{
            Id=$ViewId; EntityType='View'; Title=[string] $View.Title; Subtitle=[string] $View.Subtitle
            Keywords=''; Status=''; Severity=''; ViewId=$ViewId; TargetId=''; Category=[string] $View.Group
            Icon=[string] $View.Icon
        })
        foreach ($Section in @($View.Sections)) {
            foreach ($Row in @($Section.Rows)) {
                foreach ($Component in @($Row.Components)) {
                    if ($Component.Type -ne 'Explorer') { continue }
                    $Properties = $Component.Properties
                    $Type = [string] $Properties.EntityType
                    if ($Type -notin $Types) { continue }
                    foreach ($Record in @($Properties.Data)) {
                        $Id = [string] (Get-PSIProperty -InputObject $Record -Name 'Id')
                        if ([string]::IsNullOrWhiteSpace($Id) -or -not $Seen.Add("$Type`:$Id")) { continue }
                        $Title = [string] (Get-PSIProperty -InputObject $Record -Name ([string] $Properties.TitleProperty))
                        if ([string]::IsNullOrWhiteSpace($Title)) { $Title = '(unnamed)' }
                        $Subtitle = if ($Properties.SubtitleProperty) { [string] (Get-PSIProperty -InputObject $Record -Name ([string] $Properties.SubtitleProperty)) } else { '' }
                        $Category = [string] (Get-PSIProperty -InputObject $Record -Name 'Category')
                        if ($Type -eq 'Check') {
                            $CategoryId = [string] (Get-PSIProperty -InputObject $Record -Name 'CategoryId')
                            $Category = if ($CategoryNames.ContainsKey($CategoryId)) { $CategoryNames[$CategoryId] } else { $CategoryId }
                        }
                        if (-not $Category -and $Type -eq 'Resource') { $Category = [string] (Get-PSIProperty -InputObject $Record -Name 'Type') }
                        if (-not $Category -and $Type -eq 'Evidence') { $Category = [string] (Get-PSIProperty -InputObject $Record -Name 'Type') }
                        $Description = if ($Type -in @('Check','Resource','Exception')) { [string] (Get-PSIProperty -InputObject $Record -Name 'Description') }
                            else { [string] (Get-PSIProperty -InputObject $Record -Name 'Summary') }
                        if ($Description.Length -gt 180) { $Description = $Description.Substring(0,180) }
                        $Tags = @((Get-PSIProperty -InputObject $Record -Name 'Tags' -DefaultValue @()) | Select-Object -First 8)
                        $Keywords = (@($Tags | ForEach-Object { [string] $_ }) + @($Description)) -join ' '
                        $Items.Add([pscustomobject]@{
                            Id=$Id; EntityType=$Type; Title=$Title; Subtitle=$Subtitle; Keywords=$Keywords
                            Status=[string] (Get-PSIProperty -InputObject $Record -Name 'Status')
                            Severity=[string] (Get-PSIProperty -InputObject $Record -Name 'Severity')
                            ViewId=$ViewId; TargetId=$Id; Category=$Category; Icon=$Icons[$Type]
                        })
                    }
                }
            }
        }
    }
    $Items.ToArray()
}
#endregion

#region Private/Get-PSIExportToolbar.ps1
function Get-PSIExportToolbar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Table', 'Evidence', 'Report')]
        [string] $Scope,

        [Parameter()]
        [string[]] $Formats = @('Csv', 'Xlsx', 'Print'),

        [Parameter()]
        [switch] $UseFluentIcons
    )

    $Label = if ($Scope -eq 'Report') { 'Export report' } else { 'Export' }
    $Items = [System.Text.StringBuilder]::new()
    foreach ($Format in @('Csv', 'Xlsx', 'Print')) {
        if ($Format -notin $Formats) { continue }
        $Name = switch ($Format) { 'Csv' { 'CSV' } 'Xlsx' { 'Excel (.xlsx)' } 'Print' { 'Print / PDF' } }
        $Icon = if ($UseFluentIcons) { 'Document' } else { switch ($Format) { 'Csv' { 'file' } 'Xlsx' { 'database' } 'Print' { 'print' } } }
        $IconSize = if ($UseFluentIcons) { 18 } else { 16 }
        [void] $Items.AppendLine("<button type=`"button`" role=`"menuitem`" tabindex=`"-1`" data-psi-export-format=`"$($Format.ToLowerInvariant())`">$(Get-PSIIcon -Name $Icon -Size $IconSize)<span>$Name</span></button>")
    }
    if ($Items.Length -eq 0) { return '' }
    $TriggerIcon = if ($UseFluentIcons) { 'Export' } else { 'file' }
    $ChevronIcon = if ($UseFluentIcons) { 'AppChevron' } else { 'chevron' }
    $TriggerSize = if ($UseFluentIcons) { 19 } else { 16 }
    @"
<div class="psi-export-toolbar" data-psi-export-toolbar data-psi-export-scope="$($Scope.ToLowerInvariant())">
  <button type="button" class="psi-export-trigger" data-psi-export-trigger aria-haspopup="menu" aria-expanded="false" aria-label="$Label options">$(Get-PSIIcon -Name $TriggerIcon -Size $TriggerSize)<span>$Label</span>$(Get-PSIIcon -Name $ChevronIcon -Size 14)</button>
  <div class="psi-export-menu" role="menu" aria-label="$Label formats" data-psi-export-menu hidden>
    $($Items.ToString().TrimEnd())
  </div>
  <span class="psi-export-feedback" data-psi-export-feedback role="status" aria-live="polite"></span>
</div>
"@
}
#endregion

#region Private/Get-PSIFindingAnchors.ps1
function Get-PSIFindingAnchors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable] $Sections
    )

    $SectionList = @($Sections)
    $UsedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($FixedId in @('psi-dialog-title', 'psi-dialog-description', 'psi-dialog-summary')) { [void] $UsedIds.Add($FixedId) }
    for ($SectionIndex = 0; $SectionIndex -lt $SectionList.Count; $SectionIndex++) {
        [void] $UsedIds.Add("psi-section-$SectionIndex")
        foreach ($Row in $SectionList[$SectionIndex].Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -ne 'Table') { continue }
                $TableId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ([string]::IsNullOrWhiteSpace($TableId)) { continue }
                [void] $UsedIds.Add($TableId)
                [void] $UsedIds.Add("$TableId-data")
                $Filters = @((Get-PSIProperty -InputObject $Component.Properties -Name 'Filters'))
                for ($FilterIndex = 0; $FilterIndex -lt $Filters.Count; $FilterIndex++) {
                    [void] $UsedIds.Add("$TableId-filter-$FilterIndex")
                    [void] $UsedIds.Add("psi-filter-help-$TableId-filter-$FilterIndex")
                }
            }
        }
    }

    $Anchors = [System.Collections.Generic.List[object]]::new()
    foreach ($Section in $SectionList) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -ne 'Finding') { continue }
                $BaseId = ConvertTo-PSIFindingId -Id ([string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id'))
                $DomId = $BaseId
                $Suffix = 2
                while (-not $UsedIds.Add($DomId)) {
                    $DomId = '{0}-{1}' -f $BaseId, $Suffix
                    $Suffix++
                }
                $Anchors.Add([pscustomobject]@{
                    Id = $DomId
                    FindingReference = Get-PSIProperty -InputObject $Component.Properties -Name 'FindingReference'
                })
            }
        }
    }
    ,$Anchors
}
#endregion

#region Private/Get-PSIFluentIconSet.ps1
function Get-PSIFluentIconSet {
    <#
    .SYNOPSIS
    Resolve the icon roles used by the Fluent renderer to inline SVG markup.

    .DESCRIPTION
    Resolution order per role:
      1. Curated Fluent System Icons SVG in Assets/Icons/Fluent (MIT, see NOTICE).
      2. The same Fluent glyph extracted from the Windows "Segoe Fluent Icons" font
         (Windows 11) or "Segoe MDL2 Assets" (Windows 10) at export time.
      3. The legacy PSInsightHTML stroke icon of the closest meaning.
    Every report embeds the resolved SVG, so it renders identically offline.
    #>
    [CmdletBinding()]
    param()

    if ($script:PSIFluentIconCache) { return $script:PSIFluentIconCache }

    # role = curated file stem | Segoe code point | legacy fallback
    $Roles = [ordered]@{
        home         = @('home', 0xE80F, 'dashboard');           search      = @('search', 0xE721, 'search')
        menu         = @('navigation', 0xE700, 'dashboard');     settings    = @('settings', 0xE713, 'settings')
        sun          = @('weather_sunny', 0xE706, 'theme/light'); moon       = @('weather_moon', 0xE708, 'theme/dark')
        document     = @('document', 0xE8A5, 'file');            rules       = @('document_bullet_list', 0xE9D5, 'file')
        chevronD     = @('chevron_down', 0xE70D, 'chevron');     close       = @('dismiss', 0xE711, 'close')
        warning      = @('warning', 0xE7BA, 'warning');          critical    = @('error_circle', 0xEB90, 'critical')
        healthy      = @('checkmark_circle', 0xE930, 'healthy'); info        = @('info', 0xE946, 'info')
        server       = @('server', 0xE968, 'server');            shield      = @('shield', 0xEA18, 'security')
        relationship = @('branch_fork', 0xF168, 'network');      download    = @('arrow_download', 0xE896, 'arrow')
        chevronR     = @('chevron_right', 0xE76C, 'arrow');      chevronU    = @('chevron_up', 0xE70E, 'chevron')
        copy         = @('copy', 0xE8C8, 'file');                filter      = @('filter', 0xE71C, 'search')
        print        = @('print', 0xE749, 'print');              link        = @('link', 0xE71B, 'arrow')
        unknown      = @('question_circle', 0xE9CE, 'info');     blocked     = @('prohibited', 0xE733, 'critical')
        clock        = @('clock', 0xE823, 'info');               calendar    = @('calendar', 0xE787, 'info')
        list         = @('text_bullet_list', 0xE8FD, 'file');    grid        = @('grid', 0xE8A9, 'dashboard')
        chart        = @('data_bar_vertical', 0xE9D2, 'dashboard'); pie      = @('data_pie', 0xEB05, 'dashboard')
        people       = @('people', 0xE716, 'users');             person      = @('person', 0xE77B, 'users')
        group        = @('people_team', 0xE902, 'users');        computer    = @('desktop', 0xE7F8, 'server')
        globe        = @('globe', 0xE774, 'network');            key         = @('key', 0xE192, 'security')
        lock         = @('lock_closed', 0xE72E, 'security');     sync        = @('arrow_sync', 0xE895, 'replication')
        flag         = @('flag', 0xE7C1, 'warning');             tag         = @('tag', 0xE8EC, 'file')
        mail         = @('mail', 0xE715, 'file');                folder      = @('folder', 0xE8B7, 'file')
        layers       = @('layer', 0xE81E, 'dashboard');          tree        = @('tree', 0xF168, 'network')
        arrowRight   = @('arrow_right', 0xF0AF, 'arrow');        openNew     = @('open', 0xE8A7, 'arrow')
        view         = @('eye', 0xE890, 'search');               more        = @('more_horizontal', 0xE712, 'dashboard')
        important    = @('important', 0xE8C9, 'warning');        shieldAlert = @('shield_error', 0xE730, 'security')
        checklist    = @('task_list_ltr', 0xE9D5, 'file');       sliders     = @('options', 0xE9E9, 'settings')
        admin        = @('person_key', 0xE7EF, 'security');      history     = @('history', 0xE81C, 'info')
        check        = @('checkmark', 0xE73E, 'healthy');        domain      = @('building', 0xE80F, 'domain')
        database     = @('database', 0xEE94, 'database');        network     = @('network', 0xE968, 'network')
        cloud        = @('cloud', 0xE753, 'cloud');              certificate = @('certificate', 0xEB95, 'certificate')
        diagnostic   = @('pulse', 0xE9D9, 'dashboard');          report      = @('document_data', 0xE9F9, 'file')
        lightbulb    = @('lightbulb', 0xEA80, 'info');           wrench      = @('wrench', 0xE90F, 'settings')
    }

    $IconDirectory = Join-Path -Path $MyInvocation.MyCommand.Module.ModuleBase -ChildPath 'Assets/Icons/Fluent'
    $Typeface = $null
    $FontPath = @("$env:WINDIR\Fonts\SegoeIcons.ttf", "$env:WINDIR\Fonts\segmdl2.ttf") |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if ($FontPath) {
        try {
            Add-Type -AssemblyName PresentationCore -ErrorAction Stop
            $Typeface = [System.Windows.Media.GlyphTypeface]::new([Uri]('file:///' + ($FontPath -replace '\\', '/')))
        }
        catch { $Typeface = $null }
    }
    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture

    $Set = [ordered]@{}
    $Sources = @{ Curated = 0; Font = 0; Legacy = 0 }
    foreach ($Role in $Roles.Keys) {
        $Stem, $CodePoint, $Legacy = $Roles[$Role]
        $Svg = $null
        $Curated = Join-Path -Path $IconDirectory -ChildPath ($Stem + '_24_regular.svg')
        if (Test-Path -LiteralPath $Curated -PathType Leaf) {
            $Paths = [regex]::Matches([System.IO.File]::ReadAllText($Curated), '<path[^>]*\sd="([^"]+)"') | ForEach-Object { '<path d="' + $_.Groups[1].Value + '"/>' }
            if ($Paths) { $Svg = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">' + ($Paths -join '') + '</svg>'; $Sources.Curated++ }
        }
        if (-not $Svg -and $Typeface) {
            $Glyph = 0
            if ($Typeface.CharacterToGlyphMap.TryGetValue([int] $CodePoint, [ref] $Glyph)) {
                $Geometry = [System.Windows.Media.PathGeometry]::CreateFromGeometry($Typeface.GetGlyphOutline($Glyph, 24, 24))
                $Data = $Geometry.ToString($Invariant) -replace '^F[01]', ''
                $Data = [regex]::Replace($Data, '-?\d+\.\d+', { param($M) [math]::Round([double]::Parse($M.Value, $Invariant), 2).ToString($Invariant) })
                if ($Data) {
                    $Rule = if ($Geometry.FillRule -eq 'EvenOdd') { 'evenodd' } else { 'nonzero' }
                    $Svg = '<svg viewBox="0 -24 24 24" fill="currentColor" fill-rule="' + $Rule + '" aria-hidden="true" focusable="false"><path d="' + $Data + '"/></svg>'
                    $Sources.Font++
                }
            }
        }
        if (-not $Svg) {
            $Svg = (Get-PSIIcon -Name $Legacy -Size 24) -replace ' width="24" height="24"', ''
            $Sources.Legacy++
        }
        $Set[$Role] = $Svg
    }
    Write-Verbose ("Fluent icon set: {0} curated SVG, {1} font glyph, {2} legacy" -f $Sources.Curated, $Sources.Font, $Sources.Legacy)
    $script:PSIFluentIconCache = $Set
    $Set
}
#endregion

#region Private/Get-PSIIcon.ps1
function Get-PSIIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [ValidateRange(12, 96)]
        [int] $Size = 20,

        [Parameter()]
        [ValidateSet('Regular', 'Filled')]
        [string] $Variant = 'Regular',

        [Parameter()]
        [switch] $Strict
    )

    # Curated Fluent SVGs are local and restricted to this fixed role allowlist.
    # Legacy names below keep their established output.
    $FluentNames = @{
        NavigationHome = 'home'
        NavigationSearch = 'search'
        Menu = 'navigation'
        AppSettings = 'settings'
        ThemeLight = 'weather_sunny'
        ThemeDark = 'weather_moon'
        Document = 'document'
        AppChevron = 'chevron_down'
        AppClose = 'dismiss'
        SeverityWarning = 'warning'
        SeverityError = 'error_circle'
        SeveritySuccess = 'checkmark_circle'
        SeverityInfo = 'info'
        ResourceServer = 'server'
        SecurityShield = 'shield'
        Relationship = 'branch_fork'
        Rules = 'document_bullet_list'
        Export = 'arrow_download'
    }
    if ($FluentNames.ContainsKey($Name)) {
        $FileName = '{0}_24_{1}.svg' -f $FluentNames[$Name], $Variant.ToLowerInvariant()
        $IconPath = Join-Path -Path $script:ModuleRoot -ChildPath ('Assets/Icons/Fluent/' + $FileName)
        if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
            if ($Variant -eq 'Filled') {
                $IconPath = Join-Path -Path $script:ModuleRoot -ChildPath ('Assets/Icons/Fluent/' + $FluentNames[$Name] + '_24_regular.svg')
            }
            if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) { throw "Curated icon '$Name' is missing." }
        }
        $Document = [System.Xml.XmlDocument]::new()
        $Document.XmlResolver = $null
        try { $Document.LoadXml((Get-Content -LiteralPath $IconPath -Raw -ErrorAction Stop)) }
        catch { throw "Curated icon '$Name' is not valid SVG XML: $($_.Exception.Message)" }
        if ($null -ne $Document.DocumentType -or $null -eq $Document.DocumentElement -or
            $Document.DocumentElement.LocalName -ne 'svg' -or
            $Document.DocumentElement.GetAttribute('viewBox') -ne '0 0 24 24') {
            throw "Curated icon '$Name' contains unsupported SVG markup."
        }
        $Paths = [System.Text.StringBuilder]::new()
        foreach ($Child in $Document.DocumentElement.ChildNodes) {
            if ($Child.NodeType -eq [System.Xml.XmlNodeType]::Whitespace) { continue }
            if ($Child.LocalName -ne 'path' -or $Child.NamespaceURI -ne $Document.DocumentElement.NamespaceURI) {
                throw "Curated icon '$Name' contains unsupported SVG markup."
            }
            foreach ($Attribute in $Child.Attributes) {
                if ($Attribute.LocalName -notin @('d', 'fill')) {
                    throw "Curated icon '$Name' contains unsupported SVG attributes."
                }
            }
            $PathData = $Child.GetAttribute('d')
            if ([string]::IsNullOrWhiteSpace($PathData)) { throw "Curated icon '$Name' has an empty path." }
            [void] $Paths.Append('<path d="' + (ConvertTo-PSIHtmlEncoded -Value $PathData) + '" fill="currentColor"/>')
        }
        if ($Paths.Length -eq 0) { throw "Curated icon '$Name' has no paths." }
        return '<svg class="psi-icon psi-icon-fluent" width="{0}" height="{0}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">{1}</svg>' -f $Size, $Paths.ToString()
    }

    $IconPaths = @{
        'dashboard' = '<rect x="3" y="3" width="8" height="8" rx="1"/><rect x="13" y="3" width="8" height="5" rx="1"/><rect x="13" y="10" width="8" height="11" rx="1"/><rect x="3" y="13" width="8" height="8" rx="1"/>'
        'server' = '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01M11 7.5h6M11 16.5h6"/>'
        'domain' = '<path d="M3 21h18M5 21V7l7-4 7 4v14M9 21v-5h6v5M8 9h.01M12 9h.01M16 9h.01M8 12h.01M12 12h.01M16 12h.01"/>'
        'replication' = '<path d="M20 7h-6V3M4 17h6v4"/><path d="M5.6 9a7 7 0 0 1 11.5-2L20 9M4 15l2.9 2a7 7 0 0 0 11.5-2"/>'
        'security' = '<path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z"/><path d="m9 12 2 2 4-4"/>'
        'certificate' = '<path d="M12 15a6 6 0 1 0 0-12 6 6 0 0 0 0 12Z"/><path d="m8 14-1 8 5-3 5 3-1-8"/>'
        'users' = '<path d="M16 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM20 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>'
        'cloud' = '<path d="M20 16.2A4.5 4.5 0 0 0 18 7.5h-1.3A6 6 0 0 0 5 9a4 4 0 0 0 0 8h14"/>'
        'database' = '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>'
        'network' = '<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="2" y="16" width="6" height="5" rx="1"/><rect x="16" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M5 16v-4h14v4"/>'
        'warning' = '<path d="m10.3 3.9-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3.1l-8-14a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>'
        'critical' = '<circle cx="12" cy="12" r="9"/><path d="m15 9-6 6M9 9l6 6"/>'
        'info' = '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>'
        'healthy' = '<circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/>'
        'settings' = '<circle cx="12" cy="12" r="3"/><path d="m19.4 15 .1.1 1.4 1.1-1.4 2.4-1.7-.7a8 8 0 0 1-1.7 1l-.3 1.8h-2.8l-.3-1.8a8 8 0 0 1-1.7-1l-1.7.7-1.4-2.4L7.3 15a8 8 0 0 1 0-2l-1.4-1.1 1.4-2.4 1.7.7a8 8 0 0 1 1.7-1l.3-1.8h2.8l.3 1.8a8 8 0 0 1 1.7 1l1.7-.7 1.4 2.4-1.4 1.1a8 8 0 0 1-.1 2Z" transform="translate(-1 -1)"/>'
        'search' = '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>'
        'arrow' = '<path d="M5 12h14M13 6l6 6-6 6"/>'
        'close' = '<path d="m18 6-12 12M6 6l12 12"/>'
        'theme/light' = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'
        'theme/dark' = '<path d="M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z"/>'
        'file' = '<path d="M6 2h8l5 5v15H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Z"/><path d="M14 2v6h5M8 13h8M8 17h8"/>'
        'print' = '<path d="M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 15h12v7H6zM18 12h.01"/>'
        'chevron' = '<path d="m6 9 6 6 6-6"/>'
    }

    if (-not $IconPaths.ContainsKey($Name)) {
        if ($Strict) { throw "Unknown PSInsightHTML icon '$Name'." }
        $Name = 'dashboard'
    }

    '<svg class="psi-icon" width="{0}" height="{0}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">{1}</svg>' -f $Size, $IconPaths[$Name]
}
#endregion

#region Private/Get-PSILastRow.ps1
function Get-PSILastRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject] $Report
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty) {
        throw 'The report does not contain a Sections collection.'
    }

    $Sections = @($SectionsProperty.Value)
    if ($Sections.Count -eq 0) {
        throw 'A section must be created before adding a row.'
    }

    $LastSection = $Sections[-1]
    if ($null -eq $LastSection) {
        throw 'The last report section is null and does not contain a Rows collection.'
    }

    $RowsProperty = $LastSection.PSObject.Properties['Rows']
    if ($null -eq $RowsProperty) {
        throw 'The last report section does not contain a Rows collection.'
    }

    if ($RowsProperty.Value -isnot [System.Collections.IList]) {
        throw 'The last report section Rows property is not a collection.'
    }

    $Rows = @($RowsProperty.Value)
    if ($Rows.Count -eq 0) {
        throw 'A row must be created before adding a component.'
    }

    $Rows[-1]
}
#endregion

#region Private/Get-PSIProperty.ps1
function Get-PSIProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $DefaultValue = $null
    )

    if ($null -eq $InputObject) { return ,$DefaultValue }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $InputObject.Keys) {
            if ([string]::Equals([string] $Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ,$InputObject[$Key]
            }
        }
        return ,$DefaultValue
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) { return ,$DefaultValue }
    return ,$Property.Value
}
#endregion

#region Private/Get-PSIReportMetadata.ps1
function Get-PSIReportMetadata {
    [CmdletBinding()]
    param()

    $ProvidersRoot = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers'
    if (-not (Test-Path -LiteralPath $ProvidersRoot -PathType Container)) { return }

    $RequiredKeys = @(
        'Id', 'Provider', 'Name', 'Description', 'Category', 'Command', 'Status',
        'SupportsSampleData', 'SupportsProvidedData', 'SupportsLiveCollection',
        'MinimumPowerShellVersion'
    )
    $SeenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ProviderDirectory in @(Get-ChildItem -LiteralPath $ProvidersRoot -Directory -ErrorAction Stop | Sort-Object Name)) {
        foreach ($ReportDirectory in @(Get-ChildItem -LiteralPath $ProviderDirectory.FullName -Directory -ErrorAction Stop | Sort-Object Name)) {
            $MetadataPath = Join-Path -Path $ReportDirectory.FullName -ChildPath 'Report.psd1'
            if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { continue }
            try { $Metadata = Import-PowerShellDataFile -LiteralPath $MetadataPath -ErrorAction Stop }
            catch { throw "Cannot read report metadata '$MetadataPath': $($_.Exception.Message)" }
            foreach ($Key in $RequiredKeys) {
                if (-not $Metadata.ContainsKey($Key) -or $null -eq $Metadata[$Key]) {
                    throw "Report metadata '$MetadataPath' is missing '$Key'."
                }
            }
            foreach ($Key in @('Id','Provider','Name','Description','Category','Command','Status','MinimumPowerShellVersion')) {
                if ([string]::IsNullOrWhiteSpace([string] $Metadata[$Key])) {
                    throw "Report metadata '$MetadataPath' has an empty '$Key'."
                }
            }
            if ([string] $Metadata.Provider -ne $ProviderDirectory.Name) {
                throw "Report metadata '$MetadataPath' has a Provider that differs from its directory."
            }
            if (-not $SeenIds.Add([string] $Metadata.Id)) {
                throw "Report metadata Id '$($Metadata.Id)' is duplicated."
            }
            foreach ($Key in @('SupportsSampleData','SupportsProvidedData','SupportsLiveCollection')) {
                if ($Metadata[$Key] -isnot [bool]) { throw "Report metadata '$MetadataPath' has a non-Boolean '$Key'." }
            }
            [pscustomobject][ordered]@{
                Id = [string] $Metadata.Id
                Provider = [string] $Metadata.Provider
                Name = [string] $Metadata.Name
                Description = [string] $Metadata.Description
                Category = [string] $Metadata.Category
                Command = [string] $Metadata.Command
                Status = [string] $Metadata.Status
                SupportsSampleData = [bool] $Metadata.SupportsSampleData
                SupportsProvidedData = [bool] $Metadata.SupportsProvidedData
                SupportsLiveCollection = [bool] $Metadata.SupportsLiveCollection
                MinimumPowerShellVersion = [string] $Metadata.MinimumPowerShellVersion
            }
        }
    }
}
#endregion

#region Private/Get-PSIStatusPresentation.ps1
function Get-PSIStatusPresentation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Status)
    $Key = $Status.Trim().ToLowerInvariant()
    $Map = @{
        healthy=@('healthy','SeveritySuccess'); ready=@('ready','SeveritySuccess')
        warning=@('warning','SeverityWarning'); review=@('review','SeverityWarning')
        critical=@('critical','SeverityError'); blocked=@('blocked','SeverityError')
        info=@('info','SeverityInfo'); informational=@('informational','SeverityInfo')
        unknown=@('unknown','SeverityInfo'); neutral=@('neutral','SeverityInfo')
        notchecked=@('not-checked','SeverityInfo'); nottested=@('not-tested','SeverityInfo')
        notsupported=@('not-supported','SeverityInfo'); na=@('na','SeverityInfo')
    }
    if (-not $Map.ContainsKey($Key)) { return $null }
    [pscustomobject]@{ Class=$Map[$Key][0]; Icon=$Map[$Key][1]; Label=$Status.Trim() }
}
#endregion

#region Private/Get-PSITableColumnNames.ps1
function Get-PSITableColumnNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data
    )

    $Names = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Item in $Data) {
        if ($null -eq $Item) {
            continue
        }

        if ($Item -is [System.Collections.IDictionary]) {
            foreach ($Key in $Item.Keys) {
                $Name = [string] $Key
                if (-not [string]::IsNullOrWhiteSpace($Name) -and $Seen.Add($Name)) {
                    $Names.Add($Name)
                }
            }

            continue
        }

        foreach ($Property in $Item.PSObject.Properties) {
            if (@('NoteProperty', 'Property', 'AliasProperty', 'CodeProperty') -contains [string] $Property.MemberType) {
                if (-not [string]::IsNullOrWhiteSpace($Property.Name) -and $Seen.Add($Property.Name)) {
                    $Names.Add($Property.Name)
                }
            }
        }
    }

    $Names.ToArray()
}
#endregion

#region Private/Get-PSITableValue.ps1
function Get-PSITableValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $InputObject.Keys) {
            if ([string]::Equals([string] $Key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return ,$InputObject[$Key]
            }
        }

        return $null
    }

    $Property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }

    return ,$Property.Value
}
#endregion

#region Private/New-PSIAssessmentContractObject.ps1
function New-PSIAssessmentContractObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Category','Check','Exception')][string] $Kind,
        [Parameter(Mandatory = $true)][hashtable] $Definition
    )
    $Fields = switch ($Kind) {
        Category { @('Id','Name','Description','Icon','Weight','Status','Score','CheckIds','FindingIds','ResourceIds','Metadata') }
        Check { @('Id','Name','Description','CategoryId','Status','Severity','Weight','IsBlocking','ObservedState','ExpectedState','FindingIds','ResourceIds','EvidenceIds','Recommendation','Validation','Frameworks','Tags','Metadata') }
        Exception { @('Id','Title','Description','CheckId','FindingId','ResourceIds','Reason','Owner','ApprovedBy','ApprovedAt','ExpiresAt','Status','Metadata') }
    }
    $Required = switch ($Kind) {
        Category { @('Id','Name') }
        Check { @('Id','Name','CategoryId','Status') }
        Exception { @('Id','Title','Reason','Status') }
    }
    foreach ($Key in $Definition.Keys) { if ($Key -notin $Fields) { throw "$Kind contains unknown field '$Key'." } }
    foreach ($Key in $Required) { if ([string]::IsNullOrWhiteSpace([string] $Definition[$Key])) { throw "$Kind requires a non-empty $Key." } }
    if ([string] $Definition.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind Id is invalid." }
    if ($Kind -eq 'Category' -or $Kind -eq 'Check') {
        $Weight = if ($Definition.ContainsKey('Weight')) { [double] $Definition.Weight } else { 1.0 }
        if ($Weight -le 0 -or [double]::IsNaN($Weight) -or [double]::IsInfinity($Weight)) { throw "$Kind '$($Definition.Id)' Weight must be a positive finite number." }
        $Definition.Weight = $Weight
    }
    if ($Kind -eq 'Category') {
        if ($Definition.ContainsKey('Score') -or $Definition.ContainsKey('Status')) { throw 'Category Score and Status are calculated by the posture engine.' }
        $Icon = [string] (Get-PSIProperty -InputObject $Definition -Name Icon -DefaultValue 'Document')
        [void] (Get-PSIIcon -Name $Icon -Strict)
        $Definition.Icon = $Icon
    }
    if ($Kind -eq 'Check') {
        if ($Definition.Status -notin @('Ready','Review','Blocked','NotTested','NotApplicable','Unknown')) { throw "Check '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
        if ($Definition.Severity -and $Definition.Severity -notin @('Critical','Warning','Info','Healthy','Unknown')) { throw "Check '$($Definition.Id)' has invalid Severity." }
        foreach ($NestedName in @('Recommendation','Validation')) {
            $Nested = $Definition[$NestedName]
            if ($null -ne $Nested -and $Nested -isnot [System.Collections.IDictionary]) { throw "Check '$($Definition.Id)' $NestedName must be a dictionary." }
            $Allowed = if ($NestedName -eq 'Recommendation') { @('Summary','Rationale','Priority','Action','ExpectedState','ChangeImpact','RequiresRestart','RequiresReboot','Validation','References','AutomationHint') } else { @('Method','Description','ExpectedResult','Command','EvidenceRequired','Status') }
            if ($null -ne $Nested) { foreach ($Field in $Nested.Keys) { if ($Field -notin $Allowed) { throw "Check '$($Definition.Id)' $NestedName has unknown field '$Field'." } } }
        }
    }
    if ($Kind -eq 'Exception') {
        if ($Definition.Status -notin @('Approved','Pending','Expired','Revoked')) { throw "Exception '$($Definition.Id)' has invalid Status." }
        foreach ($DateField in @('ApprovedAt','ExpiresAt')) {
            if ($null -ne $Definition[$DateField] -and $Definition[$DateField] -isnot [datetime]) { throw "Exception '$($Definition.Id)' $DateField must be a DateTime." }
        }
        if ($Definition.Status -eq 'Approved' -and ([string]::IsNullOrWhiteSpace([string] $Definition.ApprovedBy) -or $null -eq $Definition.ApprovedAt)) { throw "Approved exception '$($Definition.Id)' requires ApprovedBy and ApprovedAt." }
    }
    $Lists = @('CheckIds','FindingIds','ResourceIds','EvidenceIds','Frameworks','Tags')
    $Result = [ordered]@{}
    foreach ($Field in $Fields) {
        if ($Definition.ContainsKey($Field)) { $Result[$Field] = $Definition[$Field] }
        elseif ($Field -in $Lists) { $Result[$Field] = @() }
        elseif ($Field -eq 'Metadata') { $Result[$Field] = @{} }
        elseif ($Field -eq 'IsBlocking') { $Result[$Field] = $false }
        else { $Result[$Field] = $null }
        if ($Field -in $Lists) { $Result[$Field] = @($Result[$Field] | Where-Object { $null -ne $_ }) }
    }
    [pscustomobject] $Result
}
#endregion

#region Private/New-PSIComponent.ps1
function New-PSIComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter()]
        [hashtable] $Properties = @{}
    )

    [pscustomobject]@{
        Type       = $Type
        Properties = $Properties
    }
}
#endregion

#region Private/New-PSIContractObject.ps1
function New-PSIContractObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Finding','Resource','Evidence','Relationship')][string] $Kind,
        [Parameter(Mandatory = $true)][hashtable] $Definition
    )

    $Fields = switch ($Kind) {
        Finding { @('Id','Title','Summary','Severity','Status','Category','Subcategory','ReadinessImpact','Frameworks','AffectedResourceIds','EvidenceIds','Recommendation','Validation','Owner','RemediationState','Relationships','Tags','Metadata') }
        Resource { @('Id','Name','Type','Status','Description','Properties','FindingIds','EvidenceIds','RelationshipIds','Tags','Metadata') }
        Evidence { @('Id','Title','Type','Source','CollectedAt','Summary','Data','FindingIds','ResourceIds','Tags','Metadata') }
        Relationship { @('Id','SourceResourceId','TargetResourceId','Type','Direction','Status','Impact','FindingIds','EvidenceIds','Label','Severity','Category','Description','IsExternal','EvidenceOnly','DisplayWeight','Metadata') }
    }
    $Required = switch ($Kind) {
        Finding { @('Id','Title','Severity','Status') }
        Resource { @('Id','Name','Type','Status') }
        Evidence { @('Id','Title','Type','Source') }
        Relationship { @('Id','SourceResourceId','TargetResourceId','Type') }
    }
    foreach ($Key in $Definition.Keys) {
        if ($Key -notin $Fields) { throw "$Kind contains unknown field '$Key'." }
    }
    foreach ($Key in $Required) {
        if ([string]::IsNullOrWhiteSpace([string] $Definition[$Key])) { throw "$Kind requires a non-empty $Key." }
    }
    if ([string] $Definition.Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Kind Id must begin with a letter and contain only letters, digits, underscores or hyphens." }
    if ($Kind -eq 'Finding') {
        if ($Definition.Severity -notin @('Critical','Warning','Info','Healthy','Unknown')) { throw "Finding '$($Definition.Id)' has invalid Severity '$($Definition.Severity)'." }
        if ($Definition.Status -notin @('Open','Acknowledged','Resolved','AcceptedRisk','NotApplicable','NotTested')) { throw "Finding '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
        foreach ($NestedName in @('Recommendation','Validation')) {
            $Nested = $Definition[$NestedName]
            if ($null -ne $Nested -and $Nested -isnot [System.Collections.IDictionary]) { throw "Finding '$($Definition.Id)' $NestedName must be a dictionary." }
            $Allowed = if ($NestedName -eq 'Recommendation') { @('Summary','Rationale','Priority','Action','ExpectedState','ChangeImpact','RequiresRestart','RequiresReboot','Validation','References','AutomationHint') } else { @('Method','Description','ExpectedResult','Command','EvidenceRequired','Status') }
            if ($null -ne $Nested) { foreach ($Field in $Nested.Keys) { if ($Field -notin $Allowed) { throw "Finding '$($Definition.Id)' $NestedName has unknown field '$Field'." } } }
        }
    }
    if ($Kind -eq 'Resource' -and -not (Resolve-PSIStatus -Status ([string] $Definition.Status) -AllowInvalid)) { throw "Resource '$($Definition.Id)' has invalid Status '$($Definition.Status)'." }
    if ($Kind -eq 'Relationship') {
        if ([string]::IsNullOrWhiteSpace([string] $Definition.Direction)) { $Definition.Direction = 'Directed' }
        if ($Definition.Direction -notin @('Directed','Bidirectional')) { throw "Relationship '$($Definition.Id)' has invalid Direction." }
        if ($Definition.Status -and -not (Resolve-PSIStatus -Status ([string] $Definition.Status) -AllowInvalid)) { throw "Relationship '$($Definition.Id)' has invalid Status." }
        if ($Definition.Severity -and -not (Resolve-PSIStatus -Status ([string] $Definition.Severity) -AllowInvalid)) { throw "Relationship '$($Definition.Id)' has invalid Severity." }
        if ($null -ne $Definition.DisplayWeight -and ($Definition.DisplayWeight -isnot [ValueType] -or [double] $Definition.DisplayWeight -lt 0)) { throw "Relationship '$($Definition.Id)' has invalid DisplayWeight." }
        if ($Definition.IsExternal -and -not $Definition.EvidenceOnly) { throw "Relationship '$($Definition.Id)' external endpoints must be evidence-only." }
    }
    if ($Kind -eq 'Evidence' -and $null -ne $Definition.CollectedAt -and $Definition.CollectedAt -isnot [datetime]) { throw "Evidence '$($Definition.Id)' CollectedAt must be a DateTime." }
    $Lists = @('Frameworks','AffectedResourceIds','EvidenceIds','Relationships','Tags','FindingIds','RelationshipIds','ResourceIds')
    $Maps = @('Metadata','Properties')
    $Result = [ordered]@{}
    foreach ($Field in $Fields) {
        if ($Definition.ContainsKey($Field)) { $Result[$Field] = $Definition[$Field] }
        elseif ($Field -in $Lists) { $Result[$Field] = @() }
        elseif ($Field -in $Maps) { $Result[$Field] = @{} }
        else { $Result[$Field] = $null }
        if ($Field -in $Lists) { $Result[$Field] = @($Result[$Field] | Where-Object { $null -ne $_ }) }
    }
    [pscustomobject] $Result
}
#endregion

#region Private/Resolve-PSIApplicationNavigation.ps1
function Resolve-PSIApplicationNavigation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Report)

    $Sections = $Report.Sections
    $UsedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @('psi-app-navigation', 'psi-app-nav-toggle', 'psi-app-main', 'psi-app-command',
        'psi-fluent-icon-attribution', 'psi-dialog-title', 'psi-dialog-description', 'psi-dialog-summary')) {
        [void] $UsedIds.Add($Id)
    }
    for ($Index = 0; $Index -lt $Sections.Count; $Index++) { [void] $UsedIds.Add("psi-section-$Index") }
    foreach ($TableId in (Assert-PSIReportIds -Sections $Sections)) {
        if (-not $UsedIds.Add([string] $TableId) -or -not $UsedIds.Add("$TableId-data")) {
            throw "Application layout ID '$TableId' conflicts with a generated section or shell ID."
        }
    }
    foreach ($Anchor in (Get-PSIFindingAnchors -Sections $Sections)) {
        if (-not $UsedIds.Add([string] $Anchor.Id)) { throw "Application layout ID '$($Anchor.Id)' is duplicated." }
    }
    foreach ($Section in $Sections) {
        foreach ($Row in $Section.Rows) {
            foreach ($Component in $Row.Components) {
                if ($Component.Type -in @('Tree','Topology','RelationshipExplorer')) {
                    $PresentationId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                    if ($PresentationId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or -not $UsedIds.Add($PresentationId)) {
                        throw "Relationship presentation ID '$PresentationId' is invalid or duplicated."
                    }
                }
                if ($Component.Type -ne 'Explorer') { continue }
                $ExplorerId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ($ExplorerId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or
                    -not $UsedIds.Add($ExplorerId) -or -not $UsedIds.Add("$ExplorerId-search")) {
                    throw "Application explorer ID '$ExplorerId' is invalid or duplicated."
                }
                $ExplorerData = Get-PSIProperty -InputObject $Component.Properties -Name 'Data' -DefaultValue @()
                for ($Index = 0; $Index -lt $ExplorerData.Count; $Index++) {
                    if (-not $UsedIds.Add("$ExplorerId-detail-$Index") -or -not $UsedIds.Add("$ExplorerId-item-$Index")) {
                        throw "Application explorer item ID '$ExplorerId-item-$Index' is duplicated."
                    }
                }
            }
        }
    }

    $RawGroups = Get-PSIProperty -InputObject $Report -Name 'NavigationGroups' -DefaultValue @()
    $Views = Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()
    $IsMultiView = $null -ne $Views -and $Views.Count -gt 0
    if ($IsMultiView) {
        if ($RawGroups.Count -gt 0) { throw 'NavigationGroups and application Views cannot be combined.' }
        $ViewIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $InitialCount = 0
        $ExpectedSections = 0
        $GroupMap = [ordered]@{}
        foreach ($View in $Views) {
            $Id = [string] (Get-PSIProperty -InputObject $View -Name 'Id')
            $Title = [string] (Get-PSIProperty -InputObject $View -Name 'Title')
            $Group = [string] (Get-PSIProperty -InputObject $View -Name 'Group' -DefaultValue 'Workspace')
            $Icon = [string] (Get-PSIProperty -InputObject $View -Name 'Icon' -DefaultValue 'Document')
            $ViewSections = Get-PSIProperty -InputObject $View -Name 'Sections'
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or -not $ViewIds.Add($Id)) {
                throw "Application view ID '$Id' is invalid or duplicated."
            }
            if (-not $UsedIds.Add("psi-view-$Id")) { throw "Application view ID '$Id' conflicts with an existing element." }
            if ([string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($Group)) {
                throw "Application view '$Id' requires a Title and Group."
            }
            if ($null -eq $ViewSections -or $ViewSections.Count -eq 0) { throw "Application view '$Id' requires at least one section." }
            [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
            [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
            foreach ($ViewSection in $ViewSections) {
                if ($ExpectedSections -ge $Sections.Count -or
                    -not [object]::ReferenceEquals($ViewSection, $Sections[$ExpectedSections]) -or
                    (Get-PSIProperty -InputObject $ViewSection -Name 'ViewId') -cne $Id) {
                    throw "Application view '$Id' has sections that do not match the report section order."
                }
                $ExpectedSections++
            }
            if ((Get-PSIProperty -InputObject $View.State -Name 'Initial' -DefaultValue $false) -eq $true) { $InitialCount++ }
            if (-not $GroupMap.Contains($Group)) { $GroupMap[$Group] = [System.Collections.Generic.List[object]]::new() }
            $GroupMap[$Group].Add(@{ Id=$Id; Label=$Title; Target="psi-view-$Id"; Icon=$Icon;
                Badge=[string] (Get-PSIProperty -InputObject $View -Name 'Badge' -DefaultValue '');
                Disabled=(Get-PSIProperty -InputObject $View -Name 'Disabled' -DefaultValue $false) -eq $true;
                Selected=(Get-PSIProperty -InputObject $View.State -Name 'Initial' -DefaultValue $false) -eq $true })
        }
        if ($ExpectedSections -ne $Sections.Count) { throw 'Every application section must belong to a registered view.' }
        if ($InitialCount -gt 1) { throw 'Only one application view can be initial.' }
        foreach ($View in $Views) {
            foreach ($Command in $View.Commands) {
                if (@($Views | Where-Object { $_.Id -ceq [string] $Command.TargetView }).Count -eq 0) {
                    throw "Application view '$($View.Id)' command targets missing view '$($Command.TargetView)'."
                }
            }
        }
        $RawGroups = @(
            foreach ($GroupName in $GroupMap.Keys) { @{ Label=$GroupName; Items=$GroupMap[$GroupName] } }
        )
    }
    if ($RawGroups.Count -eq 0) {
        $DefaultItems = @(
            for ($Index = 0; $Index -lt $Sections.Count; $Index++) {
                @{ Id = "section-$Index"; Label = [string] $Sections[$Index].Title; Target = "psi-section-$Index";
                    Icon = if ($Index -eq 0) { 'NavigationHome' } else { 'Document' }; Selected = $Index -eq 0 }
            }
        )
        $RawGroups = @(@{ Label = 'Report'; Items = $DefaultItems })
    }

    $Groups = [System.Collections.Generic.List[object]]::new()
    $SelectedCount = 0
    $FirstEnabled = $null
    foreach ($RawGroup in $RawGroups) {
        $GroupLabel = [string] (Get-PSIProperty -InputObject $RawGroup -Name 'Label')
        if ([string]::IsNullOrWhiteSpace($GroupLabel)) { throw 'Each application navigation group requires a Label.' }
        $RawItems = Get-PSIProperty -InputObject $RawGroup -Name 'Items' -DefaultValue @()
        if ($RawItems.Count -eq 0) { throw "Application navigation group '$GroupLabel' requires at least one item." }
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($RawItem in $RawItems) {
            $Id = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Id')
            $Label = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Label')
            $Target = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Target')
            $Icon = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Icon' -DefaultValue 'Document')
            $Badge = [string] (Get-PSIProperty -InputObject $RawItem -Name 'Badge' -DefaultValue '')
            $Disabled = (Get-PSIProperty -InputObject $RawItem -Name 'Disabled' -DefaultValue $false) -eq $true
            $Selected = (Get-PSIProperty -InputObject $RawItem -Name 'Selected' -DefaultValue $false) -eq $true
            if ($Id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Application navigation item ID '$Id' is invalid." }
            if ([string]::IsNullOrWhiteSpace($Label)) { throw "Application navigation item '$Id' requires a Label." }
            if (-not $UsedIds.Add("psi-app-item-$Id")) { throw "Application navigation item ID '$Id' is duplicated or conflicts with another element." }
            if ($IsMultiView) {
                if ($Target -cne "psi-view-$Id") { throw "Application navigation item '$Id' must target its view." }
            }
            else {
                if (-not $Disabled -and $Target -notmatch '^psi-section-(\d+)$') { throw "Application navigation item '$Id' requires a section Target." }
                if ($Target -match '^psi-section-(\d+)$' -and [int] $Matches[1] -ge $Sections.Count) {
                    throw "Application navigation item '$Id' targets missing section '$Target'."
                }
            }
            if ($Disabled -and $Selected) { throw "Disabled application navigation item '$Id' cannot be selected." }
            [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
            [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
            if ($Selected) { $SelectedCount++ }
            $Item = [pscustomobject]@{ Id = $Id; Label = $Label; Target = $Target; Icon = $Icon;
                Badge = $Badge; Disabled = $Disabled; Selected = $Selected }
            if (-not $Disabled -and $null -eq $FirstEnabled) { $FirstEnabled = $Item }
            $Items.Add($Item)
        }
        $Groups.Add([pscustomobject]@{ Label = $GroupLabel; Items = $Items })
    }
    if ($SelectedCount -gt 1) { throw 'Only one application navigation item can be selected.' }
    if ($null -eq $FirstEnabled) { throw 'Application navigation requires at least one enabled item.' }
    if ($SelectedCount -eq 0) { $FirstEnabled.Selected = $true }
    ,$Groups
}
#endregion

#region Private/Resolve-PSIAssessmentPosture.ps1
function Resolve-PSIAssessmentPosture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter()][AllowNull()][pscustomobject] $Model = $null
    )
    [void] (Assert-PSIApplicationAssessment -Assessment $Assessment -Model $Model)
    $Points = @{ Ready=100.0; Review=50.0; Blocked=0.0; NotTested=0.0; Unknown=0.0 }
    $Counts = [ordered]@{ Ready=0; Review=0; Blocked=0; NotTested=0; NotApplicable=0; Unknown=0; Blockers=0; CriticalFindings=0 }
    $CategoryScores = [System.Collections.Generic.List[object]]::new()
    $OverallNumerator = 0.0
    $OverallDenominator = 0.0
    foreach ($Category in $Assessment.Categories) {
        $Numerator = 0.0
        $Denominator = 0.0
        $CategoryChecks = @($Assessment.Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
        $CategoryCounts = @{ Ready=0; Review=0; Blocked=0; NotTested=0; NotApplicable=0; Unknown=0 }
        foreach ($Check in $CategoryChecks) {
            $Status = [string] $Check.Status
            $CategoryCounts[$Status]++
            $Counts[$Status]++
            if ($Status -ne 'NotApplicable') {
                $Weight = [double] $Check.Weight
                $Denominator += $Weight
                $Numerator += $Weight * [double] $Points[$Status]
            }
            if ($Check.IsBlocking -and $Status -in @('Review','Blocked')) { $Counts.Blockers++ }
        }
        $Score = if ($Denominator -gt 0) { [math]::Round($Numerator / $Denominator, 1) } else { $null }
        $Category.Score = $Score
        $Category.Status = if ($CategoryCounts.Blocked -gt 0) { 'Blocked' }
            elseif ($CategoryCounts.NotTested -gt 0) { 'NotTested' }
            elseif ($CategoryCounts.Unknown -gt 0) { 'Unknown' }
            elseif ($CategoryCounts.Review -gt 0) { 'Review' }
            elseif ($CategoryCounts.Ready -gt 0) { 'Ready' }
            else { 'NotApplicable' }
        if ($null -ne $Score) {
            $OverallNumerator += [double] $Category.Weight * [double] $Score
            $OverallDenominator += [double] $Category.Weight
        }
        $CategoryScores.Add([pscustomobject]@{
            Id=$Category.Id; Name=$Category.Name; Score=$Score; Weight=[double] $Category.Weight
            Status=$Category.Status; CheckCount=$CategoryChecks.Count; ApplicableCheckWeight=$Denominator
            Counts=[pscustomobject] $CategoryCounts
            WeightedContribution=if ($null -ne $Score) { [math]::Round([double] $Category.Weight * [double] $Score, 2) } else { $null }
        })
    }
    if ($null -ne $Model) {
        $AssessmentFindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Id in @($Assessment.FindingIds)) { [void] $AssessmentFindingIds.Add([string] $Id) }
        foreach ($Finding in $Model.Findings) {
            if ($AssessmentFindingIds.Contains([string] $Finding.Id) -and $Finding.Severity -eq 'Critical' -and $Finding.Status -notin @('Resolved','AcceptedRisk','NotApplicable')) {
                $Counts.CriticalFindings++
            }
        }
    }
    $Score = if ($OverallDenominator -gt 0) { [math]::Round($OverallNumerator / $OverallDenominator, 1) } else { $null }
    $Thresholds = $Assessment.Thresholds
    $Reasons = [System.Collections.Generic.List[string]]::new()
    if ($Counts.Blockers -gt 0) { $Reasons.Add("$($Counts.Blockers) blocking checks require action.") }
    if ($Counts.CriticalFindings -gt 0) { $Reasons.Add("$($Counts.CriticalFindings) open critical findings affect this assessment.") }
    if ($Counts.Blocked -gt 0) { $Reasons.Add("$($Counts.Blocked) checks are blocked.") }
    if ($Counts.NotTested -gt 0) { $Reasons.Add("$($Counts.NotTested) checks were not tested and count as zero until assessed.") }
    if ($Counts.Unknown -gt 0) { $Reasons.Add("$($Counts.Unknown) checks have unknown results and count as zero until assessed.") }
    if ($Counts.Review -gt 0) { $Reasons.Add("$($Counts.Review) checks require review and contribute half credit.") }
    if ($Counts.NotApplicable -gt 0) { $Reasons.Add("$($Counts.NotApplicable) not-applicable checks are excluded from the score denominator.") }
    $Decision = if ($Counts.Blockers -gt 0 -or $Counts.CriticalFindings -gt 0 -or $Counts.Blocked -gt 0) { 'NotReady' }
        elseif ($Counts.NotTested -gt 0) { 'Incomplete' }
        elseif ($Counts.Unknown -gt 0 -or $null -eq $Score) { 'Unknown' }
        elseif ($Score -ge [double] $Thresholds.Ready -and $Counts.Review -eq 0) { 'Ready' }
        elseif ($Score -ge [double] $Thresholds.Review) { 'ReadyWithReview' }
        else { 'ReviewRequired' }
    if ($Reasons.Count -eq 0) { $Reasons.Add('All applicable checks are ready.') }
    $Status = switch ($Decision) { Ready { 'Healthy' } ReadyWithReview { 'Warning' } ReviewRequired { 'Warning' } NotReady { 'Critical' } Incomplete { 'NotChecked' } default { 'Unknown' } }
    $Assessment.Score = $Score
    $Assessment.Decision = $Decision
    $Assessment.OverallStatus = $Status
    $Assessment.ScoreExplanation = [pscustomobject]@{
        CategoryScores=$CategoryScores.ToArray(); Counts=[pscustomobject] $Counts; Reasons=$Reasons.ToArray()
        CheckPoints=@{ Ready=100; Review=50; Blocked=0; NotTested=0; Unknown=0; NotApplicable='Excluded' }
        CategoryFormula='Weighted mean of applicable check points; category weights combine category scores.'
        Thresholds=$Thresholds; ExcludedCategoryCount=@($CategoryScores | Where-Object { $null -eq $_.Score }).Count
    }
    $Assessment
}
#endregion

#region Private/Resolve-PSIAssessmentStatus.ps1
function Resolve-PSIAssessmentStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Status)
    switch ($Status) {
        Ready { 'Healthy' }
        Review { 'Warning' }
        Blocked { 'Critical' }
        NotTested { 'NotChecked' }
        NotApplicable { 'Neutral' }
        Unknown { 'Unknown' }
        default { throw "Unsupported assessment status '$Status'." }
    }
}
#endregion

#region Private/Resolve-PSIEvidenceDefinition.ps1
function Resolve-PSIEvidenceDefinition {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string] $TableId = '',
        [Parameter()][AllowNull()][object] $Filter = $null,
        [Parameter()][string[]] $EvidenceColumns = @(),
        [Parameter()][string[]] $ExportColumns = @(),
        [Parameter()][hashtable] $Labels = @{},
        [Parameter()][switch] $UseVisibleColumns
    )

    $FilterTable = [string] (Get-PSIProperty -InputObject $Filter -Name 'Table')
    if (-not [string]::IsNullOrWhiteSpace($FilterTable)) {
        if (-not [string]::IsNullOrWhiteSpace($TableId) -and $TableId -ne $FilterTable) {
            throw 'EvidenceTableId and EvidenceFilter.Table must reference the same table.'
        }
        $TableId = $FilterTable
    }
    $SingleProperty = [string] (Get-PSIProperty -InputObject $Filter -Name 'Property')
    $RawConditions = Get-PSIProperty -InputObject $Filter -Name 'Conditions'
    $HasFilter = $null -ne $Filter -and $Filter -is [System.Collections.IDictionary] -and $Filter.Count -gt 0
    if ([string]::IsNullOrWhiteSpace($TableId)) {
        if ($HasFilter -or -not [string]::IsNullOrWhiteSpace($SingleProperty) -or $null -ne $RawConditions) {
            throw 'EvidenceFilter requires an EvidenceTableId or a matching Table entry.'
        }
        return $null
    }

    $Conditions = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $RawConditions) {
        foreach ($Condition in @($RawConditions)) { $Conditions.Add($Condition) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SingleProperty)) {
        $Operator = [string] (Get-PSIProperty -InputObject $Filter -Name 'Operator' -DefaultValue 'Equals')
        $SingleCondition = [ordered]@{ Property = $SingleProperty; Operator = $Operator }
        $Values = Get-PSIProperty -InputObject $Filter -Name 'Values'
        if ($Operator -eq 'In') { $SingleCondition['Values'] = @($Values) }
        else { $SingleCondition['Value'] = Get-PSIProperty -InputObject $Filter -Name 'Value' }
        $Conditions.Add($SingleCondition)
    }
    elseif ($HasFilter -and [string]::IsNullOrWhiteSpace($FilterTable)) {
        throw 'EvidenceFilter must contain Property or Conditions.'
    }

    foreach ($Condition in $Conditions) {
        $Property = [string] (Get-PSIProperty -InputObject $Condition -Name 'Property')
        $Operator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator' -DefaultValue 'Equals')
        if ([string]::IsNullOrWhiteSpace($Property)) { throw 'Each evidence condition requires a non-empty Property.' }
        if ($Operator -notin @('Equals', 'NotEquals', 'GreaterThanOrEqual', 'LessThan', 'IsEmpty', 'IsNotEmpty', 'Contains', 'In')) {
            throw "Evidence filter operator '$Operator' is not supported by the table viewer."
        }
    }
    foreach ($Column in @($EvidenceColumns) + @($ExportColumns)) {
        if ([string]::IsNullOrWhiteSpace($Column)) { throw 'Evidence and export columns cannot contain empty names.' }
    }

    return [ordered]@{
        tableId = $TableId
        conditions = $Conditions.ToArray()
        evidenceColumns = [string[]] $EvidenceColumns
        exportColumns = [string[]] $ExportColumns
        labels = $Labels
        useVisibleColumns = [bool] $UseVisibleColumns
    }
}
#endregion

#region Private/Resolve-PSIOverallStatus.ps1
function Resolve-PSIOverallStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $FindingSummary
    )

    # No supplied findings means no assessed health verdict.
    if ($FindingSummary.Total -eq 0) { return 'Neutral' }
    foreach ($Status in @('Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral')) {
        if ($FindingSummary.$Status -gt 0) { return $Status }
    }
    'Neutral'
}
#endregion

#region Private/Resolve-PSIPrintDisplay.ps1
function Resolve-PSIPrintDisplay {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $Configuration,
        [AllowNull()][object] $LegacyConfiguration
    )

    $Defaults = @{
        Resources = @(
            @{ Property='Name'; Label='Name'; Format='Text' },
            @{ Property='Type'; Label='Type'; Format='Text' },
            @{ Property='Status'; Label='Status'; Format='Status' }
        )
        Evidence = @(
            @{ Property='Id'; Label='Evidence ID'; Format='Text' },
            @{ Property='Type'; Label='Type'; Format='Text' },
            @{ Property='Source'; Label='Source'; Format='Text' },
            @{ Property='CollectionState'; Label='Collection state'; Format='Text' },
            @{ Property='Scope'; Label='Scope'; Format='Text' },
            @{ Property='CollectedAt'; Label='Collected'; Format='DateTime' },
            @{ Property='Summary'; Label='Summary'; Format='Text' },
            @{ Property='FindingIds'; Label='Findings'; Format='List' },
            @{ Property='CheckIds'; Label='Checks'; Format='List' }
        )
        Checks = @(
            @{ Property='Id'; Label='Check ID'; Format='Text' },
            @{ Property='Name'; Label='Check'; Format='Text' },
            @{ Property='Status'; Label='Status'; Format='Status' },
            @{ Property='Weight'; Label='Weight'; Format='Number' },
            @{ Property='Observation'; Label='Observation'; Format='Text' }
        )
        Findings = @(
            @{ Property='Summary'; Label='Observed'; Format='Text' },
            @{ Property='ReadinessImpact'; Label='Expected'; Format='Text' },
            @{ Property='AffectedResourceIds'; Label='Affected resources'; Format='List' },
            @{ Property='Recommendation'; Label='Recommendation'; Format='Text' },
            @{ Property='Validation'; Label='Validation'; Format='Text' },
            @{ Property='EvidenceIds'; Label='Evidence IDs'; Format='List' }
        )
    }
    $Allowed = @{
        Resources = @('Id','Name','Type','Status','Description')
        Evidence = @('Id','Title','Type','Source','CollectionState','Scope','CollectedAt','Summary','FindingIds','ResourceIds','CheckIds')
        Checks = @('Id','Name','Status','Weight','Observation','ObservedState','ExpectedState','Description','Severity')
        Findings = @('Summary','ReadinessImpact','AffectedResourceIds','Recommendation','Validation','EvidenceIds','Owner','RemediationState','Category')
    }
    $Result = @{}
    foreach ($Kind in @('Resources','Evidence','Checks','Findings')) {
        $Section = Get-PSIProperty -InputObject $Configuration -Name $Kind -DefaultValue $null
        $PropertyName = if ($Kind -in @('Resources','Checks')) { 'Columns' } else { 'Fields' }
        $Requested = Get-PSIProperty -InputObject $Section -Name $PropertyName -DefaultValue $null
        if ($null -eq $Requested -and $Kind -eq 'Resources') {
            $Legacy = Get-PSIProperty -InputObject $LegacyConfiguration -Name 'ResourceColumns' -DefaultValue $null
            if ($null -ne $Legacy) { $Requested = @($Legacy | ForEach-Object { @{ Property=[string] $_ } }) }
        }
        if ($null -eq $Requested) { $Requested = $Defaults[$Kind] }
        $Fields = [System.Collections.Generic.List[object]]::new()
        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Index = 0
        foreach ($Spec in @($Requested)) {
            $Index++
            $Property = if ($Spec -is [string]) { [string] $Spec } else { [string] (Get-PSIProperty -InputObject $Spec -Name 'Property' -DefaultValue '') }
            if ($Property -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$' -or $Property -match '(?i)password|secret|token|credential|private.?key|auth|keytab|bearer|^Data$|^Metadata$|^Properties$') { continue }
            if ($Kind -ne 'Resources' -and $Property -notin $Allowed[$Kind]) { continue }
            if ($Kind -eq 'Resources' -and $Property -notin $Allowed.Resources -and $Property -in @('FindingIds','EvidenceIds','RelationshipIds','Tags')) { continue }
            if (-not $Seen.Add($Property)) { continue }
            $Visible = Get-PSIProperty -InputObject $Spec -Name 'Visible' -DefaultValue $true
            if ($Visible -isnot [bool] -or -not $Visible) { continue }
            $Format = [string] (Get-PSIProperty -InputObject $Spec -Name 'Format' -DefaultValue $(if ($Property -eq 'Status') { 'Status' } else { 'Text' }))
            if ($Format -notin @('Text','Boolean','DateTime','Number','Percent','Status','List')) { continue }
            $Order = Get-PSIProperty -InputObject $Spec -Name 'Order' -DefaultValue $Index
            if ($Order -isnot [int] -or $Order -lt 0 -or $Order -gt 1000) { $Order = $Index }
            $Label = [string] (Get-PSIProperty -InputObject $Spec -Name 'Label' -DefaultValue $Property)
            if ([string]::IsNullOrWhiteSpace($Label) -or $Label.Length -gt 80) { $Label = $Property }
            $Fields.Add([pscustomobject]@{ Property=$Property; Label=$Label; Format=$Format; Visible=$true; Order=$Order; Index=$Index })
        }
        if ($Fields.Count -eq 0) {
            $Index = 0
            foreach ($Spec in $Defaults[$Kind]) {
                $Index++
                $Fields.Add([pscustomobject]@{ Property=$Spec.Property; Label=$Spec.Label; Format=$Spec.Format; Visible=$true; Order=$Index; Index=$Index })
            }
        }
        $Result[$Kind] = @($Fields | Sort-Object Order,Index | Select-Object -First $(if ($Kind -in @('Resources','Checks')) { 6 } else { 12 }))
    }
    $Identity = Get-PSIProperty -InputObject $Configuration -Name 'ReportIdentity' -DefaultValue $null
    $Kicker = Get-PSIProperty -InputObject $Identity -Name 'Kicker' -DefaultValue $null
    $Result.ReportIdentity = if ($Kicker -is [string] -and $Kicker.Length -le 100 -and -not [string]::IsNullOrWhiteSpace($Kicker)) { $Kicker } else { 'PSInsightHTML / Assessment document' }
    [pscustomobject] $Result
}

function Get-PSIPrintFieldValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Resources','Evidence','Checks','Findings')][string] $Kind,
          [Parameter(Mandatory)][object] $Record,
          [Parameter(Mandatory)][string] $Property,
          [AllowNull()][object] $CheckIds)

    if ($Kind -eq 'Resources') {
        if ($Property -in @('Id','Name','Type','Status','Description')) { return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null }
        return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Properties' -DefaultValue $null) -Name $Property -DefaultValue $null
    }
    if ($Kind -eq 'Checks') {
        if ($Property -eq 'Observation') {
            $Observed = Get-PSIProperty -InputObject $Record -Name 'ObservedState' -DefaultValue ''
            $Expected = Get-PSIProperty -InputObject $Record -Name 'ExpectedState' -DefaultValue ''
            return "Observed: $Observed; Expected: $Expected"
        }
        return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null
    }
    if ($Kind -eq 'Findings') {
        if ($Property -eq 'Recommendation') { return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Recommendation' -DefaultValue $null) -Name 'Action' -DefaultValue $null }
        if ($Property -eq 'Validation') { return Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Validation' -DefaultValue $null) -Name 'Method' -DefaultValue $null }
        return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null
    }
    switch ($Property) {
        'CheckIds' { return $CheckIds }
        'Scope' {
            $Scope = Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Record -Name 'Metadata' -DefaultValue $null) -Name 'Scope' -DefaultValue $null
            if ($null -ne $Scope) { return $Scope }
            return @(Get-PSIProperty -InputObject $Record -Name 'ResourceIds' -DefaultValue @())
        }
        'CollectionState' {
            $Metadata = Get-PSIProperty -InputObject $Record -Name 'Metadata' -DefaultValue $null
            $State = Get-PSIProperty -InputObject $Metadata -Name 'CollectionState' -DefaultValue $null
            if ($State -in @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')) { return $State }
            $Applicability = Get-PSIProperty -InputObject $Metadata -Name 'CollectionStateApplicability' -DefaultValue $null
            if ($Applicability -eq 'NotApplicable') { return 'Not applicable' }
            return 'Not supplied'
        }
        default { return Get-PSIProperty -InputObject $Record -Name $Property -DefaultValue $null }
    }
}

function Format-PSIPrintField {
    [CmdletBinding()]
    param([AllowNull()][object] $Value, [Parameter(Mandatory)][string] $Format)

    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Collections.IDictionary]) { return '' }
    if ($Value -is [array] -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])) {
        $Items = @($Value | Where-Object { $null -ne $_ -and ($_ -is [string] -or $_ -is [ValueType]) -and -not [string]::IsNullOrWhiteSpace([string] $_) })
        if ($Items.Count -eq 0) { return '' }
        $Value = $Items -join ', '
    }
    if ($Value -isnot [string] -and $Value -isnot [ValueType]) { return '' }
    if ([string]::IsNullOrWhiteSpace([string] $Value)) { return '' }
    switch ($Format) {
        Boolean { if ($Value -is [bool]) { return $(if ($Value) { 'Yes' } else { 'No' }) } }
        DateTime { if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm zzz') } }
        Number { if ($Value -is [ValueType] -and $Value -isnot [bool]) { return [string] $Value } }
        Percent { if ($Value -is [ValueType] -and $Value -isnot [bool]) { return ([string] $Value) + '%' } }
    }
    return [string] $Value
}
#endregion

#region Private/Resolve-PSIRelationshipPresentation.ps1
function Resolve-PSIRelationshipPresentation {
    <# .SYNOPSIS Normalize provider-neutral resources, hierarchy and relationships for presentation. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Model,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @()
    )

    $Diagnostics = [System.Collections.Generic.List[string]]::new()
    $ResourceMap = @{}
    foreach ($Resource in @($Model.Resources)) { $ResourceMap[[string] $Resource.Id] = $Resource }
    $FindingMap = @{}
    foreach ($Finding in @($Model.Findings)) { $FindingMap[[string] $Finding.Id] = $Finding }
    $EvidenceMap = @{}
    foreach ($Evidence in @($Model.Evidence)) { $EvidenceMap[[string] $Evidence.Id] = $Evidence }
    $Specs = if ($null -ne $Nodes) { @($Nodes) } else { @($Model.Resources | ForEach-Object { @{ NodeId=$_.Id; ResourceId=$_.Id } }) }
    $NodeMap = @{}
    $NormalizedNodes = [System.Collections.Generic.List[object]]::new()
    $Sequence = 0
    foreach ($Spec in $Specs) {
        $Sequence++
        $Id = [string] (Get-PSIProperty -InputObject $Spec -Name 'NodeId' -DefaultValue (Get-PSIProperty -InputObject $Spec -Name 'Id' -DefaultValue ''))
        $ResourceId = [string] (Get-PSIProperty -InputObject $Spec -Name 'ResourceId' -DefaultValue $Id)
        if ([string]::IsNullOrWhiteSpace($Id) -or $Id.Length -gt 200) { $Diagnostics.Add('A node with an invalid ID was omitted.'); continue }
        if ($NodeMap.ContainsKey($Id)) { $Diagnostics.Add("Duplicate node '$Id' was omitted."); continue }
        $Resource = if ($ResourceMap.ContainsKey($ResourceId)) { $ResourceMap[$ResourceId] } else { $null }
        $External = (Get-PSIProperty -InputObject $Spec -Name 'IsExternal' -DefaultValue $false) -eq $true
        $EvidenceOnly = (Get-PSIProperty -InputObject $Spec -Name 'EvidenceOnly' -DefaultValue $false) -eq $true
        if ($null -eq $Resource -and -not ($External -and $EvidenceOnly)) { $Diagnostics.Add("Node '$Id' has no linked resource and was omitted."); continue }
        $Name = [string] (Get-PSIProperty -InputObject $Spec -Name 'Label' -DefaultValue (Get-PSIProperty -InputObject $Resource -Name 'Name' -DefaultValue $Id))
        $Type = [string] (Get-PSIProperty -InputObject $Spec -Name 'NodeType' -DefaultValue (Get-PSIProperty -InputObject $Resource -Name 'Type' -DefaultValue 'External endpoint'))
        $Status = [string] (Get-PSIProperty -InputObject $Spec -Name 'Status' -DefaultValue (Get-PSIProperty -InputObject $Resource -Name 'Status' -DefaultValue 'Unknown'))
        $ResolvedStatus = Resolve-PSIStatus -Status $Status -AllowInvalid
        if (-not $ResolvedStatus) { $ResolvedStatus = 'Unknown' }
        $Icon = [string] (Get-PSIProperty -InputObject $Spec -Name 'Icon' -DefaultValue $(if ($External) { 'Relationship' } else { 'ResourceServer' }))
        try { [void] (Get-PSIIcon -Name $Icon -Strict) } catch { $Icon = 'ResourceServer' }
        $Description = [string] (Get-PSIProperty -InputObject $Spec -Name 'Description' -DefaultValue (Get-PSIProperty -InputObject $Resource -Name 'Description' -DefaultValue ''))
        $ParentId = [string] (Get-PSIProperty -InputObject $Spec -Name 'ParentId' -DefaultValue '')
        $SortOrder = Get-PSIProperty -InputObject $Spec -Name 'SortOrder' -DefaultValue $Sequence
        if ($SortOrder -isnot [int] -or $SortOrder -lt 0) { $SortOrder = $Sequence }
        $Details = [System.Collections.Generic.List[object]]::new()
        foreach ($Property in $DetailProperties) {
            if ($Property -notmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$' -or $Property -match '(?i)password|secret|token|credential|private.?key|auth|bearer') { continue }
            $Value = Get-PSIProperty -InputObject (Get-PSIProperty -InputObject $Resource -Name 'Properties' -DefaultValue $null) -Name $Property -DefaultValue $null
            if ($null -eq $Value -or $Value -is [System.Collections.IDictionary]) { continue }
            if ($Value -is [array]) { $Value = @($Value | Where-Object { $_ -is [string] -or $_ -is [ValueType] }) -join ', ' }
            if ($Value -isnot [string] -and $Value -isnot [ValueType]) { continue }
            if ([string]::IsNullOrWhiteSpace([string] $Value)) { continue }
            $Details.Add([pscustomobject]@{ Label=($Property -creplace '([a-z])([A-Z])', '$1 $2'); Value=[string] $Value })
        }
        $FindingLinks = @(
            foreach ($FindingId in @(Get-PSIProperty -InputObject $Resource -Name 'FindingIds' -DefaultValue @())) {
                if ($FindingMap.ContainsKey([string] $FindingId)) { [pscustomobject]@{ Id=[string] $FindingId; Label=[string] $FindingMap[[string] $FindingId].Title } }
            }
        )
        $EvidenceLinks = @(
            foreach ($EvidenceId in @(Get-PSIProperty -InputObject $Resource -Name 'EvidenceIds' -DefaultValue @())) {
                if ($EvidenceMap.ContainsKey([string] $EvidenceId)) { [pscustomobject]@{ Id=[string] $EvidenceId; Label=[string] $EvidenceMap[[string] $EvidenceId].Title } }
            }
        )
        $Node = [pscustomobject]@{
            Id=$Id; ResourceId=if ($Resource) { $ResourceId } else { '' }; ParentId=$ParentId
            Name=$Name; Type=$Type; Status=$ResolvedStatus; Icon=$Icon; Description=$Description
            SortOrder=[int] $SortOrder; External=$External; EvidenceOnly=$EvidenceOnly
            Details=$Details.ToArray(); Findings=$FindingLinks; Evidence=$EvidenceLinks
        }
        $NodeMap[$Id] = $Node
        $NormalizedNodes.Add($Node)
    }
    foreach ($Node in $NormalizedNodes) {
        if ($Node.ParentId -and -not $NodeMap.ContainsKey($Node.ParentId)) {
            $Diagnostics.Add("Node '$($Node.Id)' has a missing parent and was made a root.")
            $Node.ParentId = ''
        }
        if ($Node.ParentId -ieq $Node.Id) {
            $Diagnostics.Add("Node '$($Node.Id)' cannot parent itself and was made a root.")
            $Node.ParentId = ''
        }
    }
    foreach ($Node in $NormalizedNodes) {
        $Visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Current = $Node
        while ($Current.ParentId) {
            if (-not $Visited.Add($Current.Id) -or $Visited.Contains($Current.ParentId)) {
                $Diagnostics.Add("Hierarchy cycle involving '$($Node.Id)' was broken.")
                $Current.ParentId = ''
                break
            }
            $Current = $NodeMap[$Current.ParentId]
        }
    }
    $EdgeSpecs = if ($null -ne $Relationships) { @($Relationships) } else { @($Model.Relationships) }
    $Edges = [System.Collections.Generic.List[object]]::new()
    $EdgeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Spec in $EdgeSpecs) {
        $Id = [string] (Get-PSIProperty -InputObject $Spec -Name 'Id' -DefaultValue '')
        $SourceId = [string] (Get-PSIProperty -InputObject $Spec -Name 'SourceId' -DefaultValue (Get-PSIProperty -InputObject $Spec -Name 'SourceResourceId' -DefaultValue ''))
        $TargetId = [string] (Get-PSIProperty -InputObject $Spec -Name 'TargetId' -DefaultValue (Get-PSIProperty -InputObject $Spec -Name 'TargetResourceId' -DefaultValue ''))
        if (-not $Id -or -not $SourceId -or -not $TargetId -or -not $EdgeIds.Add($Id)) { $Diagnostics.Add('An invalid or duplicate relationship was omitted.'); continue }
        $External = (Get-PSIProperty -InputObject $Spec -Name 'IsExternal' -DefaultValue $false) -eq $true
        $EvidenceOnly = (Get-PSIProperty -InputObject $Spec -Name 'EvidenceOnly' -DefaultValue $false) -eq $true
        foreach ($Endpoint in @($SourceId,$TargetId)) {
            if ($NodeMap.ContainsKey($Endpoint) -or -not ($External -and $EvidenceOnly)) { continue }
            $ExternalNode = [pscustomobject]@{ Id=$Endpoint; ResourceId=''; ParentId=''; Name=$Endpoint; Type='External endpoint'; Status='Unknown'; Icon='Relationship'; Description='External / evidence only'; SortOrder=9999; External=$true; EvidenceOnly=$true; Details=@(); Findings=@(); Evidence=@() }
            $NodeMap[$Endpoint] = $ExternalNode
            $NormalizedNodes.Add($ExternalNode)
        }
        if (-not $NodeMap.ContainsKey($SourceId) -or -not $NodeMap.ContainsKey($TargetId)) { $Diagnostics.Add("Relationship '$Id' references a missing node and was omitted."); continue }
        $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Spec -Name 'Status' -DefaultValue 'Unknown')) -AllowInvalid
        if (-not $Status) { $Status = 'Unknown' }
        $Direction = [string] (Get-PSIProperty -InputObject $Spec -Name 'Direction' -DefaultValue 'Directed')
        if ($Direction -notin @('Directed','Bidirectional')) { $Direction = 'Directed' }
        $Type = [string] (Get-PSIProperty -InputObject $Spec -Name 'Type' -DefaultValue 'related-to')
        $Label = [string] (Get-PSIProperty -InputObject $Spec -Name 'Label' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $Type }
        $Description = [string] (Get-PSIProperty -InputObject $Spec -Name 'Description' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($Description)) { $Description = [string] (Get-PSIProperty -InputObject $Spec -Name 'Impact' -DefaultValue '') }
        $Edge = [pscustomobject]@{
            Id=$Id; SourceId=$SourceId; TargetId=$TargetId; Type=$Type
            Label=$Label
            Direction=$Direction; Status=$Status
            Category=[string] (Get-PSIProperty -InputObject $Spec -Name 'Category' -DefaultValue '')
            Description=$Description
            External=$External; EvidenceOnly=$EvidenceOnly
            Findings=@(foreach ($FindingId in @(Get-PSIProperty -InputObject $Spec -Name 'FindingIds' -DefaultValue @())) { if ($FindingMap.ContainsKey([string] $FindingId)) { [pscustomobject]@{ Id=[string] $FindingId; Label=[string] $FindingMap[[string] $FindingId].Title } } })
            Evidence=@(foreach ($EvidenceId in @(Get-PSIProperty -InputObject $Spec -Name 'EvidenceIds' -DefaultValue @())) { if ($EvidenceMap.ContainsKey([string] $EvidenceId)) { [pscustomobject]@{ Id=[string] $EvidenceId; Label=[string] $EvidenceMap[[string] $EvidenceId].Title } } })
        }
        $Edges.Add($Edge)
    }
    [pscustomobject]@{
        Nodes=@($NormalizedNodes | Sort-Object SortOrder,Name)
        Edges=$Edges.ToArray()
        Diagnostics=$Diagnostics.ToArray()
    }
}
#endregion

#region Private/Resolve-PSIStatus.ps1
function Resolve-PSIStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string] $Status,

        [Parameter()]
        [switch] $AllowInvalid
    )

    $Candidate = if ($null -eq $Status) { '' } else { $Status.Trim() }
    foreach ($Canonical in $PSIStatusValues) {
        if ([string]::Equals($Candidate, $Canonical, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Canonical
        }
    }
    foreach ($Alias in $PSIStatusAliases.Keys) {
        if ([string]::Equals($Candidate, [string] $Alias, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string] $PSIStatusAliases[$Alias]
        }
    }

    if ($AllowInvalid) { return $null }
    throw "Unsupported PSInsightHTML status '$Status'. Supported values: $($PSIStatusValues -join ', '), Info (alias for Informational)."
}
#endregion

#region Private/Test-PSICondition.ps1
function Test-PSICondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object] $InputObject,
        [Parameter(Mandatory = $true)][ValidateNotNull()][object] $Condition
    )

    $Property = [string] (Get-PSIProperty -InputObject $Condition -Name 'Property')
    $Operator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator')
    $Expected = Get-PSIProperty -InputObject $Condition -Name 'Value'
    $Actual = Get-PSITableValue -InputObject $InputObject -Name $Property

    switch ($Operator) {
        'IsNull' { return $null -eq $Actual }
        'IsNotNull' { return $null -ne $Actual }
        'Contains' {
            if ($null -eq $Actual -or $null -eq $Expected -or $Actual -is [System.Collections.IEnumerable] -and $Actual -isnot [string]) { return $false }
            return ([string] $Actual).IndexOf([string] $Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        'Match' {
            if ($null -eq $Actual -or $null -eq $Expected) { return $false }
            try { return [regex]::IsMatch([string] $Actual, [string] $Expected, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
            catch [System.ArgumentException] { return $false }
        }
    }

    if ($null -eq $Actual -or $null -eq $Expected) {
        if ($Operator -eq 'Equals') { return $null -eq $Actual -and $null -eq $Expected }
        if ($Operator -eq 'NotEquals') { return ($null -eq $Actual) -ne ($null -eq $Expected) }
        return $false
    }
    $Comparison = Compare-PSIConditionValues -Left $Actual -Right $Expected
    if ($null -eq $Comparison) { return $false }
    switch ($Operator) {
        'Equals' { return $Comparison -eq 0 }
        'NotEquals' { return $Comparison -ne 0 }
        'GreaterThan' { return $Comparison -gt 0 }
        'GreaterThanOrEqual' { return $Comparison -ge 0 }
        'LessThan' { return $Comparison -lt 0 }
        'LessThanOrEqual' { return $Comparison -le 0 }
        default { return $false }
    }
}
#endregion

#region Public/Add-PSIAlert.ps1
function Add-PSIAlert {
    <#
    .SYNOPSIS
    Add an alert card.

    .DESCRIPTION
    Displays a status-bearing message with optional timestamp, details, and action.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Status
    Alert severity.

    .PARAMETER Title
    Alert heading.

    .PARAMETER Message
    Alert description.

    .EXAMPLE
    $report | Add-PSIAlert -Status Warning -Title 'Queue' -Message 'Sample queue is growing.' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [AllowNull()]
        [object] $Timestamp = $null,

        [Parameter()]
        [AllowNull()]
        [object] $Details = $null,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Action = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Alert' -Properties @{
            Status    = Resolve-PSIStatus -Status $Status
            Title     = $Title
            Message   = $Message
            Timestamp = $Timestamp
            Details   = $Details
            Action    = $Action
        }
    }
}
#endregion

#region Public/Add-PSIAssessment.ps1
function Add-PSIAssessment {
    <#
    .SYNOPSIS
    Compose an assessment into a report.

    .DESCRIPTION
    Validates identifiers, then adds assessment sections, findings, and metadata to the report.

    .PARAMETER Report
    Destination report object.

    .PARAMETER Assessment
    Completed assessment to compose.

    .EXAMPLE
    $report | Add-PSIAssessment -Assessment $assessment | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Assessment
    )

    process {
        foreach ($PropertyName in @('Sections', 'Assessments', 'Findings')) {
            $Property = $Report.PSObject.Properties[$PropertyName]
            if ($null -eq $Property -or $Property.Value -isnot [System.Collections.Generic.List[object]]) {
                throw "The report requires a $PropertyName List[object]. Create it with New-PSIReport."
            }
        }
        if ($Assessment.PSObject.TypeNames -notcontains 'PSInsightHTML.Assessment' -or
            $Assessment.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Assessment.Findings -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied assessment is invalid. Create it with New-PSIAssessment.'
        }
        foreach ($Existing in $Report.Assessments) {
            if ([string]::Equals([string] $Existing.Id, [string] $Assessment.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Assessment ID '$($Assessment.Id)' already exists in this report."
            }
        }

        # Check the entire composition before changing the report, so a collision
        # cannot leave a partly appended assessment behind.
        $null = Assert-PSIReportIds -Sections $Report.Sections -AdditionalSections $Assessment.Sections
        foreach ($Section in $Assessment.Sections) {
            $ExistingId = [string] (Get-PSIProperty -InputObject $Section -Name 'AssessmentId')
            if (-not [string]::IsNullOrWhiteSpace($ExistingId) -and $ExistingId -ne $Assessment.Id) {
                throw "Section '$($Section.Title)' belongs to assessment '$ExistingId', not '$($Assessment.Id)'."
            }
        }
        foreach ($Section in $Assessment.Sections) {
            if ($null -eq $Section.PSObject.Properties['AssessmentId']) {
                $Section | Add-Member -NotePropertyName AssessmentId -NotePropertyValue $Assessment.Id
            }
            if ($null -eq $Section.PSObject.Properties['AssessmentName']) {
                $Section | Add-Member -NotePropertyName AssessmentName -NotePropertyValue $Assessment.Name
            }
            $Report.Sections.Add($Section)
        }
        foreach ($Finding in $Assessment.Findings) { $Report.Findings.Add($Finding) }
        $Report.Assessments.Add([pscustomobject]@{
            Id          = $Assessment.Id
            Name        = $Assessment.Name
            Title       = $Assessment.Title
            Provider    = $Assessment.Provider
            Description = $Assessment.Description
            Assessment = $Assessment
            SectionCount = $Assessment.Sections.Count
            FindingCount = $Assessment.Findings.Count
        })
        $Report
    }
}
#endregion

#region Public/Add-PSIAssessmentOverview.ps1
function Add-PSIAssessmentOverview {
    <# .SYNOPSIS Add a generic, application-style posture overview to the current row. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter()][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $CheckViewId = 'checks',
        [Parameter()][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $FindingViewId = 'findings'
    )
    process {
        if ($null -eq $Report.PSObject.Properties['ApplicationAssessment']) { throw 'Set-PSIApplicationAssessment must run before Add-PSIAssessmentOverview.' }
        Add-PSIComponentToLastRow -Report $Report -Type AssessmentOverview -Properties @{
            Assessment=$Report.ApplicationAssessment; Model=$Report.ApplicationModel
            CheckViewId=$CheckViewId; FindingViewId=$FindingViewId
        }
    }
}
#endregion

#region Public/Add-PSIChart.ps1
function Add-PSIChart {
    <#
    .SYNOPSIS
    Add an inline SVG chart.

    .DESCRIPTION
    Renders Bar, Line, Doughnut, or Pie charts from generic objects without an external chart library.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER ChartType
    Bar, Line, Doughnut, or Pie.

    .PARAMETER Data
    Generic chart records.

    .PARAMETER CategoryProperty
    Property used for categories.

    .PARAMETER ValueProperty
    Numeric property used for values.

    .PARAMETER FilterMetadata
    Optional chart-point table-filter mapping.

    .EXAMPLE
    $report | Add-PSIChart -Title 'By status' -ChartType Bar -Data $counts -CategoryProperty Status -ValueProperty Count | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Bar', 'Line', 'Doughnut', 'Pie')]
        [string] $ChartType = 'Bar',

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $CategoryProperty,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ValueProperty,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $SeriesProperty,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $StatusProperty,

        [Parameter()]
        [hashtable] $FilterMetadata = @{},

        [Parameter()]
        [ValidateRange(320, 1600)]
        [int] $Width = 900,

        [Parameter()]
        [ValidateRange(180, 900)]
        [int] $Height = 320,

        [Parameter()]
        [bool] $ShowLegend = $true,

        [Parameter()]
        [bool] $ShowLabels = $false,

        [Parameter()]
        [AllowEmptyString()]
        [string] $EmptyMessage = 'No chart data is available.'
    )

    process {
        $FilterMetadata = @{} + $FilterMetadata
        if ($FilterMetadata.Count -gt 0) {
            foreach ($RequiredKey in @('Table', 'Property')) {
                if (-not $FilterMetadata.ContainsKey($RequiredKey) -or
                    [string]::IsNullOrWhiteSpace([string] $FilterMetadata[$RequiredKey])) {
                    throw "FilterMetadata must contain a non-empty '$RequiredKey' value."
                }
            }

            if (-not $FilterMetadata.ContainsKey('ValueProperty')) {
                $FilterMetadata['ValueProperty'] = $CategoryProperty
            }
            if ([string]::IsNullOrWhiteSpace([string] $FilterMetadata['ValueProperty'])) {
                throw "FilterMetadata 'ValueProperty' must not be empty."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'Chart' -Properties @{
            Title            = $Title
            ChartType        = $ChartType
            Data             = [object[]] $Data
            CategoryProperty = $CategoryProperty
            ValueProperty    = $ValueProperty
            SeriesProperty   = $SeriesProperty
            StatusProperty   = $StatusProperty
            FilterMetadata   = $FilterMetadata
            Width            = $Width
            Height           = $Height
            ShowLegend       = $ShowLegend
            ShowLabels       = $ShowLabels
            EmptyMessage     = $EmptyMessage
        }
    }
}
#endregion

#region Public/Add-PSIEmptyState.ps1
function Add-PSIEmptyState {
    <# .SYNOPSIS Add a compact explanation for unavailable or empty content. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Explanation,
        [string] $Icon = 'Document',
        [string] $ActionLabel = '',
        [ValidatePattern('^$|^[A-Za-z][A-Za-z0-9_-]*$')][string] $TargetView = ''
    )
    process {
        [void] (Get-PSIIcon -Name $Icon -Strict)
        if ([bool]$ActionLabel -ne [bool]$TargetView) {
            throw 'Empty-state ActionLabel and TargetView must be supplied together.'
        }
        Add-PSIComponentToLastRow -Report $Report -Type 'EmptyState' -Properties @{
            Title=$Title; Explanation=$Explanation; Icon=$Icon
            ActionLabel=$ActionLabel; TargetView=$TargetView
        }
    }
}
#endregion

#region Public/Add-PSIExplorer.ps1
function Add-PSIExplorer {
    <#
    .SYNOPSIS
    Add a generic searchable master/detail list to an application view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')]
        [string] $Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $TitleProperty,
        [Parameter()]
        [string] $SubtitleProperty = '',
        [Parameter()]
        [string] $StatusProperty = '',
        [Parameter()]
        [string[]] $DetailProperties = @(),
        [Parameter()]
        [hashtable] $ColumnLabels = @{},
        [Parameter()]
        [string] $EmptyMessage = 'No records available.',
        [Parameter()]
        [ValidateSet('Finding','Resource','Evidence','Check','Category','Exception')]
        [string] $EntityType = '',
        [Parameter()]
        [hashtable] $LinkViews = @{ Finding='findings'; Resource='resources'; Evidence='evidence'; Check='checks' },
        [Parameter()]
        [string[]] $FilterProperties = @()
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
            (Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()).Count -eq 0) {
            throw 'Add-PSIExplorer requires an application view. Add a view first.'
        }
        if ($null -eq $Data) { $Data = @() }
        if ($EntityType -and $null -eq $Report.PSObject.Properties['ApplicationModel']) {
            throw 'An intelligence explorer requires Set-PSIApplicationModel first.'
        }
        if ($EntityType -in @('Check','Category','Exception') -and $null -eq $Report.PSObject.Properties['ApplicationAssessment']) {
            throw 'A Check or Category explorer requires Set-PSIApplicationAssessment first.'
        }
        if ($EntityType) {
            foreach ($Kind in @('Finding','Resource','Evidence')) {
                $Target = [string] $LinkViews[$Kind]
                if ($Target -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "LinkViews requires a valid $Kind view ID." }
            }
            if ($EntityType -in @('Category','Exception') -and [string] $LinkViews.Check -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'LinkViews requires a valid Check view ID.' }
        }
        foreach ($FilterProperty in $FilterProperties) {
            if ([string]::IsNullOrWhiteSpace($FilterProperty)) { throw 'FilterProperties cannot contain empty names.' }
        }
        $Properties = @{
            Id = $Id; Title = $Title; Data = @($Data); TitleProperty = $TitleProperty
            SubtitleProperty = $SubtitleProperty; StatusProperty = $StatusProperty
            DetailProperties = @($DetailProperties); ColumnLabels = $ColumnLabels
            EmptyMessage = $EmptyMessage
            EntityType = $EntityType
            Model = if ($EntityType) { $Report.ApplicationModel } else { $null }
            LinkViews = $LinkViews
            Assessment = if ($EntityType -in @('Check','Category','Exception')) { $Report.ApplicationAssessment } else { $null }
            FilterProperties = @($FilterProperties)
        }
        $Row = Get-PSILastRow -Report $Report
        $Row.Components.Add((New-PSIComponent -Type Explorer -Properties $Properties))
        $Report
    }
}
#endregion

#region Public/Add-PSIFilter.ps1
function Add-PSIFilter {
    <#
    .SYNOPSIS
    Define a table filter.

    .DESCRIPTION
    Creates a select or multiselect filter definition for Add-PSITable.

    .PARAMETER Property
    Data property to filter.

    .PARAMETER Values
    Selectable values.

    .PARAMETER Type
    Select or MultiSelect control.

    .EXAMPLE
    $filter = Add-PSIFilter -Property Status -Values @('Healthy','Warning')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Values,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Label = '',

        [Parameter()]
        [ValidateSet('Select', 'MultiSelect')]
        [string] $Type = 'Select'
    )

    if ([string]::IsNullOrWhiteSpace($Property)) {
        throw 'Filter Property cannot be null, empty, or whitespace.'
    }
    if ($Values.Count -eq 0) {
        throw 'A filter definition must contain at least one selectable value.'
    }

    $FilterValues = [System.Collections.Generic.List[string]]::new()
    $SeenValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ValueItem in $Values) {
        if ($null -eq $ValueItem) {
            throw 'Filter values cannot be null.'
        }
        $ValueText = [string] $ValueItem
        if ([string]::IsNullOrWhiteSpace($ValueText)) {
            throw 'Filter values cannot be empty or whitespace.'
        }
        if (-not $SeenValues.Add($ValueText)) {
            throw "Filter value '$ValueText' is duplicated."
        }
        $FilterValues.Add($ValueText)
    }

    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = $Property
    }

    [pscustomobject]@{
        Property = $Property
        Label    = $Label
        Type     = $Type
        Values   = [string[]] $FilterValues.ToArray()
    }
}
#endregion

#region Public/Add-PSIFinding.ps1
function Add-PSIFinding {
    <#
    .SYNOPSIS
    Add a finding to a report or assessment.

    .DESCRIPTION
    Adds a structured finding card and records the finding for derived summaries.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Finding
    Object created by New-PSIFinding.

    .EXAMPLE
    $assessment | Add-PSIFinding -Finding $finding | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Finding
    )

    process {
        $Title = [string] (Get-PSIProperty -InputObject $Finding -Name 'Title')
        if ([string]::IsNullOrWhiteSpace($Title)) { throw 'A Finding requires a non-empty Title.' }
        $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
        $EvidenceTableId = [string] (Get-PSIProperty -InputObject $Finding -Name 'EvidenceTableId')
        $EvidenceFilter = Get-PSIProperty -InputObject $Finding -Name 'EvidenceFilter'
        $EvidenceColumns = @((Get-PSIProperty -InputObject $Finding -Name 'EvidenceColumns' -DefaultValue @()))
        $Definition = Resolve-PSIEvidenceDefinition -TableId $EvidenceTableId -Filter $EvidenceFilter -EvidenceColumns $EvidenceColumns -ExportColumns $EvidenceColumns -UseVisibleColumns
        if ($null -ne $Definition) { $EvidenceTableId = [string] $Definition.tableId }

        $Result = Add-PSIComponentToLastRow -Report $Report -Type 'Finding' -Properties @{
            Id              = ConvertTo-PSIFindingId -Id ([string] (Get-PSIProperty -InputObject $Finding -Name 'Id'))
            Title           = $Title
            Status          = $Status
            Category        = [string] (Get-PSIProperty -InputObject $Finding -Name 'Category')
            Description     = [string] (Get-PSIProperty -InputObject $Finding -Name 'Description')
            AffectedObject  = [string] (Get-PSIProperty -InputObject $Finding -Name 'AffectedObject')
            Impact          = [string] (Get-PSIProperty -InputObject $Finding -Name 'Impact')
            Recommendation  = [string] (Get-PSIProperty -InputObject $Finding -Name 'Recommendation')
            RuleId          = [string] (Get-PSIProperty -InputObject $Finding -Name 'RuleId')
            Source          = [string] (Get-PSIProperty -InputObject $Finding -Name 'Source')
            EvidenceTableId = $EvidenceTableId
            EvidenceFilter  = $EvidenceFilter
            EvidenceColumns = [string[]] $EvidenceColumns
            FindingReference = $Finding
        }
        if ($null -ne $Report.PSObject.Properties['Findings'] -and
            $Report.Findings -is [System.Collections.Generic.List[object]]) {
            $Report.Findings.Add($Finding)
        }
        $Result
    }
}
#endregion

#region Public/Add-PSIInsight.ps1
function Add-PSIInsight {
    <#
    .SYNOPSIS
    Add an investigation insight.

    .DESCRIPTION
    Adds a metric that can open filtered evidence from an existing table dataset.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Insight label.

    .PARAMETER Value
    Displayed metric.

    .PARAMETER Filter
    Table ID and conditions defining the evidence context.

    .PARAMETER EvidenceColumns
    Columns shown in the evidence viewer.

    .EXAMPLE
    $report | Add-PSIInsight -Title 'Review items' -Value 3 -Status Warning | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Description = '',

        [Parameter()]
        [string] $Status = 'Info',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Icon = '',

        [Parameter()]
        [hashtable] $Filter = @{},

        [Parameter()]
        [string[]] $EvidenceColumns = @(),

        [Parameter()]
        [string[]] $ExportColumns = @(),

        [Parameter()]
        [hashtable] $ColumnLabels = @{}
    )

    process {
        if ($Filter.Count -gt 0) {
            if (-not $Filter.ContainsKey('Table') -or [string]::IsNullOrWhiteSpace([string] $Filter.Table)) {
                throw "Insight Filter metadata must contain a non-empty 'Table' value."
            }
            if (-not $Filter.ContainsKey('Conditions')) {
                throw "Insight Filter metadata must contain a 'Conditions' collection (which may be empty to reference all records)."
            }
            foreach ($Condition in @($Filter.Conditions)) {
                if ($null -eq $Condition -or [string]::IsNullOrWhiteSpace([string] $Condition.Property)) {
                    throw 'Each insight filter condition must contain a non-empty Property.'
                }
                if ([string] $Condition.Operator -notin @('Equals', 'NotEquals', 'GreaterThanOrEqual', 'LessThan', 'IsEmpty', 'IsNotEmpty', 'Contains', 'In')) {
                    throw "Insight filter operator '$($Condition.Operator)' is not supported."
                }
            }
        }
        foreach ($Column in @($EvidenceColumns) + @($ExportColumns)) {
            if ([string]::IsNullOrWhiteSpace($Column)) { throw 'Evidence and export column names cannot be empty.' }
        }
        Add-PSIComponentToLastRow -Report $Report -Type 'Insight' -Properties @{
            Title = $Title
            Value = $Value
            Description = $Description
            Status = Resolve-PSIStatus -Status $Status
            Icon = $Icon
            Filter = $Filter
            EvidenceColumns = [string[]] $EvidenceColumns
            ExportColumns = [string[]] $ExportColumns
            ColumnLabels = $ColumnLabels
        }
    }
}
#endregion

#region Public/Add-PSIInspector.ps1
function Add-PSIInspector {
    <# .SYNOPSIS Add a lightweight, resource-keyed context inspector to a FluentExplorer application. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]] $Items
    )
    process {
        if ((Get-PSIProperty $Report 'Navigation') -ne 'FluentExplorer' -or
            $null -eq $Report.PSObject.Properties['ResourceExplorer']) {
            throw 'Add-PSIInspector requires a FluentExplorer Resource Explorer first.'
        }
        if ($null -ne $Report.PSObject.Properties['Inspector']) { throw 'Only one shell Context Inspector is supported.' }
        if ($Id -ieq $Report.ResourceExplorer.Id) { throw 'Inspector and Resource Explorer IDs must differ.' }
        $NodeIds = @{}
        foreach ($Node in $Report.ResourceExplorer.Nodes) { $NodeIds[$Node.Id] = $true }
        $Seen = @{}
        $Normalized = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Items) {
            $ResourceId = [string] (Get-PSIProperty $Item 'ResourceId')
            $ItemId = [string] (Get-PSIProperty $Item 'Id')
            if (-not $NodeIds.ContainsKey($ResourceId)) { throw "Inspector item '$ItemId' references unknown resource '$ResourceId'." }
            if ($ItemId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or $Seen.ContainsKey($ItemId)) { throw "Inspector item ID '$ItemId' is invalid or duplicated." }
            if ($Seen.ContainsKey($ResourceId)) { throw "Inspector resource '$ResourceId' is duplicated." }
            $Seen[$ItemId] = $true
            $Seen[$ResourceId] = $true
            $Properties = Get-PSIProperty $Item 'Properties' -DefaultValue @{}
            $Metadata = Get-PSIProperty $Item 'Metadata' -DefaultValue @{}
            if ($Properties -isnot [System.Collections.IDictionary] -or $Metadata -isnot [System.Collections.IDictionary]) {
                throw "Inspector item '$ItemId' Properties and Metadata must be dictionaries."
            }
            $Fields = [System.Collections.Generic.List[object]]::new()
            foreach ($Key in $Properties.Keys) { $Fields.Add([pscustomobject]@{ Label=[string]$Key; Value=[string]$Properties[$Key] }) }
            $Tags = [System.Collections.Generic.List[object]]::new()
            foreach ($Key in $Metadata.Keys) { $Tags.Add([pscustomobject]@{ Label=[string]$Key; Value=[string]$Metadata[$Key] }) }
            $Breadcrumb = [System.Collections.Generic.List[string]]::new()
            $RawBreadcrumb = Get-PSIProperty $Item 'Breadcrumb' -DefaultValue @()
            foreach ($Part in $RawBreadcrumb) {
                if ([string]::IsNullOrWhiteSpace([string]$Part)) { throw "Inspector item '$ItemId' has an empty breadcrumb part." }
                $Breadcrumb.Add([string]$Part)
            }
            $Actions = [System.Collections.Generic.List[object]]::new()
            $RawActions = Get-PSIProperty $Item 'Actions' -DefaultValue @()
            foreach ($Action in $RawActions) {
                $ActionLabel = [string](Get-PSIProperty $Action 'Label')
                $ActionView = [string](Get-PSIProperty $Action 'TargetView' -DefaultValue '')
                $ActionResource = [string](Get-PSIProperty $Action 'ResourceId' -DefaultValue '')
                if ([string]::IsNullOrWhiteSpace($ActionLabel) -or
                    (($ActionView -cnotmatch '^$|^[A-Za-z][A-Za-z0-9_-]*$') -or
                    ($ActionResource -and -not $NodeIds.ContainsKey($ActionResource))) -or
                    (-not $ActionView -and -not $ActionResource)) {
                    throw "Inspector item '$ItemId' has an invalid header action."
                }
                $Actions.Add([pscustomobject]@{ Label=$ActionLabel; TargetView=$ActionView; ResourceId=$ActionResource })
            }
            $Sections = [System.Collections.Generic.List[object]]::new()
            $SectionIds = @{}
            $RawSections = Get-PSIProperty $Item 'Sections' -DefaultValue @()
            foreach ($Section in $RawSections) {
                $SectionId = [string] (Get-PSIProperty $Section 'Id')
                if ($SectionId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or $SectionId -eq 'Properties' -or $SectionIds.ContainsKey($SectionId)) {
                    throw "Inspector section ID '$SectionId' is invalid or duplicated."
                }
                $SectionIds[$SectionId] = $true
                $Label = [string] (Get-PSIProperty $Section 'Title' -DefaultValue $SectionId)
                if ([string]::IsNullOrWhiteSpace($Label)) { throw "Inspector section '$SectionId' needs a Title." }
                $Blocks = [System.Collections.Generic.List[object]]::new()
                $RawBlocks = Get-PSIProperty $Section 'Blocks' -DefaultValue @()
                foreach ($Block in $RawBlocks) {
                    $RelatedId = [string] (Get-PSIProperty $Block 'ResourceId' -DefaultValue '')
                    $TargetView = [string] (Get-PSIProperty $Block 'TargetView' -DefaultValue '')
                    if ($RelatedId -and -not $NodeIds.ContainsKey($RelatedId)) { throw "Inspector block references unknown resource '$RelatedId'." }
                    if ($TargetView -and $TargetView -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Inspector block has invalid TargetView '$TargetView'." }
                    $Blocks.Add([pscustomobject]@{
                        Title=[string] (Get-PSIProperty $Block 'Title' -DefaultValue '')
                        Text=[string] (Get-PSIProperty $Block 'Text' -DefaultValue '')
                        Status=[string] (Get-PSIProperty $Block 'Status' -DefaultValue '')
                        ResourceId=$RelatedId; TargetView=$TargetView
                        ActionLabel=[string] (Get-PSIProperty $Block 'ActionLabel' -DefaultValue '')
                    })
                }
                $Sections.Add([pscustomobject]@{ Id=$SectionId; Title=$Label; Blocks=$Blocks.ToArray() })
            }
            $Normalized.Add([pscustomobject]@{
                Id=$ItemId; ResourceId=$ResourceId
                Title=[string] (Get-PSIProperty $Item 'Title' -DefaultValue '')
                Subtitle=[string] (Get-PSIProperty $Item 'Subtitle' -DefaultValue '')
                Status=Resolve-PSIStatus -Status ([string] (Get-PSIProperty $Item 'Status' -DefaultValue 'Unknown'))
                Properties=$Fields.ToArray(); Metadata=$Tags.ToArray(); Sections=$Sections.ToArray()
                Breadcrumb=$Breadcrumb.ToArray(); Actions=$Actions.ToArray()
            })
        }
        $Report | Add-Member -NotePropertyName Inspector -NotePropertyValue ([pscustomobject]@{ Id=$Id; Title=$Title; Items=$Normalized.ToArray() })
        $Report
    }
}
#endregion

#region Public/Add-PSIKeyValue.ps1
function Add-PSIKeyValue {
    <#
    .SYNOPSIS
    Add a key-value summary.

    .DESCRIPTION
    Displays an ordered dictionary of labels and values in a report card.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Card heading.

    .PARAMETER Data
    Dictionary containing the displayed key-value pairs.

    .EXAMPLE
    $report | Add-PSIKeyValue -Title 'Scope' -Data ([ordered]@{ Region = 'West' }) | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Data,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 6
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'KeyValue' -Properties @{
            Title = $Title
            Data = $Data
            Span = $Span
        }
    }
}
#endregion

#region Public/Add-PSIKPI.ps1
function Add-PSIKPI {
    <#
    .SYNOPSIS
    Add a KPI card.

    .DESCRIPTION
    Adds a generic KPI with optional status, icon, trend, filter action, or evidence drill-down.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Card label.

    .PARAMETER Value
    Displayed metric or value.

    .PARAMETER Status
    Canonical health or severity status.

    .PARAMETER VisualTone
    Optional presentation tone. The underlying Status remains unchanged.

    .PARAMETER DrillDown
    Optional records for the shared evidence viewer.

    .PARAMETER Filter
    Optional table-filter action metadata.

    .EXAMPLE
    $report | Add-PSIKPI -Title 'Available' -Value 12 -Status Healthy | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Subtitle = '',

        [Parameter()]
        [string] $Status = 'Unknown',

        [Parameter()]
        [ValidateSet('Status','Informational')]
        [string] $VisualTone = 'Status',

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 3,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Icon = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Trend = '',

        [Parameter()]
        [object] $Action = @{},

        [Parameter()]
        [AllowNull()]
        [object] $DrillDown = $null,

        [Parameter()]
        [hashtable] $Filter = @{}
    )

    process {
        if ($null -ne $Action -and $Action -isnot [System.Collections.IDictionary] -and $Action -isnot [pscustomobject]) {
            throw 'KPI Action must be a hashtable, dictionary, or PSCustomObject.'
        }
        if ($Filter.Count -gt 0) {
            foreach ($RequiredKey in @('Table', 'Property')) {
                if (-not $Filter.ContainsKey($RequiredKey) -or [string]::IsNullOrWhiteSpace([string] $Filter[$RequiredKey])) {
                    throw "KPI Filter metadata must contain a non-empty '$RequiredKey' value."
                }
            }
            if (-not $Filter.ContainsKey('Value') -and -not $Filter.ContainsKey('Values')) {
                throw "KPI Filter metadata must contain either 'Value' or 'Values'."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'KPI' -Properties @{
            Title    = $Title
            Value    = $Value
            Subtitle = $Subtitle
            Status   = Resolve-PSIStatus -Status $Status
            VisualTone = $VisualTone
            Span     = $Span
            Icon     = $Icon
            Trend    = $Trend
            Action   = $Action
            DrillDown = $DrillDown
            Filter   = $Filter
        }
    }
}
#endregion

#region Public/Add-PSIRecommendation.ps1
function Add-PSIRecommendation {
    <#
    .SYNOPSIS
    Add a recommendation card.

    .DESCRIPTION
    Displays an assessment recommendation and optional remediation text.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Recommendation heading.

    .PARAMETER Description
    Reason or context.

    .PARAMETER ActionText
    Optional remediation action.

    .EXAMPLE
    $report | Add-PSIRecommendation -Title 'Review queue' -Description 'Sample backlog grew.' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [string] $Status = 'Info',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Description,

        [Parameter()]
        [AllowEmptyString()]
        [string] $ActionText = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Recommendation' -Properties @{
            Status      = Resolve-PSIStatus -Status $Status
            Title       = $Title
            Description = $Description
            ActionText  = $ActionText
        }
    }
}
#endregion

#region Public/Add-PSIRelationshipExplorer.ps1
function Add-PSIRelationshipExplorer {
    <#
    .SYNOPSIS Add an accessible master/detail relationship list to an application view.
    .EXAMPLE $Report | Add-PSIRelationshipExplorer -Id service-links -Title 'Service relationships'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' }
    )
    process { Add-PSIRelationshipComponent -Report $Report -Type RelationshipExplorer -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -LinkViews $LinkViews }
}
#endregion

#region Public/Add-PSIReportOverview.ps1
function Add-PSIReportOverview {
    <#
    .SYNOPSIS
    Add a derived report overview.

    .DESCRIPTION
    Builds severity and assessment summary components from composed report content.

    .PARAMETER Report
    Report to extend.

    .PARAMETER IncludeTopFindings
    Include a compact list of the highest-priority findings.

    .PARAMETER MaxFindings
    Maximum number of findings to show.

    .EXAMPLE
    $report | Add-PSIReportOverview -IncludeTopFindings | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [switch] $IncludeTopFindings,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int] $MaxFindings = 10
    )

    process {
        $Summary = Get-PSIReportSummary -Report $Report
        foreach ($Section in $Report.Sections) {
            if ((Get-PSIProperty -InputObject $Section -Name 'IsOverview' -DefaultValue $false) -eq $true) {
                throw 'This report already contains a report overview.'
            }
        }

        $null = $Report | Add-PSISection -Title 'Report Overview'
        $Overview = $Report.Sections[$Report.Sections.Count - 1]
        $Overview | Add-Member -NotePropertyName IsOverview -NotePropertyValue $true

        $null = $Report | Add-PSIRow -Columns 12 |
            Add-PSIStatus -Status $Summary.OverallStatus -Label 'Overall assessment' `
                -Message ('Derived from {0} structured finding(s). No findings means Neutral.' -f $Summary.FindingCount)
        $null = $Report | Add-PSIRow -Columns 12 |
            Add-PSIKPI -Title 'Critical' -Value $Summary.FindingSummary.Critical -Status Critical -Icon 'critical' -Span 3 |
            Add-PSIKPI -Title 'Warning' -Value $Summary.FindingSummary.Warning -Status Warning -Icon 'warning' -Span 3 |
            Add-PSIKPI -Title 'Informational' -Value $Summary.FindingSummary.Informational -Status Informational -Icon 'info' -Span 3 |
            Add-PSIKPI -Title 'Assessments' -Value $Summary.AssessmentCount -Status Neutral -Icon 'dashboard' -Span 3

        $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Assessment Overview' -Size Large
        if ($Summary.AssessmentCount -eq 0) {
            $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'No assessments have been added to this report.' -Size Small
        }
        else {
            $null = $Report | Add-PSIRow -Columns 12
            foreach ($AssessmentSummary in $Summary.AssessmentSummaries) {
                $TargetIndex = -1
                for ($Index = 0; $Index -lt $Report.Sections.Count - 1; $Index++) {
                    if ([string]::Equals([string] (Get-PSIProperty -InputObject $Report.Sections[$Index] -Name 'AssessmentId'),
                        [string] $AssessmentSummary.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $TargetIndex = $Index + 1
                        break
                    }
                }
                $Action = if ($TargetIndex -ge 0) { @{ Type = 'ScrollTo'; Target = "psi-section-$TargetIndex" } } else { @{} }
                $Description = if ($AssessmentSummary.FindingCount -eq 0) { 'No structured findings' } else { '{0} finding(s)' -f $AssessmentSummary.FindingCount }
                $null = $Report | Add-PSIKPI -Title $AssessmentSummary.Name -Value $AssessmentSummary.OverallStatus `
                    -Subtitle ("$Description $([char] 0x00B7) $($AssessmentSummary.SectionCount) sections") -Status $AssessmentSummary.OverallStatus `
                    -Icon 'dashboard' -Span 3 -Action $Action
            }
        }

        if ($IncludeTopFindings) {
            $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Important Findings' -Size Large
            $OrderedFindings = [System.Collections.Generic.List[object]]::new()
            foreach ($Status in @('Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral')) {
                foreach ($Finding in $Report.Findings) {
                    if ((Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))) -eq $Status) {
                        $OrderedFindings.Add($Finding)
                    }
                }
            }
            if ($OrderedFindings.Count -eq 0) {
                $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'No structured findings were supplied.' -Size Small
            }
            elseif ($MaxFindings -gt 0) {
                $Anchors = Get-PSIFindingAnchors -Sections $Report.Sections
                $null = $Report | Add-PSIRow -Columns 12
                for ($FindingIndex = 0; $FindingIndex -lt [math]::Min($MaxFindings, $OrderedFindings.Count); $FindingIndex++) {
                    $Finding = $OrderedFindings[$FindingIndex]
                    $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
                    $Action = @{}
                    foreach ($Anchor in $Anchors) {
                        if ($null -ne $Anchor.FindingReference -and [object]::ReferenceEquals($Anchor.FindingReference, $Finding)) {
                            $Action = @{ Type = 'ScrollTo'; Target = $Anchor.Id }
                            break
                        }
                    }
                    $null = $Report | Add-PSIKPI -Title ([string] $Finding.Title) -Value $Status `
                        -Subtitle ([string] $Finding.Description) -Status $Status -Icon 'info' -Span 4 -Action $Action
                }
            }
        }
        $Report.Sections.RemoveAt($Report.Sections.Count - 1)
        $Report.Sections.Insert(0, $Overview)
        $Report
    }
}
#endregion

#region Public/Add-PSIResourceExplorer.ps1
function Add-PSIResourceExplorer {
    <# .SYNOPSIS Add a provider-neutral shell resource tree to a FluentExplorer application. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]] $Nodes,
        [string] $SelectedId = ''
    )
    process {
        if ((Get-PSIProperty $Report 'Layout') -ne 'Application' -or
            (Get-PSIProperty $Report 'Navigation') -ne 'FluentExplorer') {
            throw 'Add-PSIResourceExplorer requires an Application report with FluentExplorer navigation.'
        }
        if ($null -ne $Report.PSObject.Properties['ResourceExplorer']) { throw 'Only one shell Resource Explorer is supported.' }
        $Known = @{}
        $Normalized = [System.Collections.Generic.List[object]]::new()
        foreach ($Node in $Nodes) {
            $NodeId = [string] (Get-PSIProperty $Node 'Id')
            $Label = [string] (Get-PSIProperty $Node 'Label')
            $ParentId = [string] (Get-PSIProperty $Node 'ParentId' -DefaultValue '')
            $Icon = [string] (Get-PSIProperty $Node 'Icon' -DefaultValue 'ResourceServer')
            $Target = [string] (Get-PSIProperty $Node 'Target' -DefaultValue '')
            if ($NodeId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or $Known.ContainsKey($NodeId)) { throw "Resource node ID '$NodeId' is invalid or duplicated." }
            if ([string]::IsNullOrWhiteSpace($Label)) { throw "Resource node '$NodeId' needs a Label." }
            if ($ParentId -and $ParentId -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Resource node '$NodeId' has an invalid ParentId." }
            if ($Target -and $Target -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Resource node '$NodeId' has an invalid Target view ID." }
            [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
            [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
            $Count = Get-PSIProperty $Node 'Count' -DefaultValue $null
            if ($null -ne $Count -and ($Count -isnot [int] -or $Count -lt 0)) { throw "Resource node '$NodeId' Count must be a nonnegative integer." }
            $Metadata = Get-PSIProperty $Node 'Metadata' -DefaultValue @{}
            if ($Metadata -isnot [System.Collections.IDictionary]) { throw "Resource node '$NodeId' Metadata must be a dictionary." }
            $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty $Node 'Status' -DefaultValue 'Unknown'))
            $Selectable = (Get-PSIProperty $Node 'Selectable' -DefaultValue $true) -eq $true
            $Expandable = (Get-PSIProperty $Node 'Expandable' -DefaultValue $false) -eq $true
            $Entry = [pscustomobject]@{
                Id=$NodeId; Label=$Label; Type=[string] (Get-PSIProperty $Node 'Type' -DefaultValue 'Resource')
                Icon=$Icon; ParentId=$ParentId; Status=$Status; Count=$Count; Metadata=$Metadata
                Target=$Target; Selectable=$Selectable; Expandable=$Expandable; Depth=0
            }
            $Known[$NodeId] = $Entry
            $Normalized.Add($Entry)
        }
        foreach ($Entry in $Normalized) {
            $Seen = @{}
            $ParentId = $Entry.ParentId
            while ($ParentId) {
                if (-not $Known.ContainsKey($ParentId)) { throw "Resource node '$($Entry.Id)' references missing parent '$ParentId'." }
                if ($ParentId -eq $Entry.Id -or $Seen.ContainsKey($ParentId)) { throw "Resource hierarchy contains a cycle at '$($Entry.Id)'." }
                $Seen[$ParentId] = $true
                $Entry.Depth++
                if ($Entry.Depth -gt 32) { throw 'Resource hierarchy exceeds 32 levels.' }
                $ParentId = $Known[$ParentId].ParentId
            }
            if (@($Normalized | Where-Object { $_.ParentId -eq $Entry.Id }).Count -gt 0) { $Entry.Expandable = $true }
        }
        if (-not $SelectedId) {
            $First = @($Normalized | Where-Object { $_.Selectable } | Select-Object -First 1)
            if ($First.Count -eq 0) { throw 'Resource Explorer requires at least one selectable node.' }
            $SelectedId = $First[0].Id
        }
        if (-not $Known.ContainsKey($SelectedId) -or -not $Known[$SelectedId].Selectable) { throw "Selected resource '$SelectedId' is missing or not selectable." }
        $Report | Add-Member -NotePropertyName ResourceExplorer -NotePropertyValue ([pscustomobject]@{
            Id=$Id; Title=$Title; Nodes=$Normalized.ToArray(); SelectedId=$SelectedId
        })
        $Report
    }
}
#endregion

#region Public/Add-PSIRow.ps1
function Add-PSIRow {
    <#
    .SYNOPSIS
    Add a component row.

    .DESCRIPTION
    Appends a row to the latest section; components can then be added to that row.

    .PARAMETER Report
    Report or assessment with an existing section.

    .PARAMETER Columns
    Grid column count, from 1 to 12.

    .EXAMPLE
    $report | Add-PSIRow -Columns 12 | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Columns = 12
    )

    process {
        $SectionsProperty = $Report.PSObject.Properties['Sections']
        if ($null -eq $SectionsProperty) {
            throw 'The report does not contain a Sections collection. Create a valid report with New-PSIReport.'
        }

        $Sections = $SectionsProperty.Value
        if ($Sections -isnot [System.Collections.Generic.List[object]]) {
            throw 'The report Sections property is not a List[object].'
        }

        if ($Sections.Count -eq 0) {
            throw 'A section must be created before adding a row.'
        }

        $LastSection = $Sections[$Sections.Count - 1]
        if ($null -eq $LastSection) {
            throw 'The most recently added section is null and cannot receive a row.'
        }

        $RowsProperty = $LastSection.PSObject.Properties['Rows']
        if ($null -eq $RowsProperty) {
            throw 'The most recently added section does not contain a Rows collection.'
        }

        if ($RowsProperty.Value -isnot [System.Collections.Generic.List[object]]) {
            throw 'The most recently added section Rows property is not a List[object].'
        }

        $Row = [pscustomobject]@{
            Columns    = $Columns
            Components = [System.Collections.Generic.List[object]]::new()
        }

        $RowsProperty.Value.Add($Row)
        $Report
    }
}
#endregion

#region Public/Add-PSISection.ps1
function Add-PSISection {
    <#
    .SYNOPSIS
    Add a report section.

    .DESCRIPTION
    Appends a titled section and returns the same report object.

    .PARAMETER Report
    Report or assessment to extend.

    .PARAMETER Title
    Section heading.

    .EXAMPLE
    $report | Add-PSISection -Title 'Summary' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title
    )

    process {
        $RequiredProperties = if ($Report.PSObject.TypeNames -contains 'PSInsightHTML.Assessment') {
            @('Id', 'Name', 'Title', 'Provider', 'Description', 'Metadata', 'Sections', 'Findings')
        }
        else {
            @('Title', 'Subtitle', 'Theme', 'GeneratedOn', 'ModuleVersion', 'Sections')
        }

        foreach ($PropertyName in $RequiredProperties) {
            if ($null -eq $Report.PSObject.Properties[$PropertyName]) {
                throw "The supplied object is not a valid PSInsightHTML report. Missing property '$PropertyName'. Create reports with New-PSIReport."
            }
        }

        if ($Report.Sections -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object]. Create reports with New-PSIReport.'
        }

        $Section = [pscustomobject]@{
            Title = $Title
            Rows  = [System.Collections.Generic.List[object]]::new()
        }
        if ($Report.PSObject.TypeNames -contains 'PSInsightHTML.Assessment') {
            $Section | Add-Member -NotePropertyName AssessmentId -NotePropertyValue $Report.Id
            $Section | Add-Member -NotePropertyName AssessmentName -NotePropertyValue $Report.Name
        }

        $ViewId = [string] (Get-PSIProperty -InputObject $Report -Name 'ActiveViewId' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($ViewId)) {
            $View = @($Report.Views | Where-Object { $_.Id -ceq $ViewId })[0]
            if ($null -eq $View) { throw "Application view '$ViewId' was not found." }
            $Section | Add-Member -NotePropertyName ViewId -NotePropertyValue $ViewId
            $Report.Sections.Add($Section)
            $View.Sections.Add($Section)
        }
        else { $Report.Sections.Add($Section) }
        $Report
    }
}
#endregion

#region Public/Add-PSISparkline.ps1
function Add-PSISparkline {
    <# .SYNOPSIS Add a compact, inline SVG metric trend to the current row. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]] $Values,
        [string] $Label = '',
        [AllowNull()][object] $CurrentValue = $null,
        [string] $Status = 'Info',
        [Nullable[double]] $Minimum,
        [Nullable[double]] $Maximum,
        [ValidateRange(1, 12)][int] $Span = 3
    )
    process {
        if ($Values.Count -lt 2 -or $Values.Count -gt 120) { throw 'Sparkline Values must contain between 2 and 120 numeric points.' }
        $Numbers = [System.Collections.Generic.List[double]]::new()
        foreach ($Value in $Values) {
            if ($null -eq $Value -or $Value -is [bool]) { throw 'Sparkline Values must contain only finite numbers.' }
            $Number = 0.0
            if (-not [double]::TryParse([string] $Value, [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref] $Number) -or
                [double]::IsNaN($Number) -or [double]::IsInfinity($Number)) {
                throw 'Sparkline Values must contain only finite numbers.'
            }
            $Numbers.Add($Number)
        }
        foreach ($Bound in @($Minimum, $Maximum)) {
            if ($null -ne $Bound -and ([double]::IsNaN([double]$Bound) -or [double]::IsInfinity([double]$Bound))) {
                throw 'Sparkline Minimum and Maximum must be finite numbers.'
            }
        }
        if ($null -ne $Minimum -and $null -ne $Maximum -and [double]$Minimum -ge [double]$Maximum) {
            throw 'Sparkline Minimum must be less than Maximum.'
        }
        if (($null -ne $Minimum -and @($Numbers | Where-Object { $_ -lt [double]$Minimum }).Count -gt 0) -or
            ($null -ne $Maximum -and @($Numbers | Where-Object { $_ -gt [double]$Maximum }).Count -gt 0)) {
            throw 'Sparkline Minimum and Maximum must include all Values.'
        }
        Add-PSIComponentToLastRow -Report $Report -Type 'Sparkline' -Properties @{
            Values=$Numbers.ToArray(); Label=$Label; CurrentValue=$CurrentValue
            Status=(Resolve-PSIStatus -Status $Status); Minimum=$Minimum; Maximum=$Maximum; Span=$Span
        }
    }
}
#endregion

#region Public/Add-PSIStatus.ps1
function Add-PSIStatus {
    <#
    .SYNOPSIS
    Add a status indicator.

    .DESCRIPTION
    Displays a canonical status with optional label and message.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Status
    Healthy, Warning, Critical, Informational, Neutral, Unknown, or NotChecked.

    .PARAMETER Label
    Optional status label.

    .EXAMPLE
    $report | Add-PSIStatus -Status Healthy -Label 'Overall service' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Label = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Message = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Status' -Properties @{
            Status  = Resolve-PSIStatus -Status $Status
            Label   = $Label
            Message = $Message
        }
    }
}
#endregion

#region Public/Add-PSITable.ps1
function Add-PSITable {
    <#
    .SYNOPSIS
    Add an interactive table.

    .DESCRIPTION
    Accepts generic objects and supports columns, search, filters, sorting, pagination, export, and conditional formatting.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Data
    Records to display.

    .PARAMETER Title
    Table heading.

    .PARAMETER Columns
    Optional explicit property order.

    .PARAMETER Filters
    Definitions created by Add-PSIFilter.

    .PARAMETER Conditions
    Rules created by New-PSICondition.

    .PARAMETER PageSize
    Number of rows per page.

    .EXAMPLE
    $report | Add-PSITable -Title 'Services' -Data $services -Columns @('Name','Status') | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 12,

        [Parameter()]
        [string[]] $Columns,

        [Parameter()]
        [hashtable] $ColumnLabels = @{},

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Filters = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Conditions = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $Id = '',

        [Parameter()]
        [ValidateRange(1, 500)]
        [int] $PageSize = 10,

        [Parameter()]
        [bool] $EnableSearch = $true,

        [Parameter()]
        [bool] $EnableSorting = $true,

        [Parameter()]
        [bool] $EnablePagination = $true,

        [Parameter()]
        [AllowEmptyString()]
        [string] $EmptyMessage = 'No records match your filters.',

        [Parameter()]
        [AllowEmptyString()]
        [string] $NullValueText = [char] 0x2014,

        [Parameter()]
        [bool] $EnableExport = $true,

        [Parameter()]
        [string[]] $ExportColumns,

        [Parameter()]
        [ValidateSet('Csv', 'Xlsx', 'Print')]
        [string[]] $ExportFormats = @('Csv', 'Xlsx', 'Print'),

        [Parameter()]
        [AllowEmptyString()]
        [string] $ExportFileName = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $WorksheetName = ''
    )

    process {
        if (-not [string]::IsNullOrEmpty($Id) -and $Id -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            throw 'Table Id must start with a letter and contain only letters, numbers, underscores, or hyphens.'
        }
        if ([string]::IsNullOrWhiteSpace($Id)) {
            $Id = 'psi-table-' + [guid]::NewGuid().ToString('N')
        }
        $null = Assert-PSIReportIds -Sections $Report.Sections -ProposedTableId $Id

        $FilterProperties = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($FilterDefinition in $Filters) {
            if ($null -eq $FilterDefinition -or $null -eq $FilterDefinition.PSObject.Properties['Property']) {
                throw 'Each table filter must be created with Add-PSIFilter and contain a Property.'
            }
            if ([string] $FilterDefinition.Type -notin @('Select', 'MultiSelect')) {
                throw "Table filter '$($FilterDefinition.Property)' has an unsupported Type."
            }
            if (@($FilterDefinition.Values).Count -eq 0) {
                throw "Table filter '$($FilterDefinition.Property)' must contain selectable Values."
            }
            if (-not $FilterProperties.Add([string] $FilterDefinition.Property)) {
                throw "Table filter property '$($FilterDefinition.Property)' is defined more than once."
            }
        }

        foreach ($Condition in $Conditions) {
            if ($null -eq $Condition -or [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Condition -Name 'Property'))) {
                throw 'Each table condition must contain a non-empty Property.'
            }
            $ConditionOperator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator')
            if ($ConditionOperator -notin @('Equals', 'NotEquals', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual', 'Contains', 'Match', 'IsNull', 'IsNotNull')) {
                throw "Table condition operator '$ConditionOperator' is not supported."
            }
            $ConditionScope = [string] (Get-PSIProperty -InputObject $Condition -Name 'Scope')
            if ($ConditionScope -notin @('Cell', 'Row')) {
                throw "Table condition scope '$ConditionScope' must be Cell or Row."
            }
            $null = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
        }

        if ($PSBoundParameters.ContainsKey('Columns') -and $Columns.Count -gt 0) {
            $ResolvedColumns = [System.Collections.Generic.List[string]]::new()
            $SeenColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Column in $Columns) {
                if ([string]::IsNullOrWhiteSpace($Column)) {
                    throw 'Explicit table column names cannot be null, empty, or whitespace.'
                }

                if (-not $SeenColumns.Add($Column)) {
                    throw "Explicit table column '$Column' is duplicated."
                }

                $ResolvedColumns.Add($Column)
            }

            $ColumnNames = $ResolvedColumns.ToArray()
        }
        else {
            $ColumnNames = @(Get-PSITableColumnNames -Data $Data)
        }

        if ($PSBoundParameters.ContainsKey('ExportColumns')) {
            $SeenExportColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($ExportColumn in $ExportColumns) {
                if ([string]::IsNullOrWhiteSpace($ExportColumn) -or -not $SeenExportColumns.Add($ExportColumn)) {
                    throw 'ExportColumns must contain unique, non-empty column names.'
                }
                if (-not (@($ColumnNames) | Where-Object { [string]::Equals([string] $_, $ExportColumn, [System.StringComparison]::OrdinalIgnoreCase) })) {
                    throw "Export column '$ExportColumn' must be a visible table column."
                }
            }
        }
        else {
            $ExportColumns = [string[]] $ColumnNames
        }
        if ($EnableExport -and @($ExportFormats).Count -eq 0) {
            throw 'ExportFormats must contain at least one format when export is enabled.'
        }

        foreach ($FilterDefinition in $Filters) {
            if (-not (@($ColumnNames) | Where-Object { [string]::Equals([string] $_, [string] $FilterDefinition.Property, [System.StringComparison]::OrdinalIgnoreCase) })) {
                throw "Table filter property '$($FilterDefinition.Property)' is not included in the table columns."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'Table' -Properties @{
            Title             = $Title
            Span              = $Span
            Data              = [object[]] $Data
            Columns           = [string[]] $ColumnNames
            ColumnLabels      = $ColumnLabels
            Filters           = [object[]] $Filters
            Conditions        = [object[]] $Conditions
            Id                = $Id
            PageSize          = $PageSize
            EnableSearch      = $EnableSearch
            EnableSorting     = $EnableSorting
            EnablePagination  = $EnablePagination
            EmptyMessage      = $EmptyMessage
            NullValueText     = $NullValueText
            EnableExport      = $EnableExport
            ExportColumns     = [string[]] $ExportColumns
            ExportFormats     = [string[]] $ExportFormats
            ExportFileName    = $ExportFileName
            WorksheetName     = $WorksheetName
        }
    }
}
#endregion

#region Public/Add-PSIText.ps1
function Add-PSIText {
    <#
    .SYNOPSIS
    Add a text component.

    .DESCRIPTION
    Adds HTML-encoded explanatory text to the latest row.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Text
    Text to display.

    .PARAMETER Size
    Supported typography size.

    .EXAMPLE
    $report | Add-PSIText -Text 'Fictional sample' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('Small', 'Normal', 'Large')]
        [string] $Size = 'Normal'
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Text' -Properties @{
            Text = $Text
            Size = $Size
        }
    }
}
#endregion

#region Public/Add-PSITopology.ps1
function Add-PSITopology {
    <#
    .SYNOPSIS Add a standalone SVG relationship topology with a text-list fallback.
    .DESCRIPTION Uses application resources and relationships by default. Nodes and Relationships can scope or supplement the presentation. MaxNodes limits the graph until filters reduce its scope.
    .EXAMPLE $Report | Add-PSITopology -Id service-map -Title 'Service dependencies' -MaxNodes 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [string[]] $FilterProperties = @(),
        [ValidateRange(1,500)][int] $MaxNodes = 100,
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' }
    )
    process { Add-PSIRelationshipComponent -Report $Report -Type Topology -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -FilterProperties $FilterProperties -LinkViews $LinkViews -MaxNodes $MaxNodes }
}
#endregion

#region Public/Add-PSITree.ps1
function Add-PSITree {
    <#
    .SYNOPSIS Add a keyboard-accessible hierarchy of application resources.
    .DESCRIPTION Nodes optionally supply NodeId, ParentId, ResourceId, Label, NodeType, Status, Icon and SortOrder. Missing parents and cycles become roots with a diagnostic. External nodes require IsExternal and EvidenceOnly.
    .EXAMPLE $Report | Add-PSITree -Id service-tree -Title 'Service hierarchy' -Nodes $Hierarchy
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' }
    )
    process { Add-PSIRelationshipComponent -Report $Report -Type Tree -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -LinkViews $LinkViews }
}
#endregion

#region Public/Add-PSIView.ps1
function Add-PSIView {
    <#
    .SYNOPSIS
    Register a generic application workspace view.

    .DESCRIPTION
    Sections added after this call belong to the new view. The original flat
    report Sections collection remains available to existing components.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')]
        [string] $Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter()]
        [string] $Subtitle = '',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Icon = 'Document',

        [Parameter()]
        [string] $Group = 'Workspace',

        [Parameter()]
        [string] $Badge = '',

        [Parameter()]
        [Nullable[int]] $TabCount,

        [Parameter()]
        [switch] $Disabled,

        [Parameter()]
        [object[]] $Commands = @(),

        [Parameter()]
        [switch] $Initial
    )

    process {
        if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
            $null -eq $Report.PSObject.Properties['Views'] -or
            $Report.Views -isnot [System.Collections.Generic.List[object]]) {
            throw 'Add-PSIView requires a report created with New-PSIReport -Layout Application.'
        }
        if (@($Report.NavigationGroups).Count -gt 0) {
            throw 'NavigationGroups and application Views cannot be combined.'
        }
        if ($Report.Sections.Count -gt 0 -and $Report.Views.Count -eq 0) {
            throw 'Add the first application view before adding sections.'
        }
        if (@($Report.Views | Where-Object { $_.Id -ieq $Id }).Count -gt 0) {
            throw "Application view ID '$Id' is already registered."
        }
        if ($Initial -and @($Report.Views | Where-Object { $_.State.Initial }).Count -gt 0) {
            throw 'Only one application view can be initial.'
        }
        if ($Initial -and $Disabled) { throw 'The initial application view cannot be disabled.' }
        if ($null -ne $TabCount -and [int]$TabCount -lt 0) { throw 'TabCount must be nonnegative.' }
        if ([string]::IsNullOrWhiteSpace($Group)) { throw 'Application view Group cannot be empty.' }
        [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
        [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
        $ViewCommands = [System.Collections.Generic.List[object]]::new()
        foreach ($Command in $Commands) {
            $CommandLabel = [string] (Get-PSIProperty -InputObject $Command -Name 'Label')
            $CommandIcon = [string] (Get-PSIProperty -InputObject $Command -Name 'Icon' -DefaultValue 'Document')
            $TargetView = [string] (Get-PSIProperty -InputObject $Command -Name 'TargetView')
            if ([string]::IsNullOrWhiteSpace($CommandLabel) -or $TargetView -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
                throw 'View commands require a Label and a valid TargetView ID.'
            }
            [void] (Get-PSIIcon -Name $CommandIcon -Strict)
            $ViewCommands.Add([pscustomobject]@{ Label=$CommandLabel; Icon=$CommandIcon; TargetView=$TargetView })
        }
        $View = [pscustomobject]@{
            Id       = $Id
            Title    = $Title
            Subtitle = $Subtitle
            Icon     = $Icon
            Group    = $Group
            Badge    = $Badge
            TabCount = $TabCount
            Disabled = [bool] $Disabled
            Sections = [System.Collections.Generic.List[object]]::new()
            Commands = $ViewCommands
            State    = @{ Initial = [bool] $Initial }
        }
        $Report.Views.Add($View)
        $Report.ActiveViewId = $Id
        $Report
    }
}
#endregion

#region Public/Export-PSIReport.ps1
function Export-PSIReport {
    <#
    .SYNOPSIS
    Write a standalone HTML report.

    .DESCRIPTION
    Renders a completed report and writes an HTML file with embedded local assets.

    .PARAMETER Report
    Report containing at least one section.

    .PARAMETER Path
    Destination HTML path.

    .PARAMETER EnableReportPrint
    Whether to include the report print action.

    .PARAMETER Renderer
    Classic renders the original document/application markup. Fluent renders the interactive
    Fluent application (navigation rail, data grids, detail pane, search palette). Auto uses
    Fluent when every component in the report is supported by it, otherwise Classic.
    When omitted, the PSINSIGHTHTML_RENDERER environment variable is used, then Classic.

    .EXAMPLE
    Export-PSIReport -Report $report -Path ./Reports/Service-Health.html

    .EXAMPLE
    Export-PSIReport -Report $report -Path ./Reports/Service-Health.html -Renderer Fluent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [bool] $EnableReportPrint = $true,

        [Parameter()]
        [ValidateSet('Classic', 'Fluent', 'Auto')]
        [string] $Renderer
    )

    $SectionsProperty = $Report.PSObject.Properties['Sections']
    if ($null -eq $SectionsProperty -or $SectionsProperty.Value -isnot [System.Collections.Generic.List[object]] -or $SectionsProperty.Value.Count -eq 0) {
        throw 'The report must contain at least one section before it can be exported.'
    }

    if (-not $Renderer) {
        $Renderer = if ($env:PSINSIGHTHTML_RENDERER -in @('Classic', 'Fluent', 'Auto')) { $env:PSINSIGHTHTML_RENDERER } else { 'Classic' }
    }
    if ($Renderer -eq 'Auto') {
        $Missing = Test-PSIFluentSupport -Report $Report
        if ($Missing.Count -gt 0) {
            Write-Verbose "Fluent renderer does not support $($Missing -join ', ') yet; using the classic renderer."
            $Renderer = 'Classic'
        }
        else { $Renderer = 'Fluent' }
    }

    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $ParentDirectory = Split-Path -Path $ResolvedPath -Parent
    if (-not (Test-Path -LiteralPath $ParentDirectory -PathType Container)) {
        [void] (New-Item -Path $ParentDirectory -ItemType Directory -Force -ErrorAction Stop)
    }

    $Html = if ($Renderer -eq 'Fluent') {
        ConvertTo-PSIFluentHtml -Report $Report -EnableReportPrint $EnableReportPrint
    }
    else {
        ConvertTo-PSIHtml -Report $Report -EnableReportPrint $EnableReportPrint
    }
    [System.IO.File]::WriteAllText($ResolvedPath, $Html, [System.Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop
}
#endregion

#region Public/Get-PSIAssessmentSummary.ps1
function Get-PSIAssessmentSummary {
    <#
    .SYNOPSIS
    Summarize an assessment.

    .DESCRIPTION
    Derives section and finding counts and the overall status without rendering HTML.

    .PARAMETER Assessment
    Assessment to summarize.

    .EXAMPLE
    $summary = Get-PSIAssessmentSummary -Assessment $assessment
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Assessment
    )

    process {
        if ($Assessment.PSObject.TypeNames -notcontains 'PSInsightHTML.Assessment' -or
            $Assessment.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Assessment.Findings -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML Assessment.'
        }
        $Counts = Get-PSIFindingSummary -Findings $Assessment.Findings.ToArray()
        [pscustomobject]@{
            Id = $Assessment.Id
            Name = $Assessment.Name
            Title = $Assessment.Title
            Provider = $Assessment.Provider
            SectionCount = $Assessment.Sections.Count
            FindingCount = $Counts.Total
            Critical = $Counts.Critical
            Warning = $Counts.Warning
            Healthy = $Counts.Healthy
            Informational = $Counts.Informational
            Neutral = $Counts.Neutral
            Unknown = $Counts.Unknown
            NotChecked = $Counts.NotChecked
            OverallStatus = Resolve-PSIOverallStatus -FindingSummary $Counts
        }
    }
}
#endregion

#region Public/Get-PSIFindingSummary.ps1
function Get-PSIFindingSummary {
    <#
    .SYNOPSIS
    Summarize finding severities.

    .DESCRIPTION
    Counts structured findings using the canonical status vocabulary.

    .PARAMETER Findings
    Finding objects to count.

    .EXAMPLE
    $summary = Get-PSIFindingSummary -Findings $report.Findings
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Findings = @()
    )

    begin {
        $Counts = [ordered]@{
            Total = 0; Critical = 0; Warning = 0; Healthy = 0
            Informational = 0; Neutral = 0; Unknown = 0; NotChecked = 0
        }
    }
    process {
        foreach ($Finding in $Findings) {
            if ($null -eq $Finding) { throw 'A Finding cannot be null.' }
            $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
            $Counts[$Status]++
            $Counts.Total++
        }
    }
    end { [pscustomobject] $Counts }
}
#endregion

#region Public/Get-PSIReportCatalog.ps1
function Get-PSIReportCatalog {
    <#
    .SYNOPSIS
    List integrated report providers.

    .DESCRIPTION
    Returns capability metadata for registered report commands without collecting data.

    .PARAMETER Provider
    Optional provider-name wildcard filter.

    .PARAMETER Name
    Optional report-name wildcard filter.

    .EXAMPLE
    $catalog = Get-PSIReportCatalog
    #>
    [CmdletBinding()]
    param(
        [Parameter()][ValidateNotNullOrEmpty()][string] $Provider = '*',
        [Parameter()][ValidateNotNullOrEmpty()][string] $Name = '*'
    )

    foreach ($Report in @(Get-PSIReportMetadata)) {
        if ($Report.Provider -notlike $Provider -or $Report.Name -notlike $Name) { continue }
        if (-not (Get-Command -Name $Report.Command -Module PSInsightHTML -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Catalog command '$($Report.Command)' for report '$($Report.Id)' is not exported by PSInsightHTML."
        }
        $Report
    }
}
#endregion

#region Public/Get-PSIReportSummary.ps1
function Get-PSIReportSummary {
    <#
    .SYNOPSIS
    Summarize a composed report.

    .DESCRIPTION
    Derives assessment, section, table, and finding counts and overall status.

    .PARAMETER Report
    Report to summarize.

    .EXAMPLE
    $summary = Get-PSIReportSummary -Report $report
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report
    )

    process {
        if ($Report.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Report.Findings -isnot [System.Collections.Generic.List[object]] -or
            $Report.Assessments -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML report. Create it with New-PSIReport.'
        }
        $Counts = Get-PSIFindingSummary -Findings $Report.Findings.ToArray()
        $TableCount = 0
        foreach ($Section in $Report.Sections) {
            foreach ($Row in $Section.Rows) {
                foreach ($Component in $Row.Components) {
                    if ($Component.Type -eq 'Table') { $TableCount++ }
                }
            }
        }
        $AssessmentSummaries = [System.Collections.Generic.List[object]]::new()
        foreach ($Entry in $Report.Assessments) {
            $Assessment = Get-PSIProperty -InputObject $Entry -Name 'Assessment'
            if ($null -ne $Assessment) { $AssessmentSummaries.Add((Get-PSIAssessmentSummary -Assessment $Assessment)) }
        }
        [pscustomobject]@{
            OverallStatus = Resolve-PSIOverallStatus -FindingSummary $Counts
            FindingSummary = $Counts
            FindingCount = $Counts.Total
            AssessmentCount = $Report.Assessments.Count
            SectionCount = $Report.Sections.Count
            TableCount = $TableCount
            AssessmentSummaries = $AssessmentSummaries.ToArray()
        }
    }
}
#endregion

#region Public/New-PSIApplicationAssessment.ps1
function New-PSIApplicationAssessment {
    <# .SYNOPSIS Create a generic assessment with computed posture and decision. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    $Allowed = @('Id','Name','Description','AssessmentType','Target','Profile','Scope','GeneratedAt','Categories','Checks','FindingIds','ResourceIds','EvidenceIds','Recommendations','Exceptions','Metadata','ReadyScoreMinimum','ReviewScoreMinimum')
    foreach ($Key in $Definition.Keys) { if ($Key -notin $Allowed) { throw "Assessment contains unknown or computed field '$Key'." } }
    $Ready = if ($Definition.ContainsKey('ReadyScoreMinimum')) { [double] $Definition.ReadyScoreMinimum } else { 90.0 }
    $Review = if ($Definition.ContainsKey('ReviewScoreMinimum')) { [double] $Definition.ReviewScoreMinimum } else { 75.0 }
    if ($Ready -lt 0 -or $Ready -gt 100 -or $Review -lt 0 -or $Review -gt $Ready) { throw 'Assessment score thresholds must satisfy 0 <= Review <= Ready <= 100.' }
    $Exceptions = @(
        foreach ($Exception in @($Definition.Exceptions | Where-Object { $null -ne $_ })) {
            if ($Exception -isnot [hashtable]) { throw 'Assessment Exceptions must be hashtables.' }
            New-PSIAssessmentContractObject -Kind Exception -Definition $Exception
        }
    )
    $Assessment = [pscustomobject]@{
        Id=$Definition.Id; Name=$Definition.Name; Description=$Definition.Description; AssessmentType=$Definition.AssessmentType
        Target=$Definition.Target; Profile=$Definition.Profile; Scope=$Definition.Scope
        GeneratedAt=if ($Definition.ContainsKey('GeneratedAt')) { $Definition.GeneratedAt } else { Get-Date }
        OverallStatus=$null; Score=$null; Decision=$null
        Categories=@($Definition.Categories); Checks=@($Definition.Checks)
        FindingIds=@($Definition.FindingIds | Where-Object { $null -ne $_ })
        ResourceIds=@($Definition.ResourceIds | Where-Object { $null -ne $_ })
        EvidenceIds=@($Definition.EvidenceIds | Where-Object { $null -ne $_ })
        Recommendations=@($Definition.Recommendations | Where-Object { $null -ne $_ })
        Exceptions=$Exceptions; Metadata=if ($Definition.Metadata) { $Definition.Metadata } else { @{} }
        Thresholds=[pscustomobject]@{ Ready=$Ready; Review=$Review }
        ScoreExplanation=$null
    }
    Resolve-PSIAssessmentPosture -Assessment $Assessment
}
#endregion

#region Public/New-PSIApplicationFinding.ps1
function New-PSIApplicationFinding {
    <# .SYNOPSIS Define a generic application finding, separate from the legacy report finding card. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Finding -Definition $Definition
}
#endregion

#region Public/New-PSIApplicationModel.ps1
function New-PSIApplicationModel {
    <# .SYNOPSIS Validate and aggregate linked generic application records. #>
    [CmdletBinding()]
    param(
        [Parameter()][object[]] $Findings = @(),
        [Parameter()][object[]] $Resources = @(),
        [Parameter()][object[]] $Evidence = @(),
        [Parameter()][object[]] $Relationships = @()
    )
    $Model = [pscustomobject]@{
        Findings = @($Findings)
        Resources = @($Resources)
        Evidence = @($Evidence)
        Relationships = @($Relationships)
        Summary = $null
    }
    [void] (Assert-PSIApplicationModel -Model $Model)
    $Groups = [ordered]@{}
    foreach ($Field in @('Severity','Category','Status')) {
        $Counts = @{}
        foreach ($Finding in $Model.Findings) {
            $Value = [string] (Get-PSIProperty -InputObject $Finding -Name $Field)
            if (-not $Counts.ContainsKey($Value)) { $Counts[$Value] = 0 }
            $Counts[$Value]++
        }
        $Groups["FindingsBy$Field"] = $Counts
    }
    $ResourcesByStatus = @{}
    foreach ($Resource in $Model.Resources) {
        $Value = [string] $Resource.Status
        if (-not $ResourcesByStatus.ContainsKey($Value)) { $ResourcesByStatus[$Value] = 0 }
        $ResourcesByStatus[$Value]++
    }
    $CriticalResourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Finding in $Model.Findings) {
        if ($Finding.Severity -eq 'Critical') { foreach ($Id in @($Finding.AffectedResourceIds)) { [void] $CriticalResourceIds.Add([string] $Id) } }
    }
    $Groups['ResourcesByStatus'] = $ResourcesByStatus
    $Groups['ResourcesWithCriticalFindings'] = $CriticalResourceIds.Count
    $Groups['EvidenceCount'] = $Model.Evidence.Count
    $Model.Summary = [pscustomobject] $Groups
    $Model
}
#endregion

#region Public/New-PSIAssessment.ps1
function New-PSIAssessment {
    <#
    .SYNOPSIS
    Create an assessment object.

    .DESCRIPTION
    Creates an independently composed assessment with sections and findings.

    .PARAMETER Id
    Stable assessment identifier; generated when omitted.

    .PARAMETER Name
    Display name used by the report overview and navigation.

    .PARAMETER Provider
    Source family label; it does not trigger collection.

    .EXAMPLE
    $assessment = New-PSIAssessment -Id 'sample' -Name 'Sample Service' -Provider 'Example'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [string] $Title = '',

        [Parameter()]
        [string] $Provider = '',

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [hashtable] $Metadata = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        $Id = 'psi-assessment-' + [guid]::NewGuid().ToString('N')
    }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $Name }

    $Assessment = [pscustomobject]@{
        Id          = $Id
        Name        = $Name
        Title       = $Title
        Provider    = $Provider
        Description = $Description
        Metadata    = $Metadata
        Sections    = [System.Collections.Generic.List[object]]::new()
        Findings    = [System.Collections.Generic.List[object]]::new()
    }
    $Assessment.PSObject.TypeNames.Insert(0, 'PSInsightHTML.Assessment')
    $Assessment
}
#endregion

#region Public/New-PSIAssessmentCategory.ps1
function New-PSIAssessmentCategory {
    <# .SYNOPSIS Define a generic weighted assessment category. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIAssessmentContractObject -Kind Category -Definition $Definition
}
#endregion

#region Public/New-PSIAssessmentCheck.ps1
function New-PSIAssessmentCheck {
    <# .SYNOPSIS Define a generic weighted assessment check. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIAssessmentContractObject -Kind Check -Definition $Definition
}
#endregion

#region Public/New-PSICondition.ps1
function New-PSICondition {
    <#
    .SYNOPSIS
    Define a table presentation condition.

    .DESCRIPTION
    Creates an ordered cell or row rule; a matching status controls visual formatting only.

    .PARAMETER Property
    Data property to compare.

    .PARAMETER Operator
    Comparison operator.

    .PARAMETER Value
    Expected value unless using IsNull or IsNotNull.

    .PARAMETER Status
    Status token for matching content.

    .PARAMETER Scope
    Cell or Row formatting scope.

    .EXAMPLE
    $rule = New-PSICondition -Property Status -Operator Equals -Value Warning -Status Warning -Scope Row
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Equals', 'NotEquals', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual', 'Contains', 'Match', 'IsNull', 'IsNotNull')]
        [string] $Operator,

        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter()]
        [ValidateSet('Cell', 'Row')]
        [string] $Scope = 'Cell'
    )

    if ($Operator -notin @('IsNull', 'IsNotNull') -and -not $PSBoundParameters.ContainsKey('Value')) {
        throw "Condition operator '$Operator' requires a Value."
    }
    if ($Operator -eq 'Match') {
        try {
            $null = [regex]::new([string] $Value, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        catch {
            throw "Condition Match pattern is invalid: $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Property = $Property
        Operator = $Operator
        Value    = $Value
        Status   = Resolve-PSIStatus -Status $Status
        Scope    = $Scope
    }
}
#endregion

#region Public/New-PSIEvidenceRecord.ps1
function New-PSIEvidenceRecord {
    <# .SYNOPSIS Define typed evidence data without converting it to HTML. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Evidence -Definition $Definition
}
#endregion

#region Public/New-PSIFinding.ps1
function New-PSIFinding {
    <#
    .SYNOPSIS
    Define a structured finding.

    .DESCRIPTION
    Creates a finding with severity, explanation, and optional reference to existing table evidence.

    .PARAMETER Title
    Finding heading.

    .PARAMETER Status
    Canonical severity or health status.

    .PARAMETER EvidenceTableId
    ID of the table supplying evidence records.

    .PARAMETER EvidenceFilter
    Optional filter applied to that table in the evidence viewer.

    .EXAMPLE
    $finding = New-PSIFinding -Title 'Review queue' -Status Warning -EvidenceTableId 'queue-table'
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string] $Id = '',
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter()][AllowEmptyString()][string] $Category = '',
        [Parameter()][AllowEmptyString()][string] $Description = '',
        [Parameter()][AllowEmptyString()][string] $AffectedObject = '',
        [Parameter()][AllowEmptyString()][string] $Impact = '',
        [Parameter()][AllowEmptyString()][string] $Recommendation = '',
        [Parameter()][AllowEmptyString()][string] $RuleId = '',
        [Parameter()][AllowEmptyString()][string] $Source = '',
        [Parameter()][AllowEmptyString()][string] $EvidenceTableId = '',
        [Parameter()][hashtable] $EvidenceFilter = @{},
        [Parameter()][string[]] $EvidenceColumns = @()
    )

    $CanonicalStatus = Resolve-PSIStatus -Status $Status
    $Definition = Resolve-PSIEvidenceDefinition -TableId $EvidenceTableId -Filter $EvidenceFilter -EvidenceColumns $EvidenceColumns -ExportColumns $EvidenceColumns -UseVisibleColumns
    if ($null -ne $Definition) { $EvidenceTableId = [string] $Definition.tableId }

    [pscustomobject]@{
        Id              = ConvertTo-PSIFindingId -Id $Id
        Title           = $Title
        Status          = $CanonicalStatus
        Category        = $Category
        Description     = $Description
        AffectedObject  = $AffectedObject
        Impact          = $Impact
        Recommendation  = $Recommendation
        RuleId          = $RuleId
        Source          = $Source
        EvidenceTableId = $EvidenceTableId
        EvidenceFilter  = $EvidenceFilter
        EvidenceColumns = [string[]] $EvidenceColumns
    }
}
#endregion

#region Public/New-PSIRelationship.ps1
function New-PSIRelationship {
    <# .SYNOPSIS Define a directed or bidirectional resource relationship. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Relationship -Definition $Definition
}
#endregion

#region Public/New-PSIReport.ps1
function New-PSIReport {
    <#
    .SYNOPSIS
    Create a report object.

    .DESCRIPTION
    Creates the generic report container; no HTML is written until Export-PSIReport runs.

    .PARAMETER Title
    Report heading.

    .PARAMETER Subtitle
    Optional text below the heading.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme.

    .EXAMPLE
    $report = New-PSIReport -Title 'Service Health' -Theme Auto
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter()]
        [string] $Subtitle = '',

        [Parameter()]
        [ValidateSet('Light', 'Dark', 'Auto')]
        [string] $Theme = 'Light',

        [Parameter()]
        [ValidateSet('Report', 'Application')]
        [string] $Layout = 'Report',

        [Parameter()]
        [object[]] $NavigationGroups = @(),

        [Parameter()]
        [ValidateSet('Sidebar', 'FluentExplorer')]
        [string] $Navigation = 'Sidebar',

        [Parameter()]
        [ValidateSet('Comfortable', 'Compact')]
        [string] $Density = 'Comfortable'
    )

    if ($Layout -eq 'Report' -and $NavigationGroups.Count -gt 0) {
        throw 'NavigationGroups require -Layout Application.'
    }
    if ($Layout -eq 'Report' -and ($Navigation -ne 'Sidebar' -or $Density -ne 'Comfortable')) {
        throw 'Navigation and Density options require -Layout Application.'
    }

    $Report = [pscustomobject]@{
        Title        = $Title
        Subtitle     = $Subtitle
        Theme        = $Theme
        GeneratedOn  = Get-Date
        # From the command's own module (manifest). $script: scope is not reliable here:
        # provider report scripts invoked with & get their own script scope.
        ModuleVersion = [string] $MyInvocation.MyCommand.Module.Version
        Sections     = [System.Collections.Generic.List[object]]::new()
        Assessments  = [System.Collections.Generic.List[object]]::new()
        Findings     = [System.Collections.Generic.List[object]]::new()
    }
    if ($Layout -eq 'Application') {
        $Report | Add-Member -NotePropertyName Layout -NotePropertyValue $Layout
        $Report | Add-Member -NotePropertyName NavigationGroups -NotePropertyValue @($NavigationGroups)
        $Report | Add-Member -NotePropertyName Navigation -NotePropertyValue $Navigation
        $Report | Add-Member -NotePropertyName Density -NotePropertyValue $Density
        $Report | Add-Member -NotePropertyName Views -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
        $Report | Add-Member -NotePropertyName ActiveViewId -NotePropertyValue ''
    }
    $Report
}
#endregion

#region Public/New-PSIResource.ps1
function New-PSIResource {
    <# .SYNOPSIS Define a generic resource. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Resource -Definition $Definition
}
#endregion

#region Public/Set-PSIApplicationAssessment.ps1
function Set-PSIApplicationAssessment {
    <# .SYNOPSIS Attach an assessment to an Application report and resolve its linked posture. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name Layout -DefaultValue 'Report') -ne 'Application') { throw 'Assessment experience requires New-PSIReport -Layout Application.' }
        if ($null -eq $Report.PSObject.Properties['ApplicationModel']) { throw 'Set-PSIApplicationModel must run before Set-PSIApplicationAssessment.' }
        $Resolved = Resolve-PSIAssessmentPosture -Assessment $Assessment -Model $Report.ApplicationModel
        if ($null -eq $Report.PSObject.Properties['ApplicationAssessment']) { $Report | Add-Member -NotePropertyName ApplicationAssessment -NotePropertyValue $Resolved }
        else { $Report.ApplicationAssessment = $Resolved }
        $Report
    }
}
#endregion

#region Public/Set-PSIApplicationModel.ps1
function Set-PSIApplicationModel {
    <# .SYNOPSIS Attach a validated intelligence model to an application report. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][pscustomobject] $Model
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name Layout -DefaultValue 'Report') -ne 'Application') {
            throw 'An intelligence model requires New-PSIReport -Layout Application.'
        }
        [void] (Assert-PSIApplicationModel -Model $Model)
        if ($null -eq $Report.PSObject.Properties['ApplicationModel']) {
            $Report | Add-Member -NotePropertyName ApplicationModel -NotePropertyValue $Model
        }
        else { $Report.ApplicationModel = $Model }
        $Report
    }
}
#endregion

#region Providers/ActiveDirectory/CompleteOverview/Public/Invoke-PSIADCompleteOverview.ps1
function Invoke-PSIADCompleteOverview {
    <#
    .SYNOPSIS
        Generate the linked AD Domain Overview report set.
    .DESCRIPTION
        Uses one read-only DC snapshot and scoped directory inventory queries.
        Use -UseSampleData for a fictional, offline demonstration or -Domain for a live pilot.
    .EXAMPLE
        Invoke-PSIADCompleteOverview -UseSampleData -NoBrowser
    .EXAMPLE
        Invoke-PSIADCompleteOverview -Domain ad.example.test -CollectionProfile Full -OutputPath C:\Reports\PSInsightHTML -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [switch] $UseSampleData,
        [string] $Domain,
        [pscustomobject] $Snapshot,
        [hashtable] $CommandAdapter,
        [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $CollectionProfile = 'Full',
        [ValidateRange(1,50000)][int] $MaxObjects = 2000,
        [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
        [string] $OutputPath,
        [ValidateSet('DomainOverview','DCInventory','DCReadiness2022','DCReadiness2025','HealthEvidence','Health','Security','Compliance','DNS','Replication','SitesSubnets','GroupPolicy','OUs','Groups','Users','Computers')]
        [string[]] $Only = @(),
        [switch] $NoBrowser,
        [switch] $PassThru
    )
    & (Join-Path $script:ModuleRoot 'Examples/ActiveDirectory/Invoke-PSIADCompleteOverview.ps1') @PSBoundParameters
}
#endregion

#region Providers/ActiveDirectory/DNS/Public/New-PSIADDNSAssessment.ps1
function New-PSIADDNSAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory DNS assessment.

    .DESCRIPTION
    Builds the DNS server, resolver, zone, and forwarding sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER Rules
    Provider-specific assessment rules.

    .EXAMPLE
    New-PSIADDNSAssessment -UseSampleData -DNSServerCount 56 -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(50, 60)][int] $DNSServerCount = 56,
    [Parameter()][hashtable] $Rules = @{},
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27),
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/DNS/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

#region Providers/ActiveDirectory/GroupPolicy/Public/New-PSIADGroupPolicyAssessment.ps1
function New-PSIADGroupPolicyAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory Group Policy assessment.

    .DESCRIPTION
    Builds the Group Policy object and link sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .EXAMPLE
    New-PSIADGroupPolicyAssessment -UseSampleData -GpoCount 180 -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(100, 250)][int] $GpoCount = 180,
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27),
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/GroupPolicy/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

#region Providers/ActiveDirectory/Groups/Public/New-PSIADGroupAssessment.ps1
function New-PSIADGroupAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory Groups assessment.

    .DESCRIPTION
    Builds the group and membership sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER Thresholds
    Provider-specific assessment thresholds.

    .EXAMPLE
    New-PSIADGroupAssessment -UseSampleData -GroupCount 320 -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(250, 400)][int] $GroupCount = 320,
    [Parameter()][hashtable] $Thresholds = @{},
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27),
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/Groups/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

#region Providers/ActiveDirectory/Replication/Public/New-PSIADReplicationAssessment.ps1
function New-PSIADReplicationAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory Replication assessment.

    .DESCRIPTION
    Builds the replication relationship sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER Thresholds
    Provider-specific assessment thresholds.

    .EXAMPLE
    New-PSIADReplicationAssessment -UseSampleData -DomainControllerCount 56 -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(50, 60)][int] $DomainControllerCount = 56,
    [Parameter()][hashtable] $Thresholds = @{},
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27, 12, 0, 0),
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/Replication/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

#region Providers/ActiveDirectory/SitesSubnets/Public/New-PSIADSitesSubnetsAssessment.ps1
function New-PSIADSitesSubnetsAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory Sites and Subnets assessment.

    .DESCRIPTION
    Builds the site, subnet, and topology sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER Rules
    Provider-specific assessment rules.

    .EXAMPLE
    New-PSIADSitesSubnetsAssessment -UseSampleData -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][hashtable] $Rules = @{},
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/SitesSubnets/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

#region Providers/ActiveDirectory/UserInventory/Public/New-PSIADUserInventory.ps1
function New-PSIADUserInventory {
    <#
    .SYNOPSIS
    Create an Active Directory User Inventory assessment.

    .DESCRIPTION
    Builds the user inventory assessment from fictional sample data or a supplied workbook. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .PARAMETER WorkbookPath
    Supplied workbook path; mutually exclusive with UseSampleData.

    .PARAMETER InsightThresholds
    Configurable investigation age thresholds.

    .EXAMPLE
    New-PSIADUserInventory -UseSampleData -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateNotNullOrEmpty()][string] $WorkbookPath,
    [Parameter()][datetime] $AsOfDate = (Get-Date),
    [Parameter()][hashtable] $Thresholds = @{},
    [Parameter()][hashtable] $InsightThresholds = @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 },
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if ($UseSampleData -and -not [string]::IsNullOrWhiteSpace($WorkbookPath)) {
        throw 'UseSampleData and WorkbookPath are mutually exclusive.'
    }
    if (-not $UseSampleData -and [string]::IsNullOrWhiteSpace($WorkbookPath)) {
        throw 'Specify -UseSampleData or -WorkbookPath. Live collection is not implemented.'
    }
    if ($UseSampleData) {
        $SampleWorkbook = Join-Path -Path $script:ModuleRoot -ChildPath 'Examples/Data/Active_Directory_Enterprise_User_Inventory_5000.xlsx'
        if (-not (Test-Path -LiteralPath $SampleWorkbook -PathType Leaf)) {
            throw "The local sample workbook was not found: $SampleWorkbook"
        }
    }
    elseif (-not (Test-Path -LiteralPath $WorkbookPath -PathType Leaf)) {
        throw "The supplied workbook was not found: $WorkbookPath"
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/UserInventory/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
#endregion

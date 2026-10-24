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
                formats   = @(@(Get-Prop $P 'ExportFormats' @('Csv', 'Xlsx', 'Print')) | ForEach-Object { [string] $_ })
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

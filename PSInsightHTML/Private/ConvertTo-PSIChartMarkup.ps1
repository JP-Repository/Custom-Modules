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

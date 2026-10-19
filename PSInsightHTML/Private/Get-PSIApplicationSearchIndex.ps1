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

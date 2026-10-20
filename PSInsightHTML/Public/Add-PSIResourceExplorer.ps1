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

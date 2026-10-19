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

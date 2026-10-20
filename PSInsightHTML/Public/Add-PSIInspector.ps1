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
            })
        }
        $Report | Add-Member -NotePropertyName Inspector -NotePropertyValue ([pscustomobject]@{ Id=$Id; Title=$Title; Items=$Normalized.ToArray() })
        $Report
    }
}

function Get-PSIADControlMappings {
    <# .SYNOPSIS Read the provider-owned, versioned selected control mapping. #>
    [CmdletBinding()]
    param([string] $FrameworkId='Microsoft-WindowsServer2025-DC', [switch] $All)
    $Registry=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'FrameworkRegistry.psd1')
    if ($All) { return @($Registry.Frameworks | ForEach-Object { Get-PSIADControlMappings -FrameworkId $_.Id }) }
    $Entry=@($Registry.Frameworks | Where-Object Id -eq $FrameworkId)
    if ($Entry.Count -ne 1) { throw "Unknown compliance framework '$FrameworkId'." }
    $Pack=Import-PowerShellDataFile (Join-Path $PSScriptRoot $Entry[0].Path)
    if (-not $Pack.Framework -or -not $Pack.FrameworkVersion -or -not $Pack.Controls) { throw 'Invalid AD selected control mapping pack.' }
    if ($Pack.FrameworkId -ne $FrameworkId -or $Pack.EvaluationMode -notin @('CurrentState','FutureTarget','ContextOnly')) { throw 'Invalid compliance framework identity or evaluation mode.' }
    $Seen=@{}
    foreach ($Control in @($Pack.Controls)) {
        foreach ($Required in @('ControlId','ControlTitle','ControlDescription','SourceRuleIds','EvidenceRequirements','Applicability','MappingType','MappingConfidence','Notes','Reference')) {
            if (-not $Control[$Required]) { throw "Control mapping is missing $Required." }
        }
        if ($Control.MappingType -notin @('Direct','Partial','Supporting')) { throw "Unsupported mapping type '$($Control.MappingType)'." }
        $MappingId=if ($Control.MappingId) { [string]$Control.MappingId } else { [string]$Control.ControlId }
        if ($Seen.ContainsKey($MappingId)) { throw "Duplicate mapping ID '$MappingId'." }
        $Seen[$MappingId]=$true
    }
    $Pack
}

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

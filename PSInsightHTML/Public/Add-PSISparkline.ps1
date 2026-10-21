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

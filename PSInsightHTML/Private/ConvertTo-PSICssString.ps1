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

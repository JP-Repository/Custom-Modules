function Add-PSIEmptyState {
    <# .SYNOPSIS Add a compact explanation for unavailable or empty content. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Explanation,
        [string] $Icon = 'Document',
        [string] $ActionLabel = '',
        [ValidatePattern('^$|^[A-Za-z][A-Za-z0-9_-]*$')][string] $TargetView = ''
    )
    process {
        [void] (Get-PSIIcon -Name $Icon -Strict)
        if ([bool]$ActionLabel -ne [bool]$TargetView) {
            throw 'Empty-state ActionLabel and TargetView must be supplied together.'
        }
        Add-PSIComponentToLastRow -Report $Report -Type 'EmptyState' -Properties @{
            Title=$Title; Explanation=$Explanation; Icon=$Icon
            ActionLabel=$ActionLabel; TargetView=$TargetView
        }
    }
}

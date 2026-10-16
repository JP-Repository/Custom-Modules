function Get-PSIExportToolbar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Table', 'Evidence', 'Report')]
        [string] $Scope,

        [Parameter()]
        [string[]] $Formats = @('Csv', 'Xlsx', 'Print'),

        [Parameter()]
        [switch] $UseFluentIcons
    )

    $Label = if ($Scope -eq 'Report') { 'Export report' } else { 'Export' }
    $Items = [System.Text.StringBuilder]::new()
    foreach ($Format in @('Csv', 'Xlsx', 'Print')) {
        if ($Format -notin $Formats) { continue }
        $Name = switch ($Format) { 'Csv' { 'CSV' } 'Xlsx' { 'Excel (.xlsx)' } 'Print' { 'Print / PDF' } }
        $Icon = if ($UseFluentIcons) { 'Document' } else { switch ($Format) { 'Csv' { 'file' } 'Xlsx' { 'database' } 'Print' { 'print' } } }
        $IconSize = if ($UseFluentIcons) { 18 } else { 16 }
        [void] $Items.AppendLine("<button type=`"button`" role=`"menuitem`" tabindex=`"-1`" data-psi-export-format=`"$($Format.ToLowerInvariant())`">$(Get-PSIIcon -Name $Icon -Size $IconSize)<span>$Name</span></button>")
    }
    if ($Items.Length -eq 0) { return '' }
    $TriggerIcon = if ($UseFluentIcons) { 'Export' } else { 'file' }
    $ChevronIcon = if ($UseFluentIcons) { 'AppChevron' } else { 'chevron' }
    $TriggerSize = if ($UseFluentIcons) { 19 } else { 16 }
    @"
<div class="psi-export-toolbar" data-psi-export-toolbar data-psi-export-scope="$($Scope.ToLowerInvariant())">
  <button type="button" class="psi-export-trigger" data-psi-export-trigger aria-haspopup="menu" aria-expanded="false" aria-label="$Label options">$(Get-PSIIcon -Name $TriggerIcon -Size $TriggerSize)<span>$Label</span>$(Get-PSIIcon -Name $ChevronIcon -Size 14)</button>
  <div class="psi-export-menu" role="menu" aria-label="$Label formats" data-psi-export-menu hidden>
    $($Items.ToString().TrimEnd())
  </div>
  <span class="psi-export-feedback" data-psi-export-feedback role="status" aria-live="polite"></span>
</div>
"@
}

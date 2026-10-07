function Get-PSIExportToolbar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Table', 'Evidence', 'Report')]
        [string] $Scope,

        [Parameter()]
        [string[]] $Formats = @('Csv', 'Xlsx', 'Print')
    )

    $Label = if ($Scope -eq 'Report') { 'Export report' } else { 'Export' }
    $Items = [System.Text.StringBuilder]::new()
    foreach ($Format in @('Csv', 'Xlsx', 'Print')) {
        if ($Format -notin $Formats) { continue }
        $Name = switch ($Format) { 'Csv' { 'CSV' } 'Xlsx' { 'Excel (.xlsx)' } 'Print' { 'Print / PDF' } }
        $Icon = switch ($Format) { 'Csv' { 'file' } 'Xlsx' { 'database' } 'Print' { 'print' } }
        [void] $Items.AppendLine("<button type=`"button`" role=`"menuitem`" tabindex=`"-1`" data-psi-export-format=`"$($Format.ToLowerInvariant())`">$(Get-PSIIcon -Name $Icon -Size 16)<span>$Name</span></button>")
    }
    if ($Items.Length -eq 0) { return '' }
    @"
<div class="psi-export-toolbar" data-psi-export-toolbar data-psi-export-scope="$($Scope.ToLowerInvariant())">
  <button type="button" class="psi-export-trigger" data-psi-export-trigger aria-haspopup="menu" aria-expanded="false" aria-label="$Label options">$(Get-PSIIcon -Name 'file' -Size 16)<span>$Label</span>$(Get-PSIIcon -Name 'chevron' -Size 14)</button>
  <div class="psi-export-menu" role="menu" aria-label="$Label formats" data-psi-export-menu hidden>
    $($Items.ToString().TrimEnd())
  </div>
  <span class="psi-export-feedback" data-psi-export-feedback role="status" aria-live="polite"></span>
</div>
"@
}

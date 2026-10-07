function Export-PSIEmailPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][switch] $Open
    )

    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $ParentDirectory = Split-Path -Path $ResolvedPath -Parent
    if (-not (Test-Path -LiteralPath $ParentDirectory -PathType Container)) {
        [void] (New-Item -Path $ParentDirectory -ItemType Directory -Force -ErrorAction Stop)
    }
    $Html = ConvertTo-PSIEmailMarkup -Email $Email -Preview
    [System.IO.File]::WriteAllText($ResolvedPath, $Html, [System.Text.UTF8Encoding]::new($false))
    $File = Get-Item -LiteralPath $ResolvedPath -ErrorAction Stop

    if ($Open) {
        try {
            if ($env:OS -eq 'Windows_NT') {
                Start-Process -FilePath $File.FullName -ErrorAction Stop
            }
            elseif ($PSVersionTable.PSEdition -eq 'Core' -and
                [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
                & /usr/bin/open $File.FullName
                if ($LASTEXITCODE -ne 0) { throw "open exited with code $LASTEXITCODE." }
            }
            elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) {
                Start-Process -FilePath 'xdg-open' -ArgumentList @($File.FullName) -ErrorAction Stop
            }
            else { Write-Warning 'No supported preview opener was detected.' }
        }
        catch { Write-Warning "The preview was written but could not be opened: $($_.Exception.Message)" }
    }
    $File
}

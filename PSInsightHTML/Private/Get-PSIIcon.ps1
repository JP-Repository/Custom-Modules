function Get-PSIIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [ValidateRange(12, 96)]
        [int] $Size = 20
    )

    $IconPaths = @{
        'dashboard' = '<rect x="3" y="3" width="8" height="8" rx="1"/><rect x="13" y="3" width="8" height="5" rx="1"/><rect x="13" y="10" width="8" height="11" rx="1"/><rect x="3" y="13" width="8" height="8" rx="1"/>'
        'server' = '<rect x="3" y="4" width="18" height="7" rx="2"/><rect x="3" y="13" width="18" height="7" rx="2"/><path d="M7 7.5h.01M7 16.5h.01M11 7.5h6M11 16.5h6"/>'
        'domain' = '<path d="M3 21h18M5 21V7l7-4 7 4v14M9 21v-5h6v5M8 9h.01M12 9h.01M16 9h.01M8 12h.01M12 12h.01M16 12h.01"/>'
        'replication' = '<path d="M20 7h-6V3M4 17h6v4"/><path d="M5.6 9a7 7 0 0 1 11.5-2L20 9M4 15l2.9 2a7 7 0 0 0 11.5-2"/>'
        'security' = '<path d="M12 22s8-4 8-11V5l-8-3-8 3v6c0 7 8 11 8 11Z"/><path d="m9 12 2 2 4-4"/>'
        'certificate' = '<path d="M12 15a6 6 0 1 0 0-12 6 6 0 0 0 0 12Z"/><path d="m8 14-1 8 5-3 5 3-1-8"/>'
        'users' = '<path d="M16 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM20 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>'
        'cloud' = '<path d="M20 16.2A4.5 4.5 0 0 0 18 7.5h-1.3A6 6 0 0 0 5 9a4 4 0 0 0 0 8h14"/>'
        'database' = '<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>'
        'network' = '<rect x="9" y="3" width="6" height="5" rx="1"/><rect x="2" y="16" width="6" height="5" rx="1"/><rect x="16" y="16" width="6" height="5" rx="1"/><path d="M12 8v4M5 16v-4h14v4"/>'
        'warning' = '<path d="m10.3 3.9-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3.1l-8-14a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/>'
        'critical' = '<circle cx="12" cy="12" r="9"/><path d="m15 9-6 6M9 9l6 6"/>'
        'info' = '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>'
        'healthy' = '<circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/>'
        'settings' = '<circle cx="12" cy="12" r="3"/><path d="m19.4 15 .1.1 1.4 1.1-1.4 2.4-1.7-.7a8 8 0 0 1-1.7 1l-.3 1.8h-2.8l-.3-1.8a8 8 0 0 1-1.7-1l-1.7.7-1.4-2.4L7.3 15a8 8 0 0 1 0-2l-1.4-1.1 1.4-2.4 1.7.7a8 8 0 0 1 1.7-1l.3-1.8h2.8l.3 1.8a8 8 0 0 1 1.7 1l1.7-.7 1.4 2.4-1.4 1.1a8 8 0 0 1-.1 2Z" transform="translate(-1 -1)"/>'
        'search' = '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>'
        'arrow' = '<path d="M5 12h14M13 6l6 6-6 6"/>'
        'close' = '<path d="m18 6-12 12M6 6l12 12"/>'
        'theme/light' = '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'
        'theme/dark' = '<path d="M20.9 13A9 9 0 0 1 11 3.1 9 9 0 1 0 20.9 13Z"/>'
        'file' = '<path d="M6 2h8l5 5v15H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Z"/><path d="M14 2v6h5M8 13h8M8 17h8"/>'
        'print' = '<path d="M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 15h12v7H6zM18 12h.01"/>'
        'chevron' = '<path d="m6 9 6 6 6-6"/>'
    }

    if (-not $IconPaths.ContainsKey($Name)) {
        $Name = 'dashboard'
    }

    '<svg class="psi-icon" width="{0}" height="{0}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">{1}</svg>' -f $Size, $IconPaths[$Name]
}

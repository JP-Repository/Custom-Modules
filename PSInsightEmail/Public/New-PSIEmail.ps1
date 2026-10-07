function New-PSIEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter()][AllowEmptyString()][string] $Subtitle = '',
        [Parameter()][AllowEmptyString()][string] $Preheader = '',
        [Parameter()][ValidateSet('Operational', 'Health', 'Threshold')][string] $Template = 'Operational',
        [Parameter()][AllowEmptyString()][string] $BrandName = '',
        [Parameter()][AllowEmptyString()][string] $LogoPath = '',
        [Parameter()][AllowEmptyString()][string] $LogoContentId = '',
        [Parameter()][AllowEmptyString()][string] $EnvironmentLabel = '',
        [Parameter()][ValidateSet('Neutral', 'Informational', 'Healthy', 'Warning', 'Critical')][string] $EnvironmentStatus = 'Neutral',
        [Parameter()][AllowEmptyString()][string] $SourceLabel = '',
        [Parameter()][AllowEmptyString()][string] $FooterNote = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($LogoContentId)) {
        $null = Assert-PSIEmailContentId -ContentId $LogoContentId
    }

    [pscustomobject]@{
        PSTypeName    = 'PSInsightEmail.Email'
        Title         = $Title
        Subtitle      = $Subtitle
        Preheader     = $Preheader
        Template      = $Template
        BrandName     = $BrandName
        LogoPath      = $LogoPath
        LogoContentId = $LogoContentId
        EnvironmentLabel = $EnvironmentLabel
        EnvironmentStatus = $EnvironmentStatus
        SourceLabel   = $SourceLabel
        FooterNote    = $FooterNote
        GeneratedOn   = Get-Date
        ModuleVersion = $script:PSIEmailModuleVersion
        Sections      = [System.Collections.Generic.List[object]]::new()
        Attachments   = [System.Collections.Generic.List[object]]::new()
        InlineResources = [System.Collections.Generic.List[object]]::new()
    }
}

function New-PSIAssessment {
    <#
    .SYNOPSIS
    Create an assessment object.

    .DESCRIPTION
    Creates an independently composed assessment with sections and findings.

    .PARAMETER Id
    Stable assessment identifier; generated when omitted.

    .PARAMETER Name
    Display name used by the report overview and navigation.

    .PARAMETER Provider
    Source family label; it does not trigger collection.

    .EXAMPLE
    $assessment = New-PSIAssessment -Id 'sample' -Name 'Sample Service' -Provider 'Example'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Id,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [string] $Title = '',

        [Parameter()]
        [string] $Provider = '',

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [hashtable] $Metadata = @{}
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        $Id = 'psi-assessment-' + [guid]::NewGuid().ToString('N')
    }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $Name }

    $Assessment = [pscustomobject]@{
        Id          = $Id
        Name        = $Name
        Title       = $Title
        Provider    = $Provider
        Description = $Description
        Metadata    = $Metadata
        Sections    = [System.Collections.Generic.List[object]]::new()
        Findings    = [System.Collections.Generic.List[object]]::new()
    }
    $Assessment.PSObject.TypeNames.Insert(0, 'PSInsightHTML.Assessment')
    $Assessment
}

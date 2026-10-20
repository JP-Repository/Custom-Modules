#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [string] $OutputPath = (Join-Path $PSScriptRoot 'FluentExplorer-Benchmark.html')
)

$ModuleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

# All names, measurements and findings below are fictional presentation data.
$Services = @(
    [pscustomobject]@{ Name='Atlas API'; Region='North'; Status='Healthy'; Availability='99.98%'; Owner='Platform' }
    [pscustomobject]@{ Name='Beacon Queue'; Region='West'; Status='Warning'; Availability='98.74%'; Owner='Messaging' }
    [pscustomobject]@{ Name='Cedar Gateway'; Region='South'; Status='Healthy'; Availability='99.95%'; Owner='Network' }
    [pscustomobject]@{ Name='Delta Index'; Region='East'; Status='Critical'; Availability='96.30%'; Owner='Search' }
    [pscustomobject]@{ Name='Echo Metrics'; Region='North'; Status='Healthy'; Availability='99.91%'; Owner='Observability' }
    [pscustomobject]@{ Name='Fjord Archive'; Region='West'; Status='Unknown'; Availability=$null; Owner='Storage' }
)
$StatusCounts = @(
    [pscustomobject]@{ Status='Healthy'; Count=3 }
    [pscustomobject]@{ Status='Warning'; Count=1 }
    [pscustomobject]@{ Status='Critical'; Count=1 }
    [pscustomobject]@{ Status='Unknown'; Count=1 }
)

$Report = New-PSIReport -Title 'Infrastructure Explorer' -Subtitle 'Fictional service operations snapshot' `
    -Layout Application -Navigation FluentExplorer -Density Compact -Theme $Theme

$Report | Add-PSIView -Id overview -Title Overview -Subtitle 'Fictional portfolio health' -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Portfolio pulse' | Add-PSIRow |
    Add-PSIKPI -Title Services -Value 6 -Subtitle 'Sample services' -Status Info -Icon ResourceServer -Span 3 |
    Add-PSIKPI -Title Healthy -Value 3 -Subtitle 'Operating normally' -Status Healthy -Icon SeveritySuccess -Span 3 |
    Add-PSIKPI -Title Attention -Value 2 -Subtitle 'Warning or critical' -Status Warning -Icon SeverityWarning -Span 3 |
    Add-PSIKPI -Title Availability -Value '99.14%' -Subtitle 'Fictional aggregate' -Status Info -Icon NavigationHome -Span 3 | Out-Null
$Report | Add-PSISection -Title 'Status distribution' | Add-PSIRow |
    Add-PSIChart -Title 'Services by status' -ChartType Bar -Data $StatusCounts -CategoryProperty Status -ValueProperty Count -ShowLabels $true | Out-Null

$Report | Add-PSIView -Id services -Title Services -Subtitle 'Searchable fictional inventory' -Icon ResourceServer |
    Add-PSISection -Title 'Service inventory' | Add-PSIRow |
    Add-PSITable -Title 'Service health' -Data $Services -Columns @('Name','Region','Status','Availability','Owner') -PageSize 5 | Out-Null

$Report | Add-PSIView -Id notes -Title Notes -Subtitle 'Sample interpretation only' -Icon Document |
    Add-PSISection -Title 'About this snapshot' | Add-PSIRow |
    Add-PSIText -Text 'This standalone benchmark contains synthetic services only. No live infrastructure was queried.' | Out-Null

Export-PSIReport -Report $Report -Path $OutputPath | Out-Null
Write-Output (Resolve-Path -LiteralPath $OutputPath).Path

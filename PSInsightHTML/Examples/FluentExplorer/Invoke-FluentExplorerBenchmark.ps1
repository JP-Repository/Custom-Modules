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

$Nodes = @(
    @{ Id='domain'; Label='root.cabot-corp.com'; Type='Domain'; Icon='ResourceServer'; Status='Healthy'; Count=6; Target='overview' }
    @{ Id='sites'; Label='Sites'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Healthy'; Count=3 }
    @{ Id='hq'; Label='HQ'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Healthy'; Count=2 }
    @{ Id='dc01'; Label='CABOT-DC01'; Type='Domain Controller'; ParentId='hq'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='dc02'; Label='CABOT-DC02'; Type='Domain Controller'; ParentId='hq'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='branch1'; Label='Branch1'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Warning'; Count=2 }
    @{ Id='dc03'; Label='CABOT-DC03'; Type='Domain Controller'; ParentId='branch1'; Icon='ResourceServer'; Status='Warning'; Target='overview' }
    @{ Id='dc04'; Label='CABOT-DC04'; Type='Domain Controller'; ParentId='branch1'; Icon='ResourceServer'; Status='Critical'; Target='overview' }
    @{ Id='branch2'; Label='Branch2'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Healthy'; Count=2 }
    @{ Id='dc05'; Label='CABOT-DC05'; Type='Domain Controller'; ParentId='branch2'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='dc06'; Label='CABOT-DC06'; Type='Domain Controller'; ParentId='branch2'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='ous'; Label='OUs'; Type='Category'; ParentId='domain'; Icon='Document'; Status='Unknown' }
    @{ Id='groups'; Label='Groups'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='users'; Label='Users'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='computers'; Label='Computers'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='serviceaccounts'; Label='Service Accounts'; Type='Category'; ParentId='domain'; Icon='SecurityShield'; Status='Unknown' }
    @{ Id='gpos'; Label='GPOs'; Type='Category'; ParentId='domain'; Icon='Rules'; Status='Unknown' }
    @{ Id='dns'; Label='DNS'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
    @{ Id='certificates'; Label='Certificates'; Type='Category'; ParentId='domain'; Icon='Document'; Status='Unknown' }
    @{ Id='trusts'; Label='Trusts'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
    @{ Id='adconnect'; Label='AD Connect'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
)
$Report | Add-PSIResourceExplorer -Id infrastructure -Title 'Resources' -Nodes $Nodes -SelectedId dc01 | Out-Null

$DcSamples = @(
    @{ Id='dc01'; Name='CABOT-DC01'; Site='HQ'; IPv4='10.10.1.10'; Status='Healthy'; Uptime='42 days'; Roles='AD DS, DNS, GC'; Fsmo='PDC Emulator'; OS='Windows Server 2022' }
    @{ Id='dc02'; Name='CABOT-DC02'; Site='HQ'; IPv4='10.10.1.11'; Status='Healthy'; Uptime='38 days'; Roles='AD DS, DNS, GC'; Fsmo='RID Master'; OS='Windows Server 2022' }
    @{ Id='dc03'; Name='CABOT-DC03'; Site='Branch1'; IPv4='10.10.2.10'; Status='Warning'; Uptime='97 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2022' }
    @{ Id='dc04'; Name='CABOT-DC04'; Site='Branch1'; IPv4='10.10.2.11'; Status='Critical'; Uptime='131 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2019' }
    @{ Id='dc05'; Name='CABOT-DC05'; Site='Branch2'; IPv4='10.10.3.10'; Status='Healthy'; Uptime='31 days'; Roles='AD DS, DNS, GC'; Fsmo='Infrastructure Master'; OS='Windows Server 2022' }
    @{ Id='dc06'; Name='CABOT-DC06'; Site='Branch2'; IPv4='10.10.3.11'; Status='Healthy'; Uptime='29 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2022' }
)
$InspectorItems = @(
    foreach ($Dc in $DcSamples) {
        $Attention = if ($Dc.Status -eq 'Critical') { 'Critical synthetic service observation' }
            elseif ($Dc.Status -eq 'Warning') { 'Warning synthetic replication observation' }
            else { 'Routine owner record review' }
        @{
            Id='inspector-' + $Dc.Id; ResourceId=$Dc.Id
            Title=$Dc.Name + '.root.cabot-corp.com'; Subtitle='Synthetic domain controller'; Status=$Dc.Status
            Metadata=[ordered]@{ OS=$Dc.OS; Site=$Dc.Site; IPv4=$Dc.IPv4; Uptime=$Dc.Uptime }
            Properties=[ordered]@{
                OS=$Dc.OS; Domain='root.cabot-corp.com'; Site=$Dc.Site; IPv4=$Dc.IPv4
                Roles=$Dc.Roles; FSMO=$Dc.Fsmo; Uptime=$Dc.Uptime
                'Functional Level'='Windows Server 2016'; Hardware='Fictional virtual machine'
            }
            Sections=@(
                @{ Id='Evidence'; Title='Evidence'; Blocks=@(
                    @{ Title='Heartbeat sample'; Text='Fictional monitor reference: heartbeat-' + $Dc.Id; Status=$Dc.Status },
                    @{ Title='Directory sample'; Text='Fictional directory reference: directory-' + $Dc.Id; Status='Informational' }
                ) },
                @{ Id='Findings'; Title='Findings'; Blocks=@(
                    @{ Title=$Attention; Text='Presentation-only sample finding for ' + $Dc.Name + '.'; Status=$Dc.Status },
                    @{ Title='Inventory metadata review'; Text='Confirm the fictional owner and site labels during a sample review.'; Status='Informational' }
                ) },
                @{ Id='Recommendations'; Title='Recommendations'; Blocks=@(
                    @{ Title='Review sample observation'; Text='Inspect the supplied fictional evidence reference. No change is executed.' },
                    @{ Title='Confirm inventory context'; Text='Validate the synthetic site, OS and ownership labels in the source dataset.' }
                ) },
                @{ Id='Related'; Title='Related Resources'; Blocks=@(
                    @{ Title='Domain'; Text='root.cabot-corp.com'; ResourceId='domain'; ActionLabel='Open domain' }
                ) }
            )
        }
    }
)
$Report | Add-PSIInspector -Id dc-context -Title 'Context Inspector' -Items $InspectorItems | Out-Null

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

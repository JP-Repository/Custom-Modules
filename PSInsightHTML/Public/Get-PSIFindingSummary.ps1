function Get-PSIFindingSummary {
    <#
    .SYNOPSIS
    Summarize finding severities.

    .DESCRIPTION
    Counts structured findings using the canonical status vocabulary.

    .PARAMETER Findings
    Finding objects to count.

    .EXAMPLE
    $summary = Get-PSIFindingSummary -Findings $report.Findings
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Findings = @()
    )

    begin {
        $Counts = [ordered]@{
            Total = 0; Critical = 0; Warning = 0; Healthy = 0
            Informational = 0; Neutral = 0; Unknown = 0; NotChecked = 0
        }
    }
    process {
        foreach ($Finding in $Findings) {
            if ($null -eq $Finding) { throw 'A Finding cannot be null.' }
            $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
            $Counts[$Status]++
            $Counts.Total++
        }
    }
    end { [pscustomobject] $Counts }
}

function Resolve-PSIADGroupThresholds {
    [CmdletBinding()]
    param([Parameter()][hashtable] $Thresholds = @{})

    $Resolved = [ordered]@{ LargeGroupMemberThreshold = 500; EmptyGroupMaximumMembers = 0 }
    foreach ($Name in $Thresholds.Keys) {
        if ($Name -notin @($Resolved.Keys)) { throw "Unsupported group assessment threshold '$Name'." }
        $Parsed = 0
        if (-not [int]::TryParse([string] $Thresholds[$Name], [ref] $Parsed) -or $Parsed -lt 0) {
            throw "Group assessment threshold '$Name' must be a non-negative whole number."
        }
        $Resolved[$Name] = $Parsed
    }
    if ($Resolved.LargeGroupMemberThreshold -lt 1 -or $Resolved.EmptyGroupMaximumMembers -ge $Resolved.LargeGroupMemberThreshold) {
        throw 'LargeGroupMemberThreshold must be positive and greater than EmptyGroupMaximumMembers.'
    }
    return $Resolved
}

function New-PSIADGroupSampleData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(250, 400)]
        [int] $GroupCount = 320,

        [Parameter()]
        [hashtable] $Thresholds = @{},

        [Parameter()]
        [datetime] $AsOfDate = [datetime]::new(2026, 9, 27)
    )

    $Rules = Resolve-PSIADGroupThresholds -Thresholds $Thresholds
    $Groups = [System.Collections.Generic.List[object]]::new()
    $Memberships = [System.Collections.Generic.List[object]]::new()
    $Nested = [System.Collections.Generic.List[object]]::new()
    $Regions = @('North', 'South', 'East', 'West', 'Central')
    $Purposes = @('Application', 'Platform', 'Operations', 'Collaboration', 'Service', 'Reporting')
    $Scopes = @('Global', 'Universal', 'Domain Local')
    $Names = [System.Collections.Generic.List[string]]::new()
    for ($Index = 1; $Index -le $GroupCount; $Index++) {
        $Names.Add(('GRP-{0}-{1}-{2:D3}' -f $Regions[($Index - 1) % $Regions.Count], $Purposes[($Index - 1) % $Purposes.Count], $Index))
    }

    for ($Index = 1; $Index -le $GroupCount; $Index++) {
        $Name = $Names[$Index - 1]
        $Scope = $Scopes[($Index - 1) % $Scopes.Count]
        $Category = if ($Index % 4 -eq 0) { 'Distribution' } else { 'Security' }
        $Description = if ($Index % 7 -eq 0) { $null }
            elseif ($Index % 23 -eq 0) { 'Fictional group used to demonstrate a longer ownership and access-purpose description that should remain readable in a responsive table and evidence view.' }
            else { 'Fictional {0} access group for the {1} region.' -f $Purposes[($Index - 1) % $Purposes.Count].ToLowerInvariant(), $Regions[($Index - 1) % $Regions.Count] }
        $ManagedBy = if ($Index % 9 -eq 0) { $null } else { 'Sample Owner {0:D3}' -f (($Index % 42) + 1) }
        $UserCount = if ($Index % 19 -eq 0) { 0 }
            elseif ($Index -in @(40, 160, 280)) { 520 + ($Index % 3) * 45 }
            else { 6 + ($Index % 13) }
        $DesiredGroupMemberCount = if ($UserCount -eq 0 -or $Index -ge $GroupCount -or $Index % 4 -ne 0) { 0 }
            elseif ($Index % 12 -eq 0) { [math]::Min(3, $GroupCount - $Index) }
            else { 1 }
        $ChildIndices = [System.Collections.Generic.List[int]]::new()
        for ($Candidate = $Index + 1; $Candidate -le $GroupCount -and $ChildIndices.Count -lt $DesiredGroupMemberCount; $Candidate++) {
            $CandidateScope = $Scopes[($Candidate - 1) % $Scopes.Count]
            if ($Scope -eq 'Global' -and $CandidateScope -ne 'Global') { continue }
            if ($Scope -eq 'Universal' -and $CandidateScope -eq 'Domain Local') { continue }
            $ChildIndices.Add($Candidate)
        }
        $GroupMemberCount = $ChildIndices.Count
        $DisabledCount = 0
        for ($MemberIndex = 1; $MemberIndex -le $UserCount; $MemberIndex++) {
            $UserNumber = (($Index * 37 + $MemberIndex * 101) % 2400) + 1
            $MemberName = 'Sample User {0:D4}' -f $UserNumber
            $MemberSam = 'sample.user{0:D4}' -f $UserNumber
            $Enabled = if ($UserNumber % 11 -eq 0) { 'No' } else { 'Yes' }
            if ($Enabled -eq 'No') { $DisabledCount++ }
            $Memberships.Add([pscustomobject]@{
                GroupName = $Name
                GroupSamAccountName = $Name
                MemberName = $MemberName
                MemberSamAccountName = $MemberSam
                MemberType = 'User'
                MemberEnabled = $Enabled
                MemberDistinguishedName = "CN=$MemberName,OU=Sample Users,DC=corp,DC=example,DC=invalid"
            })
        }
        foreach ($ChildIndex in $ChildIndices) {
            $ChildName = $Names[$ChildIndex - 1]
            $ChildScope = $Scopes[($ChildIndex - 1) % $Scopes.Count]
            $Memberships.Add([pscustomobject]@{
                GroupName = $Name
                GroupSamAccountName = $Name
                MemberName = $ChildName
                MemberSamAccountName = $ChildName
                MemberType = 'Group'
                MemberEnabled = 'Not applicable'
                MemberDistinguishedName = "CN=$ChildName,OU=Sample Groups,DC=corp,DC=example,DC=invalid"
            })
            $Nested.Add([pscustomobject]@{
                ParentGroup = $Name
                ChildGroup = $ChildName
                ParentScope = $Scope
                ChildScope = $ChildScope
                RelationshipDepth = 1
                RelationshipType = 'Direct'
            })
        }

        $MemberCount = $UserCount + $GroupMemberCount
        $Bucket = if ($MemberCount -eq 0) { '0' }
            elseif ($MemberCount -le 10) { '1-10' }
            elseif ($MemberCount -le 50) { '11-50' }
            elseif ($MemberCount -le 100) { '51-100' }
            elseif ($MemberCount -lt 500) { '101-499' }
            else { '500+' }
        $CreatedDate = $AsOfDate.Date.AddYears(-7).AddDays($Index * 5)
        $ModifiedDate = $CreatedDate.AddDays(60 + (($Index * 17) % 730))
        if ($ModifiedDate -gt $AsOfDate) { $ModifiedDate = $AsOfDate.Date }
        $Groups.Add([pscustomobject]@{
            GroupName = $Name
            SamAccountName = $Name
            DistinguishedName = "CN=$Name,OU=Sample Groups,DC=corp,DC=example,DC=invalid"
            GroupCategory = $Category
            GroupScope = $Scope
            Description = $Description
            ManagedBy = $ManagedBy
            MemberCount = $MemberCount
            DirectUserCount = $UserCount
            DirectGroupCount = $GroupMemberCount
            DisabledUserCount = $DisabledCount
            NestedGroupCount = $GroupMemberCount
            Created = $CreatedDate.ToString('yyyy-MM-dd')
            Modified = $ModifiedDate.ToString('yyyy-MM-dd')
            MemberCountBucket = $Bucket
            HasOwner = if ($null -eq $ManagedBy) { 'No' } else { 'Yes' }
            HasDisabledMembers = if ($DisabledCount -gt 0) { 'Yes' } else { 'No' }
        })
    }

    [pscustomobject]@{
        Source = 'Deterministic fictional AD group sample; no live directory connection.'
        AsOfDate = $AsOfDate
        Thresholds = $Rules
        GroupInventory = $Groups.ToArray()
        GroupMemberships = $Memberships.ToArray()
        NestedGroupRelationships = $Nested.ToArray()
    }
}

function Get-PSIADGroupDistribution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]] $Data,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $Property
    )
    @($Data | Group-Object -Property $Property | Sort-Object -Property Name | ForEach-Object {
        [pscustomobject]@{ Category = [string] $_.Name; Count = [int] $_.Count }
    })
}

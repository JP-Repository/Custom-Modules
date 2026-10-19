function Get-PSIADPrivilegedFacts {
    <# .SYNOPSIS Read domain and applicable forest-root privileged membership without judging it. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Domain,[Parameter(Mandatory)][string] $DomainSid,[Parameter(Mandatory)][string] $ForestRoot)
    $Groups=[System.Collections.Generic.List[object]]::new(); $Members=[System.Collections.Generic.List[object]]::new(); $Stamp=Get-Date
    $Definitions=@(@{Name='Domain Admins';Sid="$DomainSid-512";Server=$Domain;Scope='AssessedDomain'},@{Name='Administrators';Sid='S-1-5-32-544';Server=$Domain;Scope='AssessedDomain'})
    if ($Domain -eq $ForestRoot) { $Definitions+=@(@{Name='Enterprise Admins';Sid="$DomainSid-519";Server=$Domain;Scope='ForestRoot'},@{Name='Schema Admins';Sid="$DomainSid-518";Server=$Domain;Scope='ForestRoot'}) }
    foreach ($Definition in $Definitions) {
        try {
            $Group=Get-ADGroup -Identity $Definition.Sid -Server $Definition.Server -ErrorAction Stop
            $Groups.Add([pscustomobject]@{ Group=$Definition.Name; SID=[string]$Group.SID; Domain=$Domain; Scope=$Definition.Scope; CollectionState='Collected'; SourceType='Directory'; Timestamp=$Stamp; ErrorClass='' })
            $Queue=New-Object 'System.Collections.Generic.Queue[object]'
            $Queue.Enqueue([pscustomobject]@{ Group=$Group; Path=@($Definition.Name); Seen=@([string]$Group.SID) })
            while ($Queue.Count -gt 0) {
                $Node=$Queue.Dequeue()
                try { $Direct=@(Get-ADGroupMember -Identity $Node.Group.DistinguishedName -Server $Definition.Server -ErrorAction Stop) }
                catch {
                    $Members.Add([pscustomobject]@{ Group=$Definition.Name; SourceGroup=[string]$Node.Group.Name; Principal=[string]$Node.Group.DistinguishedName; PrincipalType='Unresolved'; SID=$null; Direct=($Node.Path.Count -eq 1); NestedPath=@($Node.Path); ResolutionState='Failed'; CollectionState='Partial'; ErrorClass=$_.Exception.GetType().Name; Domain=$Domain; Scope=$Definition.Scope; Timestamp=$Stamp })
                    continue
                }
                foreach ($Member in $Direct) {
                    $MemberSid=[string]$Member.SID; $IsGroup=[string]$Member.objectClass -eq 'group'; $Path=@($Node.Path)+@([string]$Member.Name)
                    $Metadata=$null; $Resolution='Resolved'; $ErrorClass=''
                    if ([string]$Member.objectClass -eq 'user') {
                        try { $U=Get-ADUser -Identity $Member.DistinguishedName -Server $Definition.Server -Properties Enabled,PasswordLastSet,PasswordNeverExpires,LastLogonTimestamp,AccountExpirationDate,ServicePrincipalName,userAccountControl -ErrorAction Stop
                            $Last=$null; if ($U.LastLogonTimestamp) { $Last=[datetime]::FromFileTimeUtc([long]$U.LastLogonTimestamp) }
                            $Metadata=[pscustomobject]@{ Enabled=$U.Enabled; PasswordLastSet=$U.PasswordLastSet; PasswordNeverExpires=$U.PasswordNeverExpires; LastLogonTimestamp=$U.LastLogonTimestamp; LastLogonDate=$Last; AccountExpirationDate=$U.AccountExpirationDate; UserAccountControl=$U.userAccountControl; HasServicePrincipalName=(@($U.ServicePrincipalName).Count -gt 0) }
                        } catch { $Resolution='Partial'; $ErrorClass=$_.Exception.GetType().Name }
                    }
                    $Members.Add([pscustomobject]@{ Group=$Definition.Name; SourceGroup=[string]$Node.Group.Name; Principal=[string]$Member.Name; PrincipalType=[string]$Member.objectClass; SID=$MemberSid; Direct=($Node.Path.Count -eq 1); NestedPath=$Path; ResolutionState=$Resolution; CollectionState=if ($Resolution -eq 'Resolved') { 'Collected' } else { 'Partial' }; ErrorClass=$ErrorClass; Domain=$Domain; Scope=$Definition.Scope; Metadata=$Metadata; Timestamp=$Stamp })
                    if ($IsGroup -and $MemberSid -notin @($Node.Seen)) { $Queue.Enqueue([pscustomobject]@{ Group=$Member; Path=$Path; Seen=@($Node.Seen)+@($MemberSid) }) }
                }
            }
        } catch { $Groups.Add([pscustomobject]@{ Group=$Definition.Name; SID=$Definition.Sid; Domain=$Domain; Scope=$Definition.Scope; CollectionState='Failed'; SourceType='Directory'; Timestamp=$Stamp; ErrorClass=$_.Exception.GetType().Name }) }
    }
    $Krbtgt=$null
    try {
        $K=Get-ADUser -Identity 'krbtgt' -Server $Domain -Properties Enabled,PasswordLastSet,LastLogonTimestamp,PasswordNeverExpires -ErrorAction Stop
        $Krbtgt=[pscustomobject]@{ Domain=$Domain; Enabled=$K.Enabled; PasswordLastSet=$K.PasswordLastSet; PasswordNeverExpires=$K.PasswordNeverExpires; LastLogonTimestamp=$K.LastLogonTimestamp; CollectionState='Collected'; SourceType='Directory'; Timestamp=$Stamp; ErrorClass='' }
    } catch { $Krbtgt=[pscustomobject]@{ Domain=$Domain; Enabled=$null; PasswordLastSet=$null; PasswordNeverExpires=$null; LastLogonTimestamp=$null; CollectionState='Failed'; SourceType='Directory'; Timestamp=$Stamp; ErrorClass=$_.Exception.GetType().Name } }
    [pscustomobject]@{ Groups=$Groups.ToArray(); Members=$Members.ToArray(); Krbtgt=$Krbtgt; CollectionMethod='Domain-scoped ActiveDirectory read-only queries' }
}

@{
    ContractVersion = '1.0'
    Framework = 'Microsoft Windows Server security baseline'
    FrameworkId = 'Microsoft-WindowsServer2025-DC'
    FrameworkVersion = '2025 Domain Controller (Azure Policy reference)'
    Publisher = 'Microsoft'
    EvaluationMode = 'FutureTarget'
    ApplicableOperatingSystems = @('Windows Server')
    ApplicableVersions = @('2025')
    ApplicableRoles = @('DomainController')
    CatalogControlCount = $null
    ScopeNote = 'Selected setting mappings only. The reference targets Windows Server 2025; observations on other versions are context, not a baseline applicability decision.'
    Controls = @(
        @{
            ControlId='CCE-37864-6'; ControlTitle='SMB server signing required'; ControlDescription='Require signed inbound SMB sessions on the server side.'
            SourceRuleIds=@('smb-signing'); EvidenceRequirements=@('EffectivePolicy'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Direct'; MappingConfidence='High'; Notes='The PSI rule observes server signing only, not the separate client signing setting.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            ControlId='AZ-WIN-00175'; ControlTitle='Disable SMB v1 server'; ControlDescription='Disable the SMB v1 server protocol.'
            SourceRuleIds=@('smbv1'); EvidenceRequirements=@('EffectiveConfiguration'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Direct'; MappingConfidence='High'; Notes='Server protocol only; the separate client driver setting is unmapped.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            ControlId='CCE-36173-3'; ControlTitle='LAN Manager authentication level'; ControlDescription='Restrict LAN Manager authentication to the baseline setting.'
            SourceRuleIds=@('ntlm-policy','ntlmv1-usage'); EvidenceRequirements=@('EffectivePolicy','CompletedTrafficTelemetry'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Partial'; MappingConfidence='Medium'; Notes='PSI classifies policy and bounded observed traffic; it does not prove the exact baseline DWORD on every DC.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            ControlId='LDAPServerLDAPServerIntegritySigningRequirementsEnforcement'; ControlTitle='LDAP server signing enforcement'; ControlDescription='Enforce LDAP server signing on domain controllers.'
            SourceRuleIds=@('ldap-signing'); EvidenceRequirements=@('EffectivePolicy'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Direct'; MappingConfidence='Medium'; Notes='Selected registry indications do not establish effective enforcement.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            ControlId='CCE-38036-0'; ControlTitle='Audit Logon'; ControlDescription='Capture successful and failed logon events.'
            SourceRuleIds=@('audit-policy'); EvidenceRequirements=@('EffectiveAuditPolicy'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Partial'; MappingConfidence='Medium'; Notes='The PSI rule summarizes audit policy and does not prove this exact subcategory on every DC.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            ControlId='CCE-36062-8'; ControlTitle='Domain firewall profile enabled'; ControlDescription='Keep the domain firewall profile enabled.'
            SourceRuleIds=@('firewall'); EvidenceRequirements=@('EffectiveConfiguration'); Applicability='Windows Server 2025 domain controller setting; other versions shown for context'
            MappingType='Partial'; MappingConfidence='Medium'; Notes='PSI observes profile state without establishing the exact domain profile baseline value or inbound rule posture.'
            Reference='https://learn.microsoft.com/en-us/azure/governance/policy/samples/guest-configuration-baseline-windows-server-2025'
        },
        @{
            MappingId='audit-logon-capacity-context'; ControlId='CCE-38036-0'; ControlTitle='Logon audit evidence support'; ControlDescription='Security log capacity provides context for logon audit review.'
            SourceRuleIds=@('event-retention'); EvidenceRequirements=@('EventLogConfiguration'); Applicability='Context for the selected Audit Logon mapping'
            MappingType='Supporting'; MappingConfidence='Low'; Notes='Provider support mapping, not a distinct Microsoft baseline control; never determines a pass or fail.'
            Reference='https://learn.microsoft.com/en-us/windows-server/security/osconfig/osconfig-how-to-configure-security-baselines'
        }
    )
}

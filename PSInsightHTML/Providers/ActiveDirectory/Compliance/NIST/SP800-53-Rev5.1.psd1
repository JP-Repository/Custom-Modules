@{
    ContractVersion = '1.1'
    FrameworkId = 'NIST-SP800-53-Rev5.1'
    Framework = 'NIST SP 800-53'
    FrameworkVersion = 'Revision 5.1'
    Publisher = 'NIST'
    EvaluationMode = 'CurrentState'
    ApplicableOperatingSystems = @('Windows Server')
    ApplicableRoles = @('DomainController')
    CatalogControlCount = $null
    ScopeNote = 'Selected technical cross-references only. Organizational selection, parameterization and full control assessment are outside this projection.'
    Controls = @(
        @{
            ControlId='SC-8'; ControlTitle='Transmission confidentiality and integrity'; ControlDescription='Protect selected properties of information in transit.'
            SourceRuleIds=@('smb-signing','ldap-signing'); EvidenceRequirements=@('EffectivePolicy'); Applicability='Selected Windows Server domain controllers; organizational selection not established'
            MappingType='Partial'; MappingConfidence='Medium'; Notes='SMB and LDAP signing cover selected integrity mechanisms, not the full organization-defined transmission scope.'
            Reference='https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf'
        },
        @{
            ControlId='AU-12'; ControlTitle='Audit record generation'; ControlDescription='Provide audit records for selected event types.'
            SourceRuleIds=@('audit-policy'); EvidenceRequirements=@('EffectiveAuditPolicy'); Applicability='Selected Windows Server domain controllers; event selection not established'
            MappingType='Partial'; MappingConfidence='Medium'; Notes='Audit policy observations do not prove the complete organization-defined event set or record content.'
            Reference='https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf'
        },
        @{
            ControlId='SC-7'; ControlTitle='Boundary protection'; ControlDescription='Monitor and control communications at selected system boundaries.'
            SourceRuleIds=@('firewall'); EvidenceRequirements=@('EffectiveConfiguration'); Applicability='Selected Windows Server domain controllers; boundary definition not established'
            MappingType='Partial'; MappingConfidence='Low'; Notes='Local firewall profile state is only one technical indication; network boundaries and traffic policy are not fully assessed.'
            Reference='https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf'
        },
        @{
            MappingId='nist-au12-log-capacity-context'; ControlId='AU-12'; ControlTitle='Audit capacity context'; ControlDescription='Log retention capacity informs audit review.'
            SourceRuleIds=@('event-retention'); EvidenceRequirements=@('EventLogConfiguration'); Applicability='Supporting context for AU-12'
            MappingType='Supporting'; MappingConfidence='Low'; Notes='Provider support mapping; cannot establish AU-12 compliance.'
            Reference='https://csrc.nist.gov/CSRC/media/Projects/risk-management/800-53%20Downloads/800-53r5/SP_800-53_v5_1-derived-OSCAL.pdf'
        }
    )
}

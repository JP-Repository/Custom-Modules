@{
    Version = '1.0.0'
    TargetOS = '2025'
    ReadyScoreMinimum = 90
    ReviewScoreMinimum = 75
    Rules = @(
        @{ Id='functional-level'; Category='platform'; Name='AD functional level interoperability'; SourceId='FunctionalLevels'; Weight=2; Rationale='Existing domain and forest must be at least Server 2016 functional level for a Server 2025 DC.' }
        @{ Id='dc-inventory'; Category='platform'; Name='Domain controller and OS inventory'; SourceId='ServerLifecycle'; Weight=1; Rationale='Confirm current DC count, roles, OS/build inventory, reboot state, and source OS support dates.' }
        @{ Id='fsmo-gc'; Category='platform'; Name='FSMO and Global Catalog placement'; SourceId='LocalPolicy'; Weight=1; Rationale='All five FSMO holders and GC placement must be known.' }
        @{ Id='sites-subnets'; Category='platform'; Name='Sites and subnet coverage'; SourceId='LocalPolicy'; Weight=1; Rationale='Known sites and subnets support placement review.' }
        @{ Id='replication'; Category='replication'; Name='Current material replication health'; SourceId='Upgrade'; Weight=2; Rationale='Current material failures block; historical transient events require review.' }
        @{ Id='replication-coverage'; Category='replication'; Name='Naming-context and partner coverage'; SourceId='LocalPolicy'; Weight=1; Rationale='Verify partner state and naming-context observations.' }
        @{ Id='sysvol'; Category='replication'; Name='SYSVOL, NETLOGON and DFSR'; SourceId='Sysvol'; Weight=2; Rationale='FRS SYSVOL is not a valid Server 2025 readiness state.' }
        @{ Id='dns-client'; Category='dns'; Name='DNS client and resolver resilience'; SourceId='LocalPolicy'; Weight=1; Rationale='Self DNS alone is not a failure; unreachable or concentrated resolvers warrant review.' }
        @{ Id='dns-zones'; Category='dns'; Name='AD-integrated and reverse zone health'; SourceId='LocalPolicy'; Weight=1; Rationale='Check observed zone presence and replication state.' }
        @{ Id='dns-forwarders'; Category='dns'; Name='Forwarder reachability'; SourceId='LocalPolicy'; Weight=1; Rationale='Only tested forwarders may be called reachable.' }
        @{ Id='time'; Category='health'; Name='PDC and domain time hierarchy'; SourceId='LocalPolicy'; Weight=1; Rationale='PDC upstream and DC source consistency require evidence.' }
        @{ Id='services'; Category='health'; Name='Core DC services'; SourceId='LocalPolicy'; Weight=1; Rationale='Service state is one health signal, not a complete health verdict.' }
        @{ Id='disk'; Category='health'; Name='System volume free space'; SourceId='LocalPolicy'; Weight=1; Rationale='Fictional profile threshold: less than 10 GB free is Review.' }
        @{ Id='ports'; Category='health'; Name='Topology-aware port evidence'; SourceId='LocalPolicy'; Weight=1; Rationale='Required, role-expected and untested connections remain distinct.' }
        @{ Id='exchange'; Category='compatibility'; Name='Exchange AD server compatibility'; SourceId='Exchange'; Weight=2; Rationale='Exchange SE or 2019 CU14+ supports Server 2025 AD servers; Exchange 2016 does not. Unknown CU is Review.' }
        @{ Id='dependencies'; Category='compatibility'; Name='Application dependency inventory'; SourceId='LocalPolicy'; Weight=1; Rationale='Unknown dependency compatibility must not be labeled Ready.' }
    )
}

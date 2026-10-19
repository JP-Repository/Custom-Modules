# Compatibility loader. The implementation lives in Providers/ActiveDirectory.
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Models/Add-PSIADResources.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Relationships/Add-PSIADRelationships.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Evidence/New-PSIADRuleEvidence.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Assessments/DCReadiness/Test-PSIADDCReadiness.ps1')

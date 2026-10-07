@{
    RootModule        = 'PSInsightEmail.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5C24B7DA-3B0C-4ACB-95F8-B34C01C538D1'
    Author            = 'PSInsightEmail'
    CompanyName       = 'PSInsightEmail'
    Copyright         = 'Copyright (c) PSInsightEmail'
    Description       = 'Enterprise HTML email composition framework for PowerShell.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-PSIEmail'
        'Send-PSIEmailGraph'
        'Send-PSIEmailSmtp'
        'Add-PSIEmailSection'
        'Add-PSIEmailRow'
        'Add-PSIEmailText'
        'Add-PSIEmailKPI'
        'Add-PSIEmailKeyValue'
        'Add-PSIEmailAlert'
        'Add-PSIEmailBanner'
        'Add-PSIEmailAttachment'
        'Add-PSIEmailInlineResource'
        'Add-PSIEmailTable'
        'Add-PSIEmailDivider'
        'ConvertTo-PSIEmailHtml'
        'Export-PSIEmailPreview'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}

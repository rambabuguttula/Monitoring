Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
Remove-Item Alias:\curl -Force -ErrorAction SilentlyContinue
Remove-Item Alias:\curl -Force -ErrorAction SilentlyContinue

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath ImportExcel) -Global

. $PSScriptRoot\LibSrc\LogHelper.ps1
. $PSScriptRoot\LibSrc\Read-ExcelTemplate.ps1
. $PSScriptRoot\LibSrc\Enable-DiagnosticSettings.ps1
. $PSScriptRoot\LibSrc\Set-CustomQueryAlertRules.ps1
. $PSScriptRoot\LibSrc\Create-AllDashboards.ps1
. $PSScriptRoot\LibSrc\Apply-MonitoringTemplate.ps1
. $PSScriptRoot\LibSrc\Create-GrafanaAppReg.ps1

    if( (get-command curl -ErrorAction SilentlyContinue).DisplayName -eq "curl -> Invoke-WebRequest" )
    {
        If (Test-Path Alias:curl) {Remove-Item Alias:curl -Force}
        If (Test-Path Alias:curl) {Remove-Item Alias:curl -Force}
        If (Test-Path Alias:curl) {Remove-Item Alias:curl -Force}
    }

Export-ModuleMember Apply-MonitoringTemplate, Connect-ResourcesToLogAnaliticsWorkspace, Set-CustomQueryAlertRules, Create-AllDashboards, Create-GrafanaAppReg
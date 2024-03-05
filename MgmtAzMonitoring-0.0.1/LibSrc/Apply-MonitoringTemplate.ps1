. $PSScriptRoot\.\Enable-DiagnosticSettings.ps1
. $PSScriptRoot\.\Set-CustomQueryAlertRules.ps1


function Apply-MonitoringTemplate
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $LogFolder)

    Connect-ResourcesToLogAnaliticsWorkspace -ExcelFileName $ExcelFileName -LogFolder $LogFolder
    Set-CustomQueryAlertRules -ExcelFileName $ExcelFileName -LogFolder $LogFolder
    Create-AllDashboards -ExcelFileName $ExcelFileName -LogFolder $LogFolder
}
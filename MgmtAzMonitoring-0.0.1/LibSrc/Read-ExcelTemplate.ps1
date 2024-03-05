Import-Module $PSScriptRoot\..\ImportExcel

. $PSScriptRoot\.\Read-MonitoringConfigPage.ps1
. $PSScriptRoot\.\Read-ServicePage.ps1
. $PSScriptRoot\.\Read-Metrics.ps1

function GetActiveSubscriptionIDs($MonObj)
{
    @($MonObj.Config.EnvPageDev.GetResourceGroupsPerSubID().keys) + 
    @($MonObj.Config.EnvPageQa.GetResourceGroupsPerSubID().keys) + 
    @($MonObj.Config.EnvPageProd.GetResourceGroupsPerSubID().keys) +
    @($MonObj.PredefinedConstants.GetCacheSubscriptionIDs()) | select -Unique
}

function GetArrayOfAllResourceTypes($MonObj)
{
     @("EnvPageDev", "EnvPageQa", "EnvPageProd") | %{
         $MonObj.Config."$_".GetArrayOfResourceTypes()
     } | Select-Object -Unique
}

function SetActiveSubscriptionIDs($MonObj)
{
    $ActiveSubscriptionIDs = @($MonObj.GetActiveSubscriptionIDs()) | ?{

                $SubscriptionID = $_
                Set-AzContext -Subscription $SubscriptionID -ErrorAction Stop  | Out-Null
                $MonitoringResIDList = (Get-AzResource -Tag @{ "MONITORING-$($MonObj.Config.GetProjectID())"="ENABLED"; } -ErrorAction Stop ).ResourceId

                if(@($MonitoringResIDList).Count -eq 0 ) { $false }
                else { $true }
            } 

    $MonObj.PredefinedConstants.SetCacheSubscriptionIDs($ActiveSubscriptionIDs)
}


<#
.SYNOPSIS
   Creating a Monitoring Object

.DESCRIPTION
   Creating a Monitoring Object from Excel file template.

.EXAMPLE
   $MonObj = New-MonitoringObj -ExcelFileName '.\Template..xlsx'

.OUTPUTS
   [PSCustomObject] @{
                        ExcelFileName = "..."

                        Config = 
                        PredefinedConstants = 

                        GetMetrics()
    }
#>
function New-MonitoringObj
{
    [cmdletBinding()] [OutputType([psobject])]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage="Full path to Excel file template.")]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String] $ExcelFileName
    )

    Process
    {
        $MonObj = $null
        $MonObj = new-object psobject -Property @{
                                                        ExcelFileName=$ExcelFileName
                                                        Config = New-MonitoringCfg -ExcelFileName $ExcelFileName
                                                        PredefinedConstants = New-PredefinedConstants -ExcelFileName $ExcelFileName
                                                 }

        $MonObj = $MonObj | Add-Member -MemberType ScriptMethod `
                                       -Name "GetMetrics" `
                                       -Value {
                                                GetMetrics -ExcelFileName $this.ExcelFileName
                                              }  `
                                       -PassThru `
                                       -ErrorAction Stop `
                                       -Force

        $MonObj = $MonObj | Add-Member -MemberType ScriptMethod `
                                -Name "GetActiveSubscriptionIDs" `
                                -Value {
                                            GetActiveSubscriptionIDs -MonObj $this
                                       }  `
                                -PassThru `
                                -ErrorAction Stop `
                                -Force

        $MonObj = $MonObj | Add-Member -MemberType ScriptMethod `
                                -Name "SetActiveSubscriptionIDs" `
                                -Value {
                                            SetActiveSubscriptionIDs -MonObj $this
                                       }  `
                                -PassThru `
                                -ErrorAction Stop `
                                -Force

        $MonObj = $MonObj | Add-Member -MemberType ScriptMethod `
                                -Name "GetArrayOfAllResourceTypes" `
                                -Value {
                                            GetArrayOfAllResourceTypes -MonObj $this
                                       }  `
                                -PassThru `
                                -ErrorAction Stop `
                                -Force

        $MonObj
    }
}
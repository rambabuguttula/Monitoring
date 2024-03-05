. $PSScriptRoot\.\Read-EnvPages.ps1

function GetProjectID($ExcelFileName)
{
    $ProjectID =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 1 -StartRow 1 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($ProjectID.Name -eq "ProjectID")
    {
        $ProjectID.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(1) should contain 'ProjectID'" 
    }
}

function GetProjectDisplayName($ExcelFileName)
{
    $ProjectDisplayName =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 2 -StartRow 2 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($ProjectDisplayName.Name -eq "Project Display Name")
    {
        $ProjectDisplayName.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(2) should contain 'Project Display Name'" 
    }
}


function GetRelatedProjectIDs($ExcelFileName)
{
    $RelatedProjectIDs =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 3 -StartRow 3 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($RelatedProjectIDs.Name -eq "Related project IDs")
    {
        if($RelatedProjectIDs.Value -replace " " -ne "")
        {
            $RelatedProjectIDs.Value -replace " " -split "[,;|]"
        }
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(3) should contain 'Related project IDs'" 
    }
}

function GetGrafanaURL($ExcelFileName)
{
    $GrafanaURL =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 4 -StartRow 4 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($GrafanaURL.Name -eq "Grafana URL")
    {
        $GrafanaURL.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(4) should contain 'Grafana URL'" 
    }
}

function GetGrafanaDashboardsFolder($ExcelFileName)
{
    $DashboardsFolder =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 5 -StartRow 5 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($DashboardsFolder.Name -eq "Dashboards Folder Name")
    {
        $DashboardsFolder.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(5) should contain 'Dashboards Folder NameL'" 
    }
}

function GetGrafanaAPIkey($ExcelFileName)
{
    $GrafanaAPIkey =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 6 -StartRow 6 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($GrafanaAPIkey.Name -eq "Grafana API key")
    {
        $GrafanaAPIkey.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(6) should contain 'Grafana API key'" 
    }
}

function GetSubscriptionIDs($ExcelFileName)
{
    $SubscriptionIDs =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 7 -StartRow 7 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($SubscriptionIDs.Name -eq "SubscriptionIDs")
    {
        if($SubscriptionIDs.Value -replace " " -ne "")
        {
            $SubscriptionIDs.Value -replace " " -split "[,;|]"
        }
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(7) should contain 'SubscriptionIDs'" 
    }
}

function GetWorkspaceId($ExcelFileName)
{
    $WorkspaceId =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 8 -StartRow 8 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($WorkspaceId.Name -eq "Log Analitics WorkspaceId")
    {
        $WorkspaceId.Value
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(8) should contain 'Log Analitics WorkspaceId'" 
    }
}

function GetWorkspaceSubscription($ExcelFileName)
{
    $WorkspaceId =  GetWorkspaceId -ExcelFileName $ExcelFileName
    if($WorkspaceId -match "/subscriptions/([^/]+)/resourcegroups/[^/]+/providers/")
    {
        $Matches[1]
    }
    else
    {
        throw "Incorrect Excel format. Incorrect WorkspaceId format on 'Monitoring Config' Excel spreadsheet in Row(8) Column(2)" 
    }     
}

function GetWorkspaceRg($ExcelFileName)
{
    $WorkspaceId =  GetWorkspaceId -ExcelFileName $ExcelFileName
    if($WorkspaceId -match "/subscriptions/[^/]+/resourcegroups/([^/]+)/providers/")
    {
        $Matches[1]
    }
    else
    {
        throw "Incorrect Excel format. Incorrect WorkspaceId format on 'Monitoring Config' Excel spreadsheet in Row(8) Column(2)" 
    }     
}

function GetWorkspaceName($ExcelFileName)
{
    $WorkspaceId =  GetWorkspaceId -ExcelFileName $ExcelFileName
    if($WorkspaceId -match "/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft.operationalinsights/workspaces/([^/]+)$")
    {
        $Matches[1]
    }
    else
    {
        throw "Incorrect Excel format. Incorrect WorkspaceId format on 'Monitoring Config' Excel spreadsheet in Row(8) Column(2)" 
    }     
}

function GetDataSources($ExcelFileName)
{
    $DataSources =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 9 -StartRow 9 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($DataSources.Name -eq "Data Sources")
    {
        $DataSources.Value -replace " " -split "\|"
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(9) should contain 'Data Sources'" 
    }     
}

function GetDLlist($ExcelFileName)
{
    $DLList =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 10 -StartRow 10 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($DLList.Name -eq "DL List")
    {
        $DLList.Value -replace " " -split ","
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(10) should contain 'DL List'" 
    }    
}

function GetITSMFuncURL($ExcelFileName)
{
    $ITSMFuncURL =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 11 -StartRow 11 -WorksheetName "Monitoring Config" -ErrorAction Stop
    if($ITSMFuncURL.Name -eq "ITSM Function App URL")
    {
        $ITSMFuncURL.Value -replace " "
    }
    else
    {
        throw "Incorrect Excel format. 'Monitoring Config' Excel spreadsheet in Row(11) should contain 'ITSM Function App URL'" 
    }    
}

function GetEnvPageNames($EnvPageDev, $EnvPageQa, $EnvPageProd)
{
    $EnvPageList = @()
    if( $EnvPageDev.IsEnvPage() ) { $EnvPageList += @("Dev") }
    if( $EnvPageQa.IsEnvPage() ) { $EnvPageList += @("Qa") }
    if( $EnvPageProd.IsEnvPage() ) { $EnvPageList += @("Prod") }   
    $EnvPageList
}

<#
.SYNOPSIS
   Creating a MonitoringConfig Object

.DESCRIPTION
   Creating a MonitoringConfig object from Excel file template.

.EXAMPLE
   $MonCfg = New-MonitoringCfg -ExcelFileName '.\Template..xlsx'

.OUTPUTS
   [PSCustomObject] @{
                        ExcelFileName = "..."

                        GetSubscriptionID()
                        GetWorkspaceId()
                        GetArrayOfResourceTypes()
                        GetResourceGroups()
                        GetIncludedTags()
                        GetExcludedResources()
    }
#>
function New-MonitoringCfg
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
        try
        {
            $MonCfgObject = $null
            $MonCfgObject = new-object psobject -Property @{
                                                                ExcelFileName=$ExcelFileName
                                                                EnvPageDev  = New-Enviroment -ExcelFileName $ExcelFileName -EnvWorksheetName "Dev Env"
                                                                EnvPageQa   = New-Enviroment -ExcelFileName $ExcelFileName -EnvWorksheetName "QA Env"
                                                                EnvPageProd = New-Enviroment -ExcelFileName $ExcelFileName -EnvWorksheetName "Prod Env"
                                                           }

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetEnvPageNames" `
                                                       -Value {
                                                                    GetEnvPageNames -EnvPageDev $this.EnvPageDev -EnvPageQa $this.EnvPageQa -EnvPageProd $this.EnvPageProd
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetProjectID" `
                                                       -Value {
                                                                    GetProjectID -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetProjectDisplayName" `
                                                       -Value {
                                                                    GetProjectDisplayName -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetRelatedProjectIDs" `
                                                       -Value {
                                                                    GetRelatedProjectIDs -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetGrafanaURL" `
                                                       -Value {
                                                                    GetGrafanaURL -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetGrafanaDashboardsFolder" `
                                                       -Value {
                                                                    GetGrafanaDashboardsFolder -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetGrafanaAPIkey" `
                                                       -Value {
                                                                    GetGrafanaAPIkey -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetSubscriptionIDs" `
                                                       -Value {
                                                                    GetSubscriptionIDs -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetWorkspaceId" `
                                                       -Value {
                                                                    GetWorkspaceId -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetWorkspaceSubscription" `
                                                       -Value {
                                                                    GetWorkspaceSubscription -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetWorkspaceRg" `
                                                       -Value {
                                                                    GetWorkspaceRg -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetWorkspaceName" `
                                                       -Value {
                                                                    GetWorkspaceName -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetDataSources" `
                                                       -Value {
                                                                    GetDataSources -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetDLlist" `
                                                       -Value {
                                                                    GetDLlist -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject = $MonCfgObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetITSMFuncURL" `
                                                       -Value {
                                                                    GetITSMFuncURL -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $MonCfgObject

        }
        catch{ Write-Error -ErrorRecord $_ }
    }
}
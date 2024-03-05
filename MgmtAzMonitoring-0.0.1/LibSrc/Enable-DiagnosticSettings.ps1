. $PSScriptRoot\.\LogHelper.ps1
. $PSScriptRoot\.\Read-ExcelTemplate.ps1

##############################################################################
#
#  Functions get lists of included and excluded resources
#
#-----------------------------------------------------------------------------

function Get-AllEnabledResources
{
    [cmdletBinding()] Param($PredefinedConstants, $EnvConfig, $SubscriptionID)

    try
    {
        $MonObj_PredefinedConstants_AllPossibleResTypes = $PredefinedConstants.GetAllPossibleResTypes()
        $MonObj_Config_ArrayOfResourceTypes = $EnvConfig.GetArrayOfResourceTypes()
        $MonObj_Config_ResourceGroups = $EnvConfig.GetResourceGroupsPerSubID()[$SubscriptionID]
        $MonObj_Config_IncludedTagsAsHashTable = $EnvConfig.GetIncludedTagsAsHashTable()

        if($MonObj_Config_ArrayOfResourceTypes.Count -eq 0  -or $MonObj_Config_ResourceGroups.Count -eq 0)
        {
            return @()
        }

        # Получим Azure тип для "Storage Account"
        $ResTypeSA = $MonObj_PredefinedConstants_AllPossibleResTypes | ?{$_.ResTypeDisplayName -eq "Storage Account" }

        # Собираем в $AllResTypes все типы ресурсов, что явно заданы, на странице "Monitoring Config"
        $AllResTypes = $MonObj_PredefinedConstants_AllPossibleResTypes | `
                       ?{$_.ResTypeDisplayName -in $MonObj_Config_ArrayOfResourceTypes}

        # Собираем в $AllResTypesNotSA все типы ресурсов, что явно заданы, на странице "Monitoring Config", кроме любых "Storage Account" 
        $AllResTypesNotSA = ( $AllResTypes | ?{$_.ResTypeDisplayName -notmatch "Storage Account" } ).ResType 

        # Собираем в $AllResTypesSA все типы "Storage Account" ресурсов, что явно заданы, на странице "Monitoring Config" 
        $AllResTypesSA = $AllResTypes | ?{$_.ResTypeDisplayName -match "Storage Account" }

        # Сначало найдем все ресурсы не SA, соответствующие фильтрам: Ресурсным группам, Тегам, и Типам из $AllResTypesNotSA
        $ODataQuery = "( "

        $MonObj_Config_ResourceGroups | %{ $ODataQuery += "resourceGroup eq '$_' or " }  
        $ODataQuery = $ODataQuery -replace " or $",""

        $ODataQuery += " ) and ( "

        @($AllResTypesNotSA) | %{ $ODataQuery += "resourceType eq '$_' or " }
        $ODataQuery = $ODataQuery -replace " or $",""

        $ODataQuery += " )"

        $EnabledResIDList = (Get-AzResource -ODataQuery $ODataQuery -Tag $MonObj_Config_IncludedTagsAsHashTable -ErrorAction Stop ).ResourceId

        # Затем найдем все ресурсы SA, соответствующие фильтрам: Ресурсным группам, Тегам, и Под Типам SA, и добавим их в общий список ресурсов $EnabledResIDList 
        if($AllResTypesSA)
        {
            # Найдем все Сторедж Акаунты, соответствующие фильтрам: Ресурсным группам, Тегам, и имеющим тип "Storage Account"
            $ODataQuery = "( "

            $MonObj_Config_ResourceGroups | %{ $ODataQuery += "resourceGroup eq '$_' or " }  
            $ODataQuery = $ODataQuery -replace " or $",""

            $ODataQuery += " ) and ( resourceType eq '$($ResTypeSA.ResType)' )"


            $ResIDListSA = (Get-AzResource -ODataQuery $ODataQuery -Tag $MonObj_Config_IncludedTagsAsHashTable -ErrorAction Stop ).ResourceId

            # Получим все ID подтипов Сторедж Акаунты в соответствии с фильтрами, и добавим эти конкретные ID в общий список $EnabledResIDList
            @($ResIDListSA) | %{

                $ResIdSA = $_

                $AllResTypesSA | %{
                        switch($_.ResTypeDisplayName)
                        {
                            "Storage Account queue"     { "$ResIdSA/queueServices/default"}
                            "Storage Account Blob"      { "$ResIdSA/blobServices/default" }
                            "Storage Account Fileshare" { "$ResIdSA/fileServices/default" }
                            "Storage Account Table"     { "$ResIdSA/tableServices/default"}
                            "Storage Account"           { "$ResIdSA"}
                        }
                } | %{ 
                        $EnabledResIDList += $_
                     } 
            }
        }

        # Получим исписок исключения ресурсов
        $ExludedResList = $EnvConfig.GetExcludedResources()

        # Исключим из полученно $EnabledResIDList списка, те ресурсы, что есть в списке исключений $ExludedResList
        @($EnabledResIDList) | ? {$_ -notin $ExludedResList} | Sort-Object -Unique 
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-AllEnabledResources(): $($_.Exception.Message) ", $_.Exception))
    }    
}

function Get-AllDisabledResources
{
    [cmdletBinding()] Param($PredefinedConstants, $Config, $Env, $EnabledResIDList)
    try
    {
        $MonObj_Config_ArrayOfResourceTypes = $Config."$Env".GetArrayOfResourceTypes()

        # Получим исписок исключения ресурсов
        $ExludedResList = $Config."$Env".GetExcludedResources()
             
        # Найдем все ресурсы, что мы хотим отключить, как ресурсы ранее включенные(по тегам)   # "MONITORING-$($Config.GetProjectID())"="ENABLED";
        $MonitoringResIDList = (Get-AzResource -Tag @{
                                                        "MONITORING-$($Config.GetProjectID())-Env"="$Env";
                                                     }`
                                               -ErrorAction Stop ).ResourceId

        # Собираем в $AllResTypesSA все типы "Storage Account" ресурсов, что явно заданы, на странице "Monitoring Config" 
        $AllResTypesSA = $PredefinedConstants.GetAllPossibleResTypes() | `
                         ?{$_.ResTypeDisplayName -in $MonObj_Config_ArrayOfResourceTypes} | `
                         ?{$_.ResTypeDisplayName -match "Storage Account" }
    
        # Плучим детальный список ресурсов на отключение, с учетом не используемых подтипов SA, 
        #        проверим так же, что для не используемого подтипа SA у ресурса существует DiagnosticSetting

        $DisabledResIDList = @()

        @($MonitoringResIDList) | %{ 
    
            if($_ -notmatch "Microsoft.Storage/storageAccounts") { $DisabledResIDList += $_} # Если у нас не SA cразу вернем его ID
            else
            {
                $StorageAccountResId = $_

                $NeededResIDSAHash = @{
                            "Storage Account queue" = "$StorageAccountResId/queueServices/default"
                            "Storage Account Blob"  = "$StorageAccountResId/blobServices/default"
                            "Storage Account Fileshare" = "$StorageAccountResId/fileServices/default"
                            "Storage Account Table" = "$StorageAccountResId/tableServices/default"
                            "Storage Account"       = "$StorageAccountResId"
                            }

                $AllResTypesSA | %{ if($NeededResIDSAHash.Item($_.ResTypeDisplayName) -notin $ExludedResList)
                                    {                
                                        $NeededResIDSAHash.Remove($_.ResTypeDisplayName) | Out-Null 
                                    }
                                  } 

                @($NeededResIDSAHash.Values) | %{

                    if( (Get-AzDiagnosticSetting -ResourceId $_ -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -ne $null)
                    {
                        # Вернем ID SA, если он не попадает в фильтры и существует
                        $DisabledResIDList += $_
                    }
                }
            }
        }

        # Исключим ресурсы, что стоят в списке на включение
        @($DisabledResIDList) | ? {$_ -notin $EnabledResIDList} | Sort-Object -Unique 
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-AllDisabledResources(): $($_.Exception.Message) ", $_.Exception))
    }       
}

##############################################################################
#
#  Remove TAG from disabling DiagnosticSetting resources
#
#-----------------------------------------------------------------------------

function Remove-AllDisabledResTags
{
    [cmdletBinding()] Param([string] $ProjectID, $DisabledResList, $Env, $Loger)

    try
    {
        @($DisabledResList) | %{

            if($_ -match "(.+/Microsoft.Storage/storageAccounts/[^/]+)(/(queueServices|blobServices|fileServices|tableServices)/default)")
            {
                $SA_ID = $Matches[1]
                $SA_ID     
            } 
            else
            {
                $_
            }
        } | Sort-Object -Unique | %{

            $ResId = $_

            try
            {
                # Если это не SA удалим ему тег TAG
                if($ResId -notmatch "Microsoft.Storage/storageAccounts")
                {
                    Update-AzTag -ResourceId $ResId -Tag  @{"MONITORING-$ProjectID"="ENABLED";} -Operation Delete -ErrorAction Stop | Out-Null
                    Update-AzTag -ResourceId $ResId -Tag  @{"MONITORING-$($ProjectID)-Env"="$Env";} -Operation Delete -ErrorAction Stop | Out-Null

                    Write-Host "Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' successfully completed"
                    Write-Host "Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' successfully completed" 
                    $Loger.OutSummaryLineCSV("[    OK]; Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' successfully completed")
                    $Loger.OutSummaryLineCSV("[    OK]; Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' successfully completed")
                }
                else
                {
                    $AllResIDSAList = @(
                        "$ResId/queueServices/default",
                        "$ResId/blobServices/default",
                        "$ResId/fileServices/default",
                        "$ResId/tableServices/default",
                        "$ResId")

                    if( (Get-AzDiagnosticSetting -ResourceId $AllResIDSAList[0] -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -eq $null -and
                        (Get-AzDiagnosticSetting -ResourceId $AllResIDSAList[1] -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -eq $null -and
                        (Get-AzDiagnosticSetting -ResourceId $AllResIDSAList[2] -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -eq $null -and
                        (Get-AzDiagnosticSetting -ResourceId $AllResIDSAList[3] -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -eq $null -and
                        (Get-AzDiagnosticSetting -ResourceId $AllResIDSAList[4] -Name AutoMngLogAnalyticsSettings -ErrorAction SilentlyContinue) -eq $null)
                    {
                         Update-AzTag -ResourceId $ResId -Tag  @{"MONITORING-$ProjectID"="ENABLED";} -Operation Delete -ErrorAction Stop | Out-Null
                         Update-AzTag -ResourceId $ResId -Tag  @{"MONITORING-$($ProjectID)-Env"="$Env";} -Operation Delete -ErrorAction Stop | Out-Null

                         Write-Host "Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' successfully completed"
                         Write-Host "Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' successfully completed" 
                         $Loger.OutSummaryLineCSV("[    OK]; Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' successfully completed")
                         $Loger.OutSummaryLineCSV("[    OK]; Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' successfully completed")
                    }
                }
            }
            catch
            {
                Write-Host -ForegroundColor DarkRed "Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' unsuccessfully completed"
                Write-Host -ForegroundColor DarkRed "Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' unsuccessfully completed"                
                $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

                $Loger.OutSummaryLineCSV("[FAIL!!]; Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' unsuccessfully completed")
                $Loger.OutSummaryLineCSV("[FAIL!!]; Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' unsuccessfully completed")
                $Loger.OutErrorLog($_, "Removing 'MONITORING-$ProjectID':'ENABLED' Tag from '$ResId' unsuccessfully completed",$IsVerbose)
                $Loger.OutErrorLog($_, "Removing 'MONITORING-$($ProjectID)-Env':'$Env' Tag from '$ResId' unsuccessfully completed",$IsVerbose)
            }

        }
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Remove-AllDisabledResTags(): $($_.Exception.Message) ", $_.Exception))
    }
}

##############################################################################
#
#  Enabling and disabling DiagnosticSetting functions
#
#-----------------------------------------------------------------------------

function Enable-DiagnosticSetting
{
    [cmdletBinding()] Param([string] $ResourceId, [string] $WorkspaceId, [string] $ProjectID, [string] $Env)

    try
    {
        $metric = @()
        $log = @()
        Get-AzDiagnosticSettingCategory -ResourceId $ResourceId -ErrorAction Stop | %{

            if($_.CategoryType -eq "Metrics")
            {
                $metric += New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category $_.Name -ErrorAction Stop
            } 
            else
            {
                $log += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -Category $_.Name -ErrorAction Stop
            }
        }
    
        $res = New-AzDiagnosticSetting -Name AutoMngLogAnalyticsSettings -ResourceId $ResourceId -WorkspaceId $WorkspaceId -Log $log -Metric $metric -ErrorAction Stop
        
        # Если мы включаем DiagnosticSetting у ресурса, что не под тип SA, то установим ему TAG
        # Если мы включаем DiagnosticSetting у ресурса, что под тип SA, то установим TAG у SA
        if($ResourceId -notmatch "Microsoft.Storage/storageAccounts/[^/]+/(queueServices|blobServices|fileServices|tableServices)/default")
        {
            Update-AzTag -ResourceId $ResourceId -Tag  @{
                                                            "MONITORING-$ProjectID"="ENABLED";
                                                            "MONITORING-$($ProjectID)-Env"="$Env";
                                                        } -Operation Merge -ErrorAction Stop | Out-Null
        }
        else
        {
            $ResourceId -match "(.+)(/(queueServices|blobServices|fileServices|tableServices)/default)" | Out-Null
            $sa_res_id = $Matches[1]               
            Update-AzTag -ResourceId $sa_res_id -Tag  @{
                                                            "MONITORING-$ProjectID"="ENABLED";
                                                            "MONITORING-$($ProjectID)-Env"="$Env";
                                                       } -Operation Merge -ErrorAction Stop | Out-Null
        }

    } 
    catch
    {
        try{ Remove-AzDiagnosticSetting -ResourceId $ResourceId -Name AutoMngLogAnalyticsSettings -ErrorAction Stop | Out-Null } catch{}
        try{ Update-AzTag -ResourceId $ResourceId -Tag  @{"MONITORING-$ProjectID"="ENABLED"; "MONITORING-$($ProjectID)-Env"="$Env";} -Operation Delete -ErrorAction Stop | Out-Null } catch{}

        Write-Error -Exception ([Exception]::new("Error in Enable-DiagnosticSetting(): $($_.Exception.Message) ", $_.Exception))
    }
}

function Enable-DiagnosticSettingWrapper
{
    [cmdletBinding()] Param([string] $ResId, $MonObj, $Env, $Loger)
        
    try
    {  
        Enable-DiagnosticSetting -ResourceId $ResId -WorkspaceId $MonObj.Config.GetWorkspaceId() -ProjectID $MonObj.Config.GetProjectID() -Env $Env -ErrorAction Stop

        Write-Host "Enabling DiagnosticSetting for '$ResId' successfully completed" 
        $Loger.OutSummaryLineCSV("[    OK]; Enabling DiagnosticSetting for '$ResId' successfully completed")
    }
    catch
    {            
        Write-Host -ForegroundColor DarkRed "Enabling DiagnosticSetting for '$ResId' unsuccessfully completed"
                
        $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

        $Loger.OutSummaryLineCSV("[FAIL!!]; Enabling DiagnosticSetting for '$ResId' unsuccessfully completed")
        $Loger.OutErrorLog($_, "Enabling DiagnosticSetting for '$ResId' unsuccessfully completed",$IsVerbose)
    }
}

function Disable-DiagnosticSetting
{
    [cmdletBinding()] Param([string] $ResId, $MonObj, $Loger)

    try
    {  
        Remove-AzDiagnosticSetting -ResourceId $ResId -Name AutoMngLogAnalyticsSettings -ErrorAction Stop | Out-Null

        Write-Host "Disabling DiagnosticSetting for '$ResId' successfully completed" 
        $Loger.OutSummaryLineCSV("[    OK]; Disabling DiagnosticSetting for '$ResId' successfully completed")
    }
    catch
    {
        Write-Host -ForegroundColor DarkRed "Disabling DiagnosticSetting for '$ResId' unsuccessfully completed"

        $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

        $Loger.OutSummaryLineCSV("[FAIL!!]; Disabling DiagnosticSetting for '$ResId' unsuccessfully completed")
        $Loger.OutErrorLog($_, "Disabling DiagnosticSetting for '$ResId' unsuccessfully completed", $IsVerbose)
    }
}

<#
.SYNOPSIS
   Connecting Resources to LogAnalitics Workspace

.DESCRIPTION
   Connecting resources to the LogAnalitics workspace. The list of resources is defined by the criteria set on the 'Monitoring Config' Excel spreadsheet of the input Excel file.

.EXAMPLE
   Connect-ResourcesToLogAnaliticsWorkspace -ExcelFileName '.\Template..xlsx'

#>

function Connect-ResourcesToLogAnaliticsWorkspace
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $LogFolder)

    try
    {
        $LogFolder = Resolve-Path $LogFolder -ErrorAction Stop
        $DataStr = "$(Get-Date -Format "dd.MM.yyyy-HH.mm.ss")"

        $LogFile = Join-Path -Path $LogFolder -ChildPath "ConnectResToLogAnalitics-$DataStr.log"
        $ErrFile = Join-Path -Path $LogFolder -ChildPath "ConnectResToLogAnalitics-$DataStr.err"

        $Loger = New-Logger -ErrorLogFile $ErrFile -SummaryCSVFile $LogFile -SummaryCSVHeader "Status; Description"

        try
        { 
            $Stream = [System.IO.FileInfo]::new($ExcelFileName).OpenWrite() 
            $Stream.Close()
        } 
        catch 
        {
             throw "Error opening an $ExcelFileName file. This file is already open: '$($_.Exception.InnerException.Message)'. Close Excel application."
        }

        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop

        if( $MonObj.Config.GetProjectID() -eq "")
        {
            throw "Excel file contain empty ProjectID in 'Monitoring Config' Excel spreadsheet in Row(1) Column(2)"
        }

        if( $MonObj.Config.GetWorkspaceId() -eq "")
        {
            throw "Excel file contain empty WorkspaceId in 'Monitoring Config' Excel spreadsheet in Row(3) Column(2)"
        }

        if( $MonObj.GetActiveSubscriptionIDs().Count -eq 0)
        {
            throw "Excel file don't contain SubscriptionID in 'Dev Env', 'QA Env' and 'Prod Env' Excel spreadsheets"
        }

        if( $MonObj.Config.EnvPageDev.GetArrayOfResourceTypes().Count -eq 0 -and
            $MonObj.Config.EnvPageQa.GetArrayOfResourceTypes().Count -eq 0 -and
            $MonObj.Config.EnvPageProd.GetArrayOfResourceTypes().Count -eq 0 )
        {
            throw "Excel file contain empty list Resource Types in 'Dev Env', 'QA Env' and 'Prod Env' Excel spreadsheets in Row(2) Column(1)"
        }

        if( $MonObj.Config.EnvPageDev.GetResourceGroupsPerSubID().Count -eq 0 -and
            $MonObj.Config.EnvPageQa.GetResourceGroupsPerSubID().Count -eq 0 -and
            $MonObj.Config.EnvPageProd.GetResourceGroupsPerSubID().Count -eq 0 )
        {
            throw "Excel file contain empty list Resource Groups in 'Dev Env', 'QA Env' and 'Prod Env' Excel spreadsheets in Row(2) Column(2)"
        }

        @("EnvPageDev", "EnvPageQa", "EnvPageProd") | %{

            $Env = $_

            @($MonObj.GetActiveSubscriptionIDs()) | %{

                $SubscriptionID = $_

                Set-AzContext -Subscription $SubscriptionID -ErrorAction Stop  | Out-String | Out-Host
                Write-Host ""

                $Loger.OutSummaryLineCSV("--------; ------------------- DiagnosticSettings: $Env | $SubscriptionID ---------------------------")
                Write-Host "----------------------------- DiagnosticSettings: $Env | $SubscriptionID ---------------------------"


                $EnabledResList = Get-AllEnabledResources -PredefinedConstants $MonObj.PredefinedConstants `
                                                          -EnvConfig $MonObj.Config."$Env" `
                                                          -SubscriptionID $SubscriptionID `
                                                          -ErrorAction Stop

                $DisabledResList = Get-AllDisabledResources -PredefinedConstants $MonObj.PredefinedConstants `
                                                            -Config $MonObj.Config `
                                                            -Env $Env `
                                                            -EnabledResIDList $EnabledResList `
                                                            -ErrorAction Stop

                $IsVerbose = $($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent)

                @($EnabledResList) |  ?{$_} | %{

                    $ResId = $_
                    Enable-DiagnosticSettingWrapper -ResId $ResId -MonObj $MonObj -Env $Env -Loger $Loger -Verbose:$IsVerbose

                }

                @($DisabledResList) | ?{$_} | %{

                    $ResId =$_
                    Disable-DiagnosticSetting -ResId $ResId -MonObj $MonObj -Loger $Loger -Verbose:$IsVerbose
                }

                Remove-AllDisabledResTags -ProjectID $MonObj.Config.GetProjectID() -DisabledResList $DisabledResList -Env $Env -Loger $Loger -Verbose:$IsVerbose
            }
        }

        $MonObj.SetActiveSubscriptionIDs()
        
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Connect-ResourcesToLogAnaliticsWorkspace(): $($_.Exception.Message) ", $_.Exception))
    }
}
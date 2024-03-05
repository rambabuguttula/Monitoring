. $PSScriptRoot\.\Read-ExcelTemplate.ps1
. $PSScriptRoot\.\Create-MetricsObjects.ps1
. $PSScriptRoot\.\Uploade-DashboardToGrafana.ps1

function New-variableRgKustoQuery
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $QueryResources = @()

        @("EnvPageDev", "EnvPageQa", "EnvPageProd") | %{
 
            $EnvPage = $_

            @($MonObj.GetActiveSubscriptionIDs()) | %{

                $SubscriptionID = $_

                $MonObj.Config."$EnvPage".GetResourceGroupsPerSubID()[$SubscriptionID] | ?{$_} | %{

                    $Env = switch($EnvPage)
                           {
                                "EnvPageDev" { "Dev" }
                                "EnvPageQa" { "QA" }
                                "EnvPageProd" { "Prod" }
                           }
                    $QueryResources += @("|union (print Env=`"$Env`", RG=`"$($_.ToLower())`")")
                }

            }
        }
        $QueryResources[0] = $QueryResources[0] -replace "\|union \((.+)\)","`$1"
        $QueryResources += @("|where Env == `"`$env`" | project RG ")
        
        -join $QueryResources
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in New-variableRgKustoQuery(): $($_.Exception.Message) ", $_.Exception))
    }
}

function New-variableRnKustoQuery
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $ProjectID = $MonObj.Config.GetProjectID()
        #$ResGrList = ($MonObj.Config.GetResourceGroups().ToLower() | %{"`"$_`"" } ) -join ","

        $ResGrList = ( @("EnvPageDev", "EnvPageQa", "EnvPageProd") | %{
 
            $EnvPage = $_

            @($MonObj.GetActiveSubscriptionIDs()) | %{

                $SubscriptionID = $_

                $MonObj.Config."$EnvPage".GetResourceGroupsPerSubID()[$SubscriptionID] | ?{$_} | %{"`"$($_.ToLower())`"" }
            }
        } | Select-Object -Unique ) -join ","

        $QueryResources =
"resources
| project-rename ResourceId = id
| extend ResourceId = tolower(ResourceId)
| where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ ($ResGrList)
| where ResourceId matches regex iff(indexof(`"`$rt`",`"/microsoft.storage/storageaccounts/`") == -1,
                                     `"`$rt`",
                                     `"/microsoft.storage/storageaccounts/[^/]+`$`")
| extend MonitoringTag = iff(isnotempty(extractjson('`$.MONITORING-$($ProjectID)', tostring(tags))),
                             strcat('MONITORING-$($ProjectID):', extractjson('`$.MONITORING-$($ProjectID)', tostring(tags))),
                             '')
| where MonitoringTag == 'MONITORING-$($ProjectID):ENABLED'
| project name
| extend name = iff(indexof(`"`$rt`",`"/queueservices`") != -1, strcat(name,`"/queueservices/default`"),
                iff(indexof(`"`$rt`",`"/blobservices`") != -1, strcat(name,`"/blobservices/default`"),
                iff(indexof(`"`$rt`",`"/fileservices`") != -1, strcat(name,`"/fileservices/default`"),
                iff(indexof(`"`$rt`",`"/tableservices`") != -1, strcat(name,`"/tableservices/default`"), name))))
"

        $QueryResources
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in New-variableRnKustoQuery(): $($_.Exception.Message) ", $_.Exception))
    }
}

function New-ResStatusListKustoQuery-B
{
    [cmdletBinding()] Param([string]$ResTypeDisplayName, $MonObj)

    try
    {
        $IsStorageAccount = 0
        $ResTypeBaseName = $ResTypeDisplayName
        $ProjectID = $MonObj.Config.GetProjectID()

        if($ResTypeDisplayName -match "Storage Account") 
        { 
            $IsStorageAccount = 1
            $ResTypeBaseName = "Storage Account"

            $ResExt =   switch($ResTypeDisplayName)
                        {
                            "Storage Account queue"     { "/queueservices/default"}
                            "Storage Account Blob"      { "/blobservices/default" }
                            "Storage Account Fileshare" { "/fileservices/default" }
                            "Storage Account Table"     { "/tableservices/default"}
                            "Storage Account"           { ""}
                        }
        }

        $TypeTable = Get-TypeTable -MonObj $MonObj -ErrorAction Stop

        $QueryResources = 
"resources
    | project-rename ResourceId = id 
    | extend ResourceId = tolower(ResourceId)
    | where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ (`$rg)
    | where ResourceId matches regex '$($TypeTable[$ResTypeBaseName].ResTypeRegEx)'
    | extend MonitoringTag = iff(isnotempty(extractjson('$.MONITORING-$($ProjectID)', tostring(tags))),
                                 strcat('MONITORING-$($ProjectID):', extractjson('$.MONITORING-$($ProjectID)', tostring(tags))),
                                 '')
    | where MonitoringTag == 'MONITORING-$($ProjectID):ENABLED'
    | extend Status = iff((isempty(tostring(properties.status)) and isempty(tostring(properties.state))) or 
                            tostring(properties.state) == 'Running' or tostring(properties.status) == 'Ready' or tostring(properties.status) == 'Online', 0, 2)
    | extend Enabled = iff(isempty(tostring(properties.enabled)) or tostring(properties.enabled) == 'true', 0, 2)
    | extend ResourceId = iff($($IsStorageAccount) == 1, strcat(ResourceId,'$($ResExt)'), ResourceId)
    | extend name = iff($($IsStorageAccount) == 1, strcat(name,'$($ResExt)'), name)
    | extend RawResourceType = `"$([System.Web.HttpUtility]::UrlEncode($TypeTable[$ResTypeDisplayName].ResTypeRegEx))`"`n
"
        $QueryResources
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in New-ResStatusListKustoQuery-B(): $($_.Exception.Message) ", $_.Exception))
    }
}

function New-ResStatusListKustoQuery-A
{
    [cmdletBinding()] Param([string]$ResTypeDisplayName, $MonObj, $MetricsOnlySpecificType, $Loger)

    try
    {
        $TypeTable = Get-TypeTable -MonObj $MonObj -ErrorAction Stop

        $Query = 
"let ResourcesByType = AzureMetrics 
    | where `$__timeFilter(TimeGenerated) 
    | extend ResourceId = tolower(ResourceId)
    | where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ (`$rg)
    | where ResourceId matches regex '$($TypeTable[$ResTypeDisplayName].ResTypeRegEx)';
//
let CmpThreshold = (currentValue_arg:long, cmp_oper_arg:string, Threshold_arg:long)
{
    iff(cmp_oper_arg == '>', currentValue_arg > Threshold_arg, 
        iff(cmp_oper_arg == '<', currentValue_arg < Threshold_arg,
        iff(cmp_oper_arg == '>=', currentValue_arg >= Threshold_arg,
        iff(cmp_oper_arg == '<=', currentValue_arg <= Threshold_arg, false)))) };
//
let AddMetric = (MetricName_arg:string,  ThresholdFieldName_arg:string,
                 cmp_oper_arg:string, ThresholdWarning_arg:long, ThresholdError_arg:long)
{
  ResourcesByType
    | where MetricName == MetricName_arg
    | extend currentValue = iff(ThresholdFieldName_arg == 'Average', Average,
                            iff(ThresholdFieldName_arg == 'Total', Total,
                            iff(ThresholdFieldName_arg == 'Maximum', Maximum,
                            iff(ThresholdFieldName_arg == 'Minimum', Minimum, Count))))
    | extend StatusThreshold = iff(CmpThreshold(currentValue, cmp_oper_arg, ThresholdError_arg),2,
                               iff(CmpThreshold(currentValue, cmp_oper_arg, ThresholdWarning_arg),1,0))
    | where StatusThreshold > 0
    | summarize arg_max(TimeGenerated, *) by ResourceId
    | project ResourceId, StatusThreshold
};"

        # $MetricsOnlySpecificType = $MetricObjects | ?{$_.ResTypeDisplayName -eq $ResTypeDisplayName}

        if($MetricsOnlySpecificType.Count -gt 0)
        {
            $Query += "AddMetric("
            $Query += "`"$($MetricsOnlySpecificType[0].QueryMetricName)`","
            $Query += "`"$($MetricsOnlySpecificType[0].MetricMeasureColumn)`"," 
            $Query += "`"$($MetricsOnlySpecificType[0].OperatorSymbols)`","
            $Query += "`"$($MetricsOnlySpecificType[0].WarningThreshold)`","
            $Query += "`"$($MetricsOnlySpecificType[0].ErrorThreshold)`")`n"

            $Loger.OutSummaryLineCSV("[    OK]; ----- Adding condition for `"$($MetricsOnlySpecificType[0].QueryMetricName)`" metric to '$($ResTypeDisplayName)' chart")
        }

        if($MetricsOnlySpecificType.Count -gt 1)
        {
            $MetricsOnlySpecificType[1..($MetricsOnlySpecificType.Count-1)] | %{

                    $Query += "| join kind=fullouter ( AddMetric("
                    $Query += "`"$($_.QueryMetricName)`","
                    $Query += "`"$($_.MetricMeasureColumn)`"," 
                    $Query += "`"$($_.OperatorSymbols)`","
                    $Query += "`"$($_.WarningThreshold)`","
                    $Query += "`"$($_.ErrorThreshold)`") ) on ResourceId `n"

                    $Query += "| extend ResourceId = iff(isnotempty(ResourceId), ResourceId, ResourceId1)`n"
                    $Query += "| extend StatusThreshold = max_of(StatusThreshold, StatusThreshold1)| project ResourceId, StatusThreshold`n"

                    $Loger.OutSummaryLineCSV("[    OK]; ----- Adding condition for `"$($_.QueryMetricName)`" metric to '$($ResTypeDisplayName)' chart")
            }
        }

        # $Query += "| extend isAlert = 1 `n"
        # $Query += "| extend ResourceId = iff(indexof(ResourceId, '/queueservices/') != -1, extract('(.+)/queueservices/[^/]+$', 1, ResourceId), ResourceId) `n" 
        $Query += "| summarize StatusThreshold=max(StatusThreshold) by ResourceId"

        $Query
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in New-ResStatusListKustoQuery-A(): $($_.Exception.Message) ", $_.Exception))
    }
}

function New-AlertsDetailsKustoQuery
{
    [cmdletBinding()] Param($MonObj, $MetricObjects, $Loger)

    try
    {
        $AppNameByResTypeTable = (
                                    (Add-ResTypeRegEx -AllPossibleResTypes $MonObj.PredefinedConstants.GetAllPossibleResTypes() -ErrorAction Stop) | 
                                    %{ "'$($_.ResTypeRegEx)':'$($_.ResTypeDisplayName)'," }
                                 ) -join "`n" -replace ",$"

        $Query = 
"let ResourceMetrics = AzureMetrics
   | where `$__timeFilter(TimeGenerated)
   | extend ResourceId = tolower(ResourceId)
   | where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ (`$rg)
   | where ResourceId matches regex '`$rt'
   | extend FullResName = iff(indexof('`$rn','queueservices') != -1, '`$rn', iff(indexof('`$rn','blobservices') != -1, '`$rn',
                          iff(indexof('`$rn','fileservices') != -1, '`$rn', iff(indexof('`$rn','tableservices') != -1, '`$rn',
                          iff(indexof('`$rn','/') != -1, extract(tolower(strcat('.+/(', substring('`$rn', 0, indexof('`$rn','/')),'/[^/]+/', substring('`$rn', indexof('`$rn','/') + 1), ')$')), 1, ResourceId),'`$rn')))))
   | where isnotempty(FullResName)
   | where ResourceId endswith FullResName;
let GetAppNameByResType = (rt_arg:string){
   dynamic({ $AppNameByResTypeTable }).[rt_arg] };     
let GetCmpTxt = (cmp_oper_arg:string){
   dynamic({'>':'greater than',
            '<':'less than',
            '>=':'greater than or equal',
            '<=':'less than or equal'}).[cmp_oper_arg] };
let GetDescription = (AppName_arg:string, MetricName_arg:string, cmptxt_arg:string, threshold_arg:string, unit_arg:string) 
{
    strcat(AppName_arg,' `"', MetricName_arg, '`" metric has increased and exceeds the threshold value (', 
           cmptxt_arg, ' ', threshold_arg, ' ', unit_arg, ')') 
};
let CmpThreshold = (currentValue_arg:long, cmp_oper_arg:string, Threshold_arg:long)
{
    iff(cmp_oper_arg == '>', currentValue_arg > Threshold_arg, 
        iff(cmp_oper_arg == '<', currentValue_arg < Threshold_arg,
        iff(cmp_oper_arg == '>=', currentValue_arg >= Threshold_arg,
        iff(cmp_oper_arg == '<=', currentValue_arg <= Threshold_arg, false)))) };            
let GetValueFixByte = (Unit_arg:string, Value:long)
{
    iff(Unit_arg == 'Bytes', extract(`"([0-9.]+)(.*)`",1,tostring(format_bytes(Value, 0, 'Mb'))), tostring(Value))
};    
let AddDescription = (rt_mask_arg:string, MetricName_arg:string, 
                      ThresholdFieldName_arg:string, cmp_oper_arg:string, 
                      ThresholdWarning_arg:long, ThresholdError_arg:long, Unit_arg:string)
{
  ResourceMetrics
  | where rt_mask_arg == '`$rt'
  | where MetricName == MetricName_arg
  | extend currentValue = iff(ThresholdFieldName_arg == 'Average', Average,
                          iff(ThresholdFieldName_arg == 'Total', Total,
                          iff(ThresholdFieldName_arg == 'Maximum', Maximum,
                          iff(ThresholdFieldName_arg == 'Minimum', Minimum, Count))))
  | extend StatusThreshold = iff(CmpThreshold(currentValue, cmp_oper_arg, ThresholdError_arg),2,
                             iff(CmpThreshold(currentValue, cmp_oper_arg, ThresholdWarning_arg),1,0))
  | where StatusThreshold > 0
  | summarize arg_max(TimeGenerated, *) by ResourceId
  | extend Description = GetDescription(GetAppNameByResType(rt_mask_arg), MetricName_arg, GetCmpTxt(cmp_oper_arg),
                                        GetValueFixByte(Unit_arg, iff(StatusThreshold == 1, ThresholdWarning_arg, ThresholdError_arg)),Unit_arg)
  | extend Unit = Unit_arg
  | extend currentValue = strcat(iff(StatusThreshold == 1, 'WARN: ', 'ALARM: '), GetValueFixByte(Unit_arg, currentValue)),
           TimeGenerated = tostring(format_datetime(TimeGenerated, 'yyyy-MM-dd [HH:mm:ss]'))
  | project TimeGenerated, ResourceId, currentValue, Description, Unit
};`n"

        $Query += "AddDescription("
        $Query += "`"$($MetricObjects[0].ResTypeRegEx)`","
        $Query += "`"$($MetricObjects[0].QueryMetricName)`","
        $Query += "`"$($MetricObjects[0].MetricMeasureColumn)`"," 
        $Query += "`"$($MetricObjects[0].OperatorSymbols)`","
        $Query += "`"$($MetricObjects[0].WarningThreshold)`","
        $Query += "`"$($MetricObjects[0].ErrorThreshold)`","
        $Query += "`"$($MetricObjects[0].Unit)`")`n"

        $Loger.OutSummaryLineCSV("[    OK]; ----- Adding condition for `"$($MetricObjects[0].QueryMetricName)`" metric to 'Detail Alert Info' chart")

        $MetricObjects[1..$MetricObjects.Count] | %{

                $Query += "| union (AddDescription("
                $Query += "`"$($_.ResTypeRegEx)`","
                $Query += "`"$($_.QueryMetricName)`","
                $Query += "`"$($_.MetricMeasureColumn)`"," 
                $Query += "`"$($_.OperatorSymbols)`","
                $Query += "`"$($_.WarningThreshold)`","
                $Query += "`"$($_.ErrorThreshold)`","
                $Query += "`"$($_.Unit)`"))`n"

                $Loger.OutSummaryLineCSV("[    OK]; ----- Adding condition for `"$($_.QueryMetricName)`" metric to 'Detail Alert Info' chart")
        }

        # Сжатие
        # $Query = $Query -replace "[\s]+", " "

        $Query
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in New-AlertsDetailsKustoQuery(): $($_.Exception.Message) ", $_.Exception))
    }
}


function Create-StatusDashboard
{
    [cmdletBinding()] Param([string] $ExcelFileName, $UploadeMetricsDashboardInfoHash, [string] $OutputFolder, $Loger)
    
    $Loger.OutSummaryLineCSV("--------; ----------------------------- Creating Status Dashboard ------------------------------------")
    Write-Host "-------- ----------------------------- Creating Status Dashboard ------------------------------------" 

    try
    {        
        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop
        $MetricObjects = Get-MetricsObjects -MonObj $MonObj -ErrorAction Stop

        $DashboardTemplateFile = "$PSScriptRoot\..\Grafana Template\Status\StatusResourcesDashboardTemplate.json"
        #$CurrentResNameChartTemplateFile = "$PSScriptRoot\..\Grafana Template\Status\CurrentResNameChartTemplate.json"
        $RunningStatusChartTemplateFile = "$PSScriptRoot\..\Grafana Template\Status\RunningStatusChartTemplate.json"
        $AlertsDetailsChartTemplateFile = "$PSScriptRoot\..\Grafana Template\Status\AlertsDetailsChartTemplate.json"
        $ResListChartTemplateFile = "$PSScriptRoot\..\Grafana Template\Status\StatusResListChartTemplate.json"

        $DashboardTemplateObj = Get-Content -Path $DashboardTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        #$CurrentResNameChartObj = Get-Content -Path $CurrentResNameChartTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $RunningStatusChartObj = Get-Content -Path $RunningStatusChartTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $AlertsDetailsChartObj = Get-Content -Path $AlertsDetailsChartTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        #$CurrentResNameChartObj.targets[0].azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()
        
        $RunningStatusChartObj.targets[0].subscriptions = @($MonObj.GetActiveSubscriptionIDs())

        $AlertsDetailsChartObj.targets[0].azureLogAnalytics.query = New-AlertsDetailsKustoQuery -MonObj $MonObj -MetricObjects $MetricObjects -Loger $Loger -ErrorAction Stop
        $AlertsDetailsChartObj.targets[0].azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()
               

        #$DashboardTemplateObj.panels = @($CurrentResNameChartObj, $RunningStatusChartObj, $AlertsDetailsChartObj)
        $DashboardTemplateObj.panels += @($RunningStatusChartObj, $AlertsDetailsChartObj)
        $Loger.OutSummaryLineCSV("[    OK]; Adding 'Detail Alert Info' chart successfully completed to dashboard")
        $Loger.OutSummaryLineCSV("[    OK]; Adding 'Running Status Resource' chart successfully completed to dashboard")


        # Adding charts of list of Statuses Resources

        # Подключенные типы к Лог Аналитике
        $ResTypeList = $MonObj.GetArrayOfAllResourceTypes()

        $CountCharts = $ResTypeList.Count
        $WidthChart = 6
        $HeightChart = 10
        $WidthDashboard = 24
        $CountChartsInLine = [math]::Truncate($WidthDashboard/$WidthChart)
        $CountLine = [math]::Ceiling($CountCharts/$CountChartsInLine)

        $NumberType = 0

:GetOut for (($i = 0), ($y = 8); $i -lt $CountLine; $i++)  # $y = 8 - оставляем место для верхних двух панелей со статусом и детальной информацией об ошибке ресурса.
        {
            for (($j = 0), ($x = 0); $j -lt $CountChartsInLine; $j++)
            {
                $MetricsOnlySpecificType = $MetricObjects | ?{$_.ResTypeDisplayName -eq $ResTypeList[$NumberType]}

                while($MetricsOnlySpecificType.Count -eq 0)
                {
                    Write-Host -ForegroundColor Red "[FAIL!!] Failure to add the '$($ResTypeList[$NumberType])' chart. There aren't any enabled metrics for the '$($ResTypeList[$NumberType])' chart."
                    $Loger.OutSummaryLineCSV("[FAIL!!]; Failure to add the '$($ResTypeList[$NumberType])' chart. There aren't any enabled metrics for the '$($ResTypeList[$NumberType])' chart.")
                    $NumberType++
                    if($NumberType -ge $ResTypeList.Count){ break GetOut; }
                    $MetricsOnlySpecificType = $MetricObjects | ?{$_.ResTypeDisplayName -eq $ResTypeList[$NumberType]}   
                }

                $ResListChartObj = Get-Content -Path $ResListChartTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $ResListChartObj.title = $ResTypeList[$NumberType]
                $ResListChartObj.gridPos.h=$HeightChart 
                $ResListChartObj.gridPos.w=$WidthChart 
                $ResListChartObj.gridPos.x=$x
                $ResListChartObj.gridPos.y=$y

                $ResListChartObj.targets[0].azureLogAnalytics.query = New-ResStatusListKustoQuery-A -ResTypeDisplayName $ResTypeList[$NumberType] -MonObj $MonObj -MetricsOnlySpecificType $MetricsOnlySpecificType -Loger $Loger -ErrorAction Stop
                $ResListChartObj.targets[0].azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()
                $ResListChartObj.targets[1].azureResourceGraph.query = New-ResStatusListKustoQuery-B -ResTypeDisplayName $ResTypeList[$NumberType] -MonObj $MonObj -ErrorAction Stop
                $ResListChartObj.targets[1].subscriptions = @($MonObj.GetActiveSubscriptionIDs())

                #  $UploadeMetricsDashboardInfoHash[$ResTypeList[$NumberType]].url 
                #  return string like
                #      "/d/2TwvbarVk/application-service-metrics"

                $ResListChartObj.fieldConfig.overrides[2].properties[-1].value[1].url = 
                   "$($MonObj.Config.GetGrafanaURL())" + 
                   $UploadeMetricsDashboardInfoHash[$ResTypeList[$NumberType]].url + 
                   '?var-ds=${ds}&${env:queryparam}&${rg:queryparam}&var-rt=${__data.fields.RawResourceType}&var-rn=${__data.fields.name}&from=now-30m&to=now'

                $ResListChartObj.fieldConfig.overrides[0].properties[0].value[0].url = 
                   "$($MonObj.Config.GetGrafanaURL())" +
                   "/d/`${__dashboard.uid}" +
                   '?var-ds=${ds}&${env:queryparam}&${rg:queryparam}&var-rt=${__data.fields.RawResourceType}&var-rn=${__data.fields.name}'    
    
                $DashboardTemplateObj.panels += $ResListChartObj
                Write-Host "[    OK] Adding '$($ResTypeList[$NumberType])' chart is successful"
                $Loger.OutSummaryLineCSV("[    OK]; Adding '$($ResTypeList[$NumberType])' chart successfully completed to dashboard")

                $NumberType++
                if($NumberType -ge $ResTypeList.Count){ break GetOut; }
                $x += $WidthChart
            }
            $y += $HeightChart
        }

        # Adding "Data Source" variable $ds
        $i = 0
        for(;$DashboardTemplateObj.templating.list[$i].label -ne "DataSource";$i++){}
        $DashboardTemplateObj.templating.list[$i].regex = "/$($MonObj.Config.GetDataSources())/"
        $DashboardTemplateObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$true; text=@($MonObj.Config.GetDataSources())[0]; value=@($MonObj.Config.GetDataSources())[0]})

        $Loger.OutSummaryLineCSV("[    OK]; Setting `"Data Source`" variable successfully completed to dashboard")

        # Adding "Environment" variable $env
        $i = 0
        for(;$DashboardTemplateObj.templating.list[$i].label -ne "Environment";$i++){}
        $DashboardTemplateObj.templating.list[$i].query = $MonObj.Config.GetEnvPageNames() -join ", "
        $DashboardTemplateObj.templating.list[$i].options = @( @($MonObj.Config.GetEnvPageNames()) | %{ new-object psobject -Property ([ordered]@{ selected=$false; text=$_; value=$_}) } )
        $DashboardTemplateObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$false; text=@($MonObj.Config.GetEnvPageNames())[0]; value=@($MonObj.Config.GetEnvPageNames())[0]})

        $Loger.OutSummaryLineCSV("[    OK]; Setting `"Environment`" variable successfully completed to dashboard")

        # Adding "Resource Group" variable $rg
        $i = 0
        for(;$DashboardTemplateObj.templating.list[$i].label -ne "Resource Group";$i++){}
        $DashboardTemplateObj.templating.list[$i].query.azureLogAnalytics.query = New-variableRgKustoQuery -MonObj $MonObj
        $DashboardTemplateObj.templating.list[$i].query.azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()

        #$DashboardTemplateObj.templating.list[$i].options = @( $MonObj.Config.GetResourceGroups().ToLower() | %{ new-object psobject -Property ([ordered]@{ selected=$false; text=$_; value=$_}) } )
        #$DashboardTemplateObj.templating.list[$i].options[0].selected = $true
        #$DashboardTemplateObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$true; text=@($MonObj.Config.GetResourceGroups().ToLower())[0]; value=@($MonObj.Config.GetResourceGroups().ToLower())[0]})

        $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Group`" variable successfully completed to dashboard")

        # Adding "Resource Type" variable $rt
        $i = 0
        for(;$DashboardTemplateObj.templating.list[$i].label -ne "Resource Type";$i++){}
        $TypeTable = Get-TypeTable -MonObj $MonObj -ErrorAction Stop
        $DashboardTemplateObj.templating.list[$i].query = ( $MonObj.GetArrayOfAllResourceTypes() |  %{ $TypeTable[$_] } | %{ "$($_.ResTypeName) : $($_.ResTypeRegEx)" } ) -join ","
        $DashboardTemplateObj.templating.list[$i].options = @( $MonObj.GetArrayOfAllResourceTypes() | %{ $TypeTable[$_] } | 
                                                                                                          %{ new-object psobject -Property ([ordered]@{ selected=$false; text=$_.ResTypeName; value=$_.ResTypeRegEx}) } )
        $DashboardTemplateObj.templating.list[$i].options[0].selected = $true
        $DashboardTemplateObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$true; text=$TypeTable[@($MonObj.GetArrayOfAllResourceTypes())[0]].ResTypeName; value=$TypeTable[@($MonObj.GetArrayOfAllResourceTypes())[0]].ResTypeRegEx})

        $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Type`" variable successfully completed to dashboard")

        # Adding "Resource name" variable $rn
        $i = 0
        for(;$DashboardTemplateObj.templating.list[$i].label -ne "Resource Name";$i++){}
        $DashboardTemplateObj.templating.list[$i].query.azureResourceGraph.query = New-variableRnKustoQuery -MonObj $MonObj
        $DashboardTemplateObj.templating.list[$i].query.subscriptions = @($MonObj.GetActiveSubscriptionIDs())
        $DashboardTemplateObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$false; text=""; value=""})

        $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Name`" variable successfully completed to dashboard")

        # Set Cross Link to Related Projects
        if($MonObj.Config.GetRelatedProjectIDs().count -eq 0)
        {
            # Remove "Go to Application" button            
            $item = $DashboardTemplateObj.links[0]
            $DashboardTemplateObj.links = @($item)
        }
        else
        {
            $DashboardTemplateObj.links[1].tags = @( $MonObj.Config.GetRelatedProjectIDs() | %{"Main-ResStatuses-$($_)"} )
        }

        # Set Link to Monitoring Dashboard
        $DashboardTemplateObj.links[0].tags = @("MetricsDashboard-$($MonObj.Config.GetProjectID())") 

        # Set Dashboard Title
        $DashboardTemplateObj.title = "Resource statuses of project: " + $MonObj.Config.GetProjectDisplayName()
        
        # Adding Tags
        $DashboardTemplateObj.tags = @("Main-ResStatuses-$($MonObj.Config.GetProjectID())")

        # Saving Dasboard
        if($OutputFolder)
        {
            $DashboardTemplateObj | ConvertTo-Json -Depth 100 -ErrorAction Stop | Set-Content -Path "$OutputFolder\dashboard.json" -ErrorAction Stop

            Write-Host "[    OK] Saving 'Alert status of resource' dashboard to `"$OutputFolder\dashboard.json`" file successfully completed"
            $Loger.OutSummaryLineCSV("[    OK]; Saving 'Alert status of resource' dashboard to `"$OutputFolder\dashboard.json`" file successfully completed")
        }

        # Upload Dashboard To Grafana
        Uploade-DashboardToFolder -MonObj $MonObj -Dashboard $DashboardTemplateObj -ErrorAction Stop | Out-Null
        Write-Host "[    OK] Uploading 'Alert status of resource' dashboard to `"$($MonObj.Config.GetGrafanaURL())`" successfully completed"
        $Loger.OutSummaryLineCSV("[    OK]; Uploading 'Alert status of resource' dashboard to `"$($MonObj.Config.GetGrafanaURL())`" successfully completed")
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Create-StatusDashboard(): $($_.Exception.Message) ", $_.Exception))
    }
}

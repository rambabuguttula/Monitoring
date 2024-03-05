. $PSScriptRoot\.\LogHelper.ps1
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

function New-variableRnMetricKustoQuery
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $ProjectID = $MonObj.Config.GetProjectID()
        # $ResGrList = ($MonObj.Config.GetResourceGroups().ToLower() | %{"`"$_`"" } ) -join ","

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
| where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ (`$rg)
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

function New-MetricKustoQuery-A
{
    [cmdletBinding()] Param([string]$MonObj, $MetricItem)

    $QueryMetric =
"AzureMetrics
| where `$__timeFilter(TimeGenerated)
| extend ResourceId = tolower(ResourceId)
| where extract(@`"/resourcegroups/([^/]+)/`", 1, ResourceId) in~ (`$rg)
| where ResourceId matches regex '$($MetricItem.ResTypeRegEx)'
| extend FullResName = iff(indexof('`$rn','queueservices') != -1, '`$rn', iff(indexof('`$rn','blobservices') != -1, '`$rn',
                       iff(indexof('`$rn','fileservices') != -1, '`$rn', iff(indexof('`$rn','tableservices') != -1, '`$rn',
                       iff(indexof('`$rn','/') != -1, extract(tolower(strcat('.+/(', substring('`$rn', 0, indexof('`$rn','/')),'/[^/]+/', substring('`$rn', indexof('`$rn','/') + 1), ')$')), 1, ResourceId),'`$rn')))))
| where isnotempty(FullResName)
| where ResourceId endswith FullResName
| where MetricName == '$($MetricItem.QueryMetricName)'
| extend currentValue = iff('$($MetricItem.MetricMeasureColumn)' == 'Average', Average,
                        iff('$($MetricItem.MetricMeasureColumn)' == 'Total', Total,
                        iff('$($MetricItem.MetricMeasureColumn)' == 'Maximum', Maximum,
                        iff('$($MetricItem.MetricMeasureColumn)' == 'Minimum', Minimum, Count))))
| project TimeGenerated, currentValue
| sort by TimeGenerated asc 
"
    $QueryMetric

}

function Create-MetricsDashboard
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $OutputFolder, $Loger)

    $Loger.OutSummaryLineCSV("--------; ----------------------------- Creating Metrics Dashboards ------------------------------------")
    Write-Host "-------- ----------------------------- Creating Metrics Dashboards ------------------------------------"

    try
    {
        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop
        $MetricObjects = Get-MetricsObjects -MonObj $MonObj -ErrorAction Stop
        $TypeTable = Get-TypeTable -MonObj $MonObj -ErrorAction Stop
        $UnitsTable = Get-UnitsTable -MonObj $MonObj -ErrorAction Stop

        $MetricsDashboardTemplateFile = "$PSScriptRoot\..\Grafana Template\Metrics\MetricsDashboardTemplate.json"

        $UploadeInfoHash = @{}

        # Подключенные типы к Лог Аналитике
        $MonObj.GetArrayOfAllResourceTypes() | %{

            $ResType = $_

            $MetricsDashboardObj = Get-Content -Path $MetricsDashboardTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $MetricsDashboardObj.panels = @()

            $MetricsOnlySpecificType = $MetricObjects | ?{ $_.ResTypeDisplayName -eq $ResType }

            if($MetricsOnlySpecificType.Count -eq 0)
            {
                Write-Host -ForegroundColor Red "[FAIL!!] Failure to create the '$ResType' dashboard. There aren't any enabled metrics for the '$ResType' resource type."
                $Loger.OutSummaryLineCSV("[FAIL!!]; Failure to create the '$ResType' dashboard. There aren't any enabled metrics for the '$ResType' resource type.")
                return;
            }

            $CountCharts = $MetricsOnlySpecificType.Count
            $WidthChart = 12
            $HeightChart = 8
            $WidthDashboard = 24
            $CountChartsInLine = [math]::Truncate($WidthDashboard/$WidthChart)
            $CountLine = [math]::Ceiling($CountCharts/$CountChartsInLine)

            $NumberMetrics = 0

            for (($i = 0), ($y = 0); $i -lt $CountLine; $i++)
            {
                for (($j = 0), ($x = 0); $j -lt $CountChartsInLine; $j++)
                {

                    $MetricChartTemplateFile = "$PSScriptRoot\..\Grafana Template\Metrics\MetricChartTemplate.json"
                    $MetricChartObj = Get-Content -Path $MetricChartTemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $MetricChartObj.title = $MetricsOnlySpecificType[$NumberMetrics].QueryMetricDisplayName
                    $MetricChartObj.description = "The amount of $($MetricsOnlySpecificType[$NumberMetrics].QueryMetricDisplayName) consumed by the resource, in $($MetricsOnlySpecificType[$NumberMetrics].Unit)"
                    $MetricChartObj.gridPos.h=$HeightChart
                    $MetricChartObj.gridPos.w=$WidthChart
                    $MetricChartObj.gridPos.x=$x
                    $MetricChartObj.gridPos.y=$y

                    $MetricChartObj.targets[0].azureLogAnalytics.query = New-MetricKustoQuery-A -MonObj $MonObj -MetricItem  $MetricsOnlySpecificType[$NumberMetrics] -ErrorAction Stop
                    $MetricChartObj.targets[0].azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()
                    $MetricChartObj.fieldConfig.defaults.unit = $UnitsTable[$MetricsOnlySpecificType[$NumberMetrics].Unit]."Unit Grafana"

                    if($MetricsOnlySpecificType[$NumberMetrics].Operator -eq "GreaterThan"  -or $MetricsOnlySpecificType[$NumberMetrics].Operator -eq "GreaterThanOrEqual")
                    {
                        $step_i = 0
                        for(;$MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color -ne "yellow";$step_i++){}
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].value = [int64]$MetricsOnlySpecificType[$NumberMetrics].WarningThreshold

                        $step_i = 0
                        for(;$MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color -ne "dark-red";$step_i++){}
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].value = [int64]$MetricsOnlySpecificType[$NumberMetrics].ErrorThreshold
                    }
                    else
                    {
                        $step_i = 0
                        for(;$MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color -ne "dark-red";$step_i++){}
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color = "green"
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].value = [int64]$MetricsOnlySpecificType[$NumberMetrics].ErrorThreshold

                        $step_i = 0
                        for(;$MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].value -ne $null;$step_i++){}
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color = "dark-red"

                        $step_i = 0
                        for(;$MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].color -ne "yellow";$step_i++){}
                        $MetricChartObj.fieldConfig.defaults.thresholds.steps[$step_i].value = [int64]$MetricsOnlySpecificType[$NumberMetrics].WarningThreshold

                    }


                    $MetricsDashboardObj.panels += $MetricChartObj
                    Write-Host "[    OK] ----- Adding '$($MetricsOnlySpecificType[$NumberMetrics].QueryMetricDisplayName)' chart is successful."
                    $Loger.OutSummaryLineCSV("[    OK]; ----- Adding '$($MetricsOnlySpecificType[$NumberMetrics].QueryMetricDisplayName)' chart successfully completed to dashboard")

                    $NumberMetrics++
                    if($NumberMetrics -ge $MetricsOnlySpecificType.Count){ break; }
                    $x += $WidthChart
                }
                $y += $HeightChart
            }
        
            # Adding "Data Source" variable $ds
            $i = 0
            for(;$MetricsDashboardObj.templating.list[$i].label -ne "Data Source";$i++){}
            $MetricsDashboardObj.templating.list[$i].regex = "/$($MonObj.Config.GetDataSources())/"
            $MetricsDashboardObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$true; text=$MonObj.Config.GetDataSources(); value=$MonObj.Config.GetDataSources()})

            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Data Source`" variable successfully completed to dashboard")

            # Adding "Environment" variable $env
            $i = 0
            for(;$MetricsDashboardObj.templating.list[$i].label -ne "Environment";$i++){}
            $MetricsDashboardObj.templating.list[$i].query = $MonObj.Config.GetEnvPageNames() -join ", "
            $MetricsDashboardObj.templating.list[$i].options = @( @($MonObj.Config.GetEnvPageNames()) | %{ new-object psobject -Property ([ordered]@{ selected=$false; text=$_; value=$_}) } )
            $MetricsDashboardObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$false; text=@($MonObj.Config.GetEnvPageNames())[0]; value=@($MonObj.Config.GetEnvPageNames())[0]})

            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Environment`" variable successfully completed to dashboard")

            # Adding "Resource Group" variable $rg
            $i = 0
            for(;$MetricsDashboardObj.templating.list[$i].label -ne "Resource Group";$i++){}
            ### $MetricsDashboardObj.templating.list[$i].query = $MonObj.Config.GetResourceGroups() -join ","
            $MetricsDashboardObj.templating.list[$i].query.azureLogAnalytics.query = New-variableRgKustoQuery -MonObj $MonObj
            $MetricsDashboardObj.templating.list[$i].query.azureLogAnalytics.resource = $MonObj.Config.GetWorkspaceId()

            # $MetricsDashboardObj.templating.list[$i].options = @( $MonObj.Config.GetResourceGroups() | %{ new-object psobject -Property ([ordered]@{ selected=$false; text=$_; value=$_}) } )
            # $MetricsDashboardObj.templating.list[$i].options[0].selected = $true
            # $MetricsDashboardObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$true; text=@($MonObj.Config.GetResourceGroups())[0]; value=@($MonObj.Config.GetResourceGroups())[0]})

            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Group`" variable successfully completed to dashboard")

            # Adding "Resource Type" variable $rt
            $i = 0
            for(;$MetricsDashboardObj.templating.list[$i].label -ne "Resource Type";$i++){}
            $TypeTable = Get-TypeTable -MonObj $MonObj -ErrorAction Stop
            $MetricsDashboardObj.templating.list[$i].query = "$($TypeTable[$ResType].ResTypeName) : $($TypeTable[$ResType].ResTypeRegEx)"
            $MetricsDashboardObj.templating.list[$i].options = @( new-object psobject -Property ([ordered]@{ selected=$true; text=$TypeTable[$ResType].ResTypeName; value=$TypeTable[$ResType].ResTypeRegEx}) )
            $MetricsDashboardObj.templating.list[$i].current = new-object psobject -Property ([ordered]@{ selected=$true; text=$TypeTable[$ResType].ResTypeName; value=$TypeTable[$ResType].ResTypeRegEx})

            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Type`" variable successfully completed to dashboard")

            # Adding "Resource name" variable $rn
            $i = 0
            for(;$MetricsDashboardObj.templating.list[$i].label -ne "Resource Name";$i++){}
            $MetricsDashboardObj.templating.list[$i].query.azureResourceGraph.query = New-variableRnMetricKustoQuery -MonObj $MonObj
            $MetricsDashboardObj.templating.list[$i].query.subscriptions = @($MonObj.GetActiveSubscriptionIDs())
            $MetricsDashboardObj.templating.list[$i].current =  new-object psobject -Property ([ordered]@{ selected=$false; text=""; value=""})

            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Resource Name`" variable successfully completed to dashboard")

            # Adding Tags
            $MetricsDashboardObj.tags = @("MetricsDashboard-$($MonObj.Config.GetProjectID())")
            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Tags`" successfully completed to dashboard")

            # Adding Title
            $MetricsDashboardObj.title = "$ResType metrics"
            $Loger.OutSummaryLineCSV("[    OK]; Setting `"Title`" successfully completed to dashboard")

            # Saving Dasboard
            if($OutputFolder)
            {
                $MetricsDashboardObj | ConvertTo-Json -Depth 100 -ErrorAction Stop | Set-Content -Path "$OutputFolder\metric_$($ResType)_dashboard.json" -ErrorAction Stop

                Write-Host "[    OK] Saving '$ResType metrics' dashboard to `"$OutputFolder\metric_$($ResType)_dashboard.json`" file successfully completed"
                $Loger.OutSummaryLineCSV("[    OK]; Saving '$ResType metrics' dashboard to `"$OutputFolder\metric_$($ResType)_dashboard.json`" file successfully completed")
            }

            # Upload Dashboard To Grafana
            $UploadeInfo = Uploade-DashboardToFolder -MonObj $MonObj -Dashboard $MetricsDashboardObj -ErrorAction Stop
            Write-Host "[    OK] Uploading '$ResType metrics' dashboard to `"$($MonObj.Config.GetGrafanaURL())`" successfully completed"
            $Loger.OutSummaryLineCSV("[    OK]; Uploading '$ResType metrics' dashboard to `"$($MonObj.Config.GetGrafanaURL())`" successfully completed")
            $UploadeInfoHash[$ResType] = $UploadeInfo

        }

        $UploadeInfoHash
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Create-MetricsDashboard(): $($_.Exception.Message) ", $_.Exception))
    }
}

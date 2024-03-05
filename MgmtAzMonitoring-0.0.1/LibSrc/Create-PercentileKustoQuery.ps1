. $PSScriptRoot\.\LogHelper.ps1  
. $PSScriptRoot\.\Read-ExcelTemplate.ps1
. $PSScriptRoot\.\Create-MetricsObjects.ps1 

function Get-PercentileKustoQuery
{
    [cmdletBinding()] Param($MonObj, $PercentileWarning, $PercentileError, $Loger)

    try
    {
        $Query = 
"let ResourcesByType = (RG_arg:string,  RT_arg:string)
{
    AzureMetrics 
    | where TimeGenerated > now() - 120d
    | extend ResourceId = tolower(ResourceId)
    | where tolower(ResourceGroup) in (parse_json(RG_arg))
    | where ResourceId matches regex RT_arg
};
let PercentileMetric = (RG_arg:string, RT_Name_arg:string, RT_arg:string, MetricName_arg:string, ThresholdFieldName_arg:string, 
                        PercentileWarning_arg:long, PercentileError_arg:long)
{
    ResourcesByType(RG_arg,  RT_arg)
    | where MetricName == MetricName_arg
    | extend currentValue = iff(ThresholdFieldName_arg == 'Average', Average,
                            iff(ThresholdFieldName_arg == 'Total', Total,
                            iff(ThresholdFieldName_arg == 'Maximum', Maximum,
                            iff(ThresholdFieldName_arg == 'Minimum', Minimum, Count))))
    | summarize PercentileWarning = percentile(currentValue, PercentileWarning_arg), 
                PercentileError = percentile(currentValue, PercentileError_arg) by ResourceId
    | summarize AvgPercentileWarning=round(avg(PercentileWarning)), AvgPercentileError = round(avg(PercentileError))
    | extend MetricName = MetricName_arg
    | extend PercentileValue = strcat(tostring(PercentileWarning_arg),'x',tostring(PercentileError_arg))
    | extend TypeResource = RT_Name_arg
    | project TypeResource, MetricName, PercentileValue, AvgPercentileError, AvgPercentileWarning
};"
        
        $MetricObjects = Get-MetricsObjects -MonObj $MonObj -ErrorAction Stop

        if($MetricObjects.Count -gt 0)
        {
            $Query += "PercentileMetric("
            $Query += "`"['$(($MonObj.Config.EnvPageProd.GetResourceGroupsPerSubID().Values | %{ $_ }) -join "','")']`","
            $Query += "`"$($MetricObjects[0].ResTypeDisplayName)`","
            $Query += "`"$($MetricObjects[0].ResTypeRegEx)`","
            $Query += "`"$($MetricObjects[0].QueryMetricName)`","
            $Query += "`"$($MetricObjects[0].MetricMeasureColumn)`","
            $Query += "`"$PercentileWarning`","
            $Query += "`"$PercentileError`")`n"

            Write-Host "[    OK] ----- Adding Percentile for `"$($MetricObjects[0].QueryMetricName)`" metric to '$($MetricObjects[0].ResTypeDisplayName)'"
            $Loger.OutSummaryLineCSV("[    OK]; ----- Adding Percentile for `"$($MetricObjects[0].QueryMetricName)`" metric to '$($MetricObjects[0].ResTypeDisplayName)'")
        }

        if($MetricObjects.Count -gt 1)
        {
            $MetricObjects[1..($MetricObjects.Count-1)] | %{

                $Query += "| union PercentileMetric("
                $Query += "`"['$(($MonObj.Config.EnvPageProd.GetResourceGroupsPerSubID().Values | %{ $_ }) -join "','")']`","
                $Query += "`"$($_.ResTypeDisplayName)`","
                $Query += "`"$($_.ResTypeRegEx)`","
                $Query += "`"$($_.QueryMetricName)`","
                $Query += "`"$($_.MetricMeasureColumn)`","
                $Query += "`"$PercentileWarning`","
                $Query += "`"$PercentileError`")`n"

                Write-Host "[    OK] ----- Adding Percentile for `"$($_.QueryMetricName)`" metric to '$($_.ResTypeDisplayName)'"
                $Loger.OutSummaryLineCSV("[    OK]; ----- Adding Percentile for `"$($_.QueryMetricName)`" metric to '$($_.ResTypeDisplayName)'")
            }
        }

        $Query
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-PercentileKustoQuery(): $($_.Exception.Message) ", $_.Exception))
    }
}


function Create-PercentileKustoQuery
{
    [cmdletBinding()] Param([string] $ExcelFileName, $PercentileWarning, $PercentileError, [string] $OutputFolder, [string] $LogFolder)
    
    $LogFolder = Resolve-Path $LogFolder -ErrorAction Stop
    $DataStr = "$(Get-Date -Format "dd.MM.yyyy-HH.mm.ss")"

    $LogFile = Join-Path -Path $LogFolder -ChildPath "CreatingPercentileKustoQuery-$DataStr.log" -ErrorAction Stop
    $ErrFile = Join-Path -Path $LogFolder -ChildPath "CreatingPercentileKustoQuery-$DataStr.err" -ErrorAction Stop

    $Loger = New-Logger -ErrorLogFile $ErrFile -SummaryCSVFile $LogFile -SummaryCSVHeader "Status; Description"

    $Loger.OutSummaryLineCSV("--------; ----------------------------- Creating Percentile KustoQuery ------------------------------------")
    Write-Host "-------- ----------------------------- Creating Percentile KustoQuery ------------------------------------" 

    try
    {        
        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop
        $KustoQuery = Get-PercentileKustoQuery -MonObj $MonObj -PercentileWarning $PercentileWarning -PercentileError $PercentileError -Loger $Loger -ErrorAction Stop

        $Loger.OutSummaryLineCSV("--------; ----------------------------- Running Percentile KustoQuery ------------------------------------")
        Write-Host "-------- ----------------------------- Running Percentile KustoQuery ------------------------------------"

        $LAWorkspace = Get-AzOperationalInsightsWorkspace -Name "$($MonObj.Config.GetWorkspaceName())" -ResourceGroupName "$($MonObj.Config.GetWorkspaceRg())"
        $queryResults = Invoke-AzOperationalInsightsQuery -Workspace $LAWorkspace -Query $KustoQuery

        # Saving Dasboard
        if($OutputFolder)
        {
            $Loger.OutSummaryLineCSV("--------; ----------------------------- Save Results of runnig Percentile KustoQuery ------------------------------------")
            Write-Host "-------- ----------------------------- Save Results of runnig Percentile KustoQuery  ------------------------------------"
            
            $queryResults.Results | Export-Excel -Path "$OutputFolder\ResultsKustoQuery.xlsx" -Show

            $KustoQuery | Set-Content -Path "$OutputFolder\KustoQuery.json" -ErrorAction Stop

            Write-Host "[    OK] Saving Percentile KustoQuery to `"$OutputFolder\KustoQuery.json`" file successfully completed"
            $Loger.OutSummaryLineCSV("[    OK]; Saving Percentile KustoQuery to `"$OutputFolder\KustoQuery.json`" file successfully completed")
        }
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Create-PercentileKustoQuery(): $($_.Exception.Message) ", $_.Exception))
    }
}

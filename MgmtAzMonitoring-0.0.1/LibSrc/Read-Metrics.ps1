function GetMetrics($ExcelFileName)
{
    $Metrics = Import-Excel $ExcelFileName -StartRow 4 -WorksheetName "Metrics" -ErrorAction Stop
 
    if(($Metrics| gm | ?{$_.Name -eq "Enable" -or 
                         $_.Name -eq "EvaluationFrequency" -or 
                         $_.Name -eq "FailingPeriodMinFailingPeriodsToAlert" -or 
                         $_.Name -eq "FailingPeriodNumberOfEvaluationPeriod" -or 
                         $_.Name -eq "MetricMeasureColumn" -or
                         $_.Name -eq "Operator" -or
                         $_.Name -eq "QueryMetricDisplayName" -or
                         $_.Name -eq "QueryMetricName" -or
                         $_.Name -eq "ResTypeDisplayName" -or
                         $_.Name -eq "Severity" -or
                         $_.Name -eq "ErrorThreshold" -or
                         $_.Name -eq "WarningThreshold" -or
                         $_.Name -eq "TimeAggregation" -or
                         $_.Name -eq "Unit" -or
                         $_.Name -eq "WindowSize"
                         }).Count -eq 15)
    {
        $Metrics | ?{$_.Enable -eq $true}
    }
    else
    {
        throw "Incorrect Excel format. 'Metrics' Excel spreadsheet should containin: Row(4) Column(1) - 'Enable'; 
                                                                                     Row(1) Column(2) - 'ResTypeDisplayName'; 
                                                                                     Row(1) Column(3) - 'Severity'; 
                                                                                     Row(1) Column(4) - 'QueryMetricName'; 
                                                                                     Row(1) Column(5) - 'QueryMetricDisplayName';
                                                                                     Row(1) Column(6) - 'MetricMeasureColumn';
                                                                                     Row(1) Column(7) - 'TimeAggregation';
                                                                                     Row(1) Column(8) - 'WindowSize';
                                                                                     Row(1) Column(9) - 'Unit';
                                                                                     Row(1) Column(10) - 'Operator';
                                                                                     Row(1) Column(11) - 'ErrorThreshold';
                                                                                     Row(1) Column(12) - 'WarningThreshold';
                                                                                     Row(1) Column(13) - 'EvaluationFrequency';
                                                                                     Row(1) Column(14) - 'FailingPeriodMinFailingPeriodsToAlert';
                                                                                     Row(1) Column(15) - 'FailingPeriodNumberOfEvaluationPeriod';" 
    }
}
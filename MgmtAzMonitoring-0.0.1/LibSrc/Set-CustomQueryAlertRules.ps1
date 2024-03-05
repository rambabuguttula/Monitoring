. $PSScriptRoot\.\LogHelper.ps1
. $PSScriptRoot\.\Read-ExcelTemplate.ps1
. $PSScriptRoot\.\Create-MetricsObjects.ps1

function Get-AlertRuleName
{
    [cmdletBinding()] Param($MetricsItem)

    "$($MetricsItem.ResTypeName)$($MetricsItem.QueryMetricName)$($MetricsItem.Severity)"
}

function Get-AlertRuleShortDisplayName
{
    [cmdletBinding()] Param($MetricsItem)

    "$($MetricsItem.ResTypeDisplayName) $($MetricsItem.QueryMetricDisplayName) is $($MetricsItem.Severity.ToLower())"
}

function Get-AlertRuleQuery
{
    [cmdletBinding()] Param($MetricsItem)
        
    "AzureMetrics | extend ResourceId = tolower(ResourceId) | where ResourceId matches regex '$($MetricsItem.ResTypeRegEx)' | where MetricName == '$($MetricsItem.QueryMetricName)' "
}

function Get-AlertRuleDescription
{
    [cmdletBinding()] Param($MetricsItem)

    $MI = $MetricsItem

    $Threshold = $MI.ErrorThreshold
    if($MI.Unit -eq "Bytes"){ $Threshold = $Threshold/1024/1024 }


    "$($MI.ResTypeDisplayName) $($MI.QueryMetricDisplayName) has increased and exceeds the threshold value ($($MI.OperatorText) $Threshold $($MI.Unit) for the last $($MI.EvaluationFrequency) mins)"
}

function Create-ActionGroup
{
    [cmdletBinding()] Param([string] $ProjectID, [string] $ResourceGroupName, [string]$EmailAddress)

    $NameAG = "$ProjectID-AutoMgmtActionGroup"
    $ShortProjectID = $ProjectID -replace "-"
    $NameShortAG = "$($ShortProjectID.Substring(0,[math]::Min(9,$ShortProjectID.Length)))AG"

    #$ResAG_Id = (Get-AzActionGroup -Name $NameAG -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Id

    #if( $ResAG_Id -eq $null )
    #{
        $email = New-AzActionGroupReceiver -Name 'user' -EmailReceiver -EmailAddress $EmailAddress -ErrorAction Stop -WarningAction SilentlyContinue

        $ResAG_Id = (Set-AzActionGroup -Name $NameAG -ResourceGroupName $ResourceGroupName -ShortName $NameShortAG -Receiver $email -ErrorAction Stop -WarningAction SilentlyContinue).Id
    #}
    $ResAG_Id
}

function Set-DimensionSplit
{
    [cmdletBinding()] Param($ResID)

    $AlertRule = Invoke-AzRestMethod -Path "$($ResID)?api-version=2021-08-01" -Method GET
    if($AlertRule.StatusCode -eq 200)
    {
        $AlertRuleObj = $AlertRule.Content | ConvertFrom-Json
        $AlertRuleObj.properties.criteria.allOf[0] = $AlertRuleObj.properties.criteria.allOf[0] | 
                                                      Add-Member -NotePropertyName resourceIdColumn `
                                                                 -NotePropertyValue "ResourceId" `
                                                                 -PassThru -ErrorAction Stop -Force

        $AlertRuleObj.systemData = $null
        $AlertRuleObj.PSObject.Properties.Remove('systemData')

        $AlertRuleJson = $AlertRuleObj | ConvertTo-Json -Depth 100      

        $UpdatedAlerRule = Invoke-AzRestMethod -Path "$($ResID)?api-version=2021-08-01" -Method PUT -Payload $AlertRuleJson

        if($UpdatedAlerRule.StatusCode -ne 200) { throw "Error in Set-DimensionSplit: $(($UpdatedAlerRule.Content | ConvertFrom-Json).error.message)" }
    }
    else
    {
        throw "Error in Set-DimensionSplit: Alert Rule '$ResID' not found"
    }
}

function Create-AlertRuls
{
    [cmdletBinding()] Param($MonObj, $MetricsItem, [string] $AlertRulsResourceGroup, [string] $ActionGroupResourceId)

    try
    {

        $dimension = New-AzScheduledQueryRuleDimensionObject -Name "ResourceId" -Operator Include -Value * -ErrorAction Stop

        $condition = New-AzScheduledQueryRuleConditionObject -Dimension $dimension `
                                                                -Query "$( Get-AlertRuleQuery -MetricsItem $MetricsItem )" `
                                                                -TimeAggregation $MetricsItem.TimeAggregation `
                                                                -MetricMeasureColumn $MetricsItem.MetricMeasureColumn `
                                                                -Operator $MetricsItem.Operator `
                                                                -Threshold $MetricsItem.ErrorThreshold `
                                                                -FailingPeriodNumberOfEvaluationPeriod $MetricsItem.FailingPeriodNumberOfEvaluationPeriod `
                                                                -FailingPeriodMinFailingPeriodsToAlert $MetricsItem.FailingPeriodMinFailingPeriodsToAlert `
                                                                -ErrorAction Stop

        $res  = New-AzScheduledQueryRule -Name "$( Get-AlertRuleName -MetricsItem $MetricsItem )" `
                                            -ResourceGroupName $AlertRulsResourceGroup `
                                            -Location eastus `
                                            -DisplayName "$( Get-AlertRuleShortDisplayName -MetricsItem $MetricsItem )" `
                                            -Scope $MonObj.Config.GetWorkspaceId() `
                                            -Severity $([Severity]::"$($MetricsItem.Severity)".value__) `
                                            -WindowSize ([System.TimeSpan]::New(0,$MetricsItem.WindowSize,0)) `
                                            -EvaluationFrequency ([System.TimeSpan]::New(0,$MetricsItem.EvaluationFrequency,0)) `
                                            -Description "$( Get-AlertRuleDescription -MetricsItem $MetricsItem )" `
                                            -CriterionAllOf $condition `
                                            -ActionGroupResourceId $ActionGroupResourceId `
                                            -ErrorAction Stop

        Update-AzTag -ResourceId $res.Id -Tag  @{"MONITORING-$($MonObj.Config.GetProjectID())"="ALERTRULE";} -Operation Merge -ErrorAction Stop | Out-Null

        Set-DimensionSplit -ResID $res.Id -ErrorAction Stop

    }
    catch
    {
         Write-Error -Exception ([Exception]::new("Error in Create-AlertRuls(): $($_.Exception.Message) ", $_.Exception))
    }
}



function Set-CustomQueryAlertRules
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $LogFolder)

    try
    {
        $LogFolder = Resolve-Path $LogFolder -ErrorAction Stop
        $DataStr = "$(Get-Date -Format "dd.MM.yyyy-HH.mm.ss")"

        $LogFile = Join-Path -Path $LogFolder -ChildPath "CreatingAlertRules-$DataStr.log"
        $ErrFile = Join-Path -Path $LogFolder -ChildPath "CreatingAlertRules-$DataStr.err"

        $Loger = New-Logger -ErrorLogFile $ErrFile -SummaryCSVFile $LogFile -SummaryCSVHeader "Status; Description"    
        
        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop

        if( $MonObj.Config.GetProjectID() -eq "")
        {
            throw "Excel file contain empty ProjectID in 'Monitoring Config' Excel spreadsheet in Row(1) Column(2)"
        }

        if( $MonObj.Config.GetSubscriptionID() -eq "")
        {
            throw "Excel file contain empty SubscriptionID in 'Monitoring Config' Excel spreadsheet in Row(2) Column(2)"
        }

        if( $MonObj.Config.GetWorkspaceId() -eq "")
        {
            throw "Excel file contain empty WorkspaceId in 'Monitoring Config' Excel spreadsheet in Row(3) Column(2)"
        }

        if( $MonObj.PredefinedConstants.GetAllPossibleResTypes().Count -eq 0 )
        {
            throw "Excel file contain empty list Resource Types in 'ServicePage' Excel spreadsheet in Row(2) Column(1)"
        }

        Write-Host "`n------------------------------------ Alert Rules ---------------------------------------------"

        Set-AzContext -Subscription $MonObj.Config.GetSubscriptionID() -ErrorAction Stop | Out-String | Out-Null
        Write-Host ""

        $MetricObjects = Get-MetricsObjects -MonObj $MonObj -ErrorAction Stop

        $AlertRulsResourceGroup = $MonObj.Config.GetWorkspaceRg()


        enum Severity { Critical = 0; Error = 1; Warning = 2; Informational = 3; Verbose = 4 }

        $ActionGroupResourceId = Create-ActionGroup -ProjectID $MonObj.Config.GetProjectID() -ResourceGroupName  $AlertRulsResourceGroup -EmailAddress $MonObj.Config.GetDLlist()

        $Loger.OutSummaryLineCSV("[    OK]; ------------------------------------ ActionGroup ---------------------------------------------------")
        $Loger.OutSummaryLineCSV("[    OK]; Creating/getting '$ActionGroupResourceId' Action Group is successful")
        $Loger.OutSummaryLineCSV("[    OK]; ---------------------------- Creating/Updating Alert Rules -----------------------------------------")

        
        $ListEnabledTypes = $MonObj.Config.GetArrayOfResourceTypes()
        $ListUpdatedAlertRules = $MetricObjects | ?{$_} | ?{$_.ResTypeDisplayName -in $ListEnabledTypes } | %{ Get-AlertRuleName -MetricsItem $_ }                
        $ListExistAlertRules = Get-AzScheduledQueryRule -ResourceGroupName $AlertRulsResourceGroup | ?{ $_.Tag.ToJsonString() -eq (@{"MONITORING-$ProjectID"="ALERTRULE";} | ConvertTo-Json) }
        
        $ListDeletedAlertRules = $ListExistAlertRules | ?{ $_.Name  -notin $ListUpdatedAlertRules}


        $MetricObjects | ?{$_} | %{

            $MetricItem = $_

            try
            {
                Create-AlertRuls -MonObj $MonObj -MetricsItem $_  -AlertRulsResourceGroup $AlertRulsResourceGroup -ActionGroupResourceId $ActionGroupResourceId -ErrorAction Stop

                Write-Host "Creating '$(Get-AlertRuleShortDisplayName -MetricsItem $MetricItem)' alert rule successfully completed"
                $Loger.OutSummaryLineCSV("[    OK]; Creating '$(Get-AlertRuleShortDisplayName -MetricsItem $MetricItem)' alert rule successfully completed")
            }
            catch
            {
                Write-Host -ForegroundColor DarkRed "Creating '$(Get-AlertRuleShortDisplayName -MetricsItem $MetricItem)' alert rule unsuccessfully completed"
                
                $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

                $Loger.OutSummaryLineCSV("[FAIL!!]; Error creating '$(Get-AlertRuleShortDisplayName -MetricsItem $MetricItem)' alert rule")
                $Loger.OutErrorLog($_, "Error creating '$(Get-AlertRuleShortDisplayName -MetricsItem $MetricItem)' alert rule",$IsVerbose)
            }
        }

        if($ListDeletedAlertRules -ne $null)
        {
            $Loger.OutSummaryLineCSV("[    OK]; ---------------------------- Removing Alert Rules -----------------------------------------")
        }

        $ListDeletedAlertRules | ?{$_} | %{

            try
            {
                Remove-AzScheduledQueryRule -ResourceGroupName $AlertRulsResourceGroup -Name $_.Name

                Write-Host "Removing '$($_.DisplayName)' alert rule successfully completed"
                $Loger.OutSummaryLineCSV("[    OK]; Removing '$($_.DisplayName)' alert rule successfully completed")
            }
            catch
            {
                Write-Host -ForegroundColor DarkRed "Removing '$($_.DisplayName)' alert rule unsuccessfully completed"
                
                $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

                $Loger.OutSummaryLineCSV("[FAIL!!]; Error removing of '$($_.DisplayName)' alert rule")
                $Loger.OutErrorLog($_, "Error removing of '$($_.DisplayName)' alert rule",$IsVerbose)
            }
        }


    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Set-CustomQueryAlertRules(): $($_.Exception.Message) ", $_.Exception))
    }
}

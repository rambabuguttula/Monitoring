. $PSScriptRoot\.\Create-MetricsDashboard.ps1
. $PSScriptRoot\.\Create-AzureResStatusDashboard.ps1

function Create-AllDashboards
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $OutputFolder, [string] $LogFolder)

    $LogFolder = Resolve-Path $LogFolder -ErrorAction Stop
    $DataStr = "$(Get-Date -Format "dd.MM.yyyy-HH.mm.ss")"

    $LogFile = Join-Path -Path $LogFolder -ChildPath "CreatingDashboard-$DataStr.log" -ErrorAction Stop
    $ErrFile = Join-Path -Path $LogFolder -ChildPath "CreatingDashboard-$DataStr.err" -ErrorAction Stop

    $Loger = New-Logger -ErrorLogFile $ErrFile -SummaryCSVFile $LogFile -SummaryCSVHeader "Status; Description"
    
    try
    {
        $UploadeMetricsDashboardInfoHash = Create-MetricsDashboard -ExcelFileName $ExcelFileName -OutputFolder $OutputFolder -Loger $Loger -ErrorAction Stop

        Create-StatusDashboard -ExcelFileName $ExcelFileName -UploadeMetricsDashboardInfoHash $UploadeMetricsDashboardInfoHash -OutputFolder $OutputFolder  -Loger $Loger -ErrorAction Stop
    }
    catch
    {
        $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent
        $Loger.OutErrorLog($_, "Error creating the Grafanas Dashboards.",$IsVerbose)

        Write-Error -Exception ([Exception]::new("Error in Create-AllDashboards(): $($_.Exception.Message) ", $_.Exception))
    }
}
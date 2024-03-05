function GetAllPossibleResTypes($ExcelFileName)
{
    $ResTypes =  Import-Excel $ExcelFileName -StartRow 1 -StartColumn 1 -EndColumn 3 -WorksheetName "ServicePage" -ErrorAction Stop
    if(($ResTypes| gm | ?{$_.Name -eq "ResTypeDisplayName" -or $_.Name -eq "ResTypeName" -or $_.Name -eq "ResType" }).Count -eq 3)
    {
        $ResTypes | ?{$_.ResTypeDisplayName -ne $null}
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet should containin: Row(1) Column(1) - 'ResTypeDisplayName'; Row(1) Column(2) - 'ResTypeName'; Row(1) Column(3) - 'ResType';" 
    }
}

function GetAllPossibleUnits($ExcelFileName)
{
    $UnitList = Import-Excel $ExcelFileName -StartRow 1 -StartColumn 4 -EndColumn 5 -WorksheetName "ServicePage" -ErrorAction Stop
 
    if(($UnitList| gm | ?{$_.Name -eq "Unit" -or $_.Name -eq "Unit Grafana"}).Count -eq 2)
    {
        $UnitList | ?{$_.Unit -ne $null}
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet should containin: Row(1) Column(4) - 'Unit'; Row(1) Column(5) - 'Unit Grafana';" 
    }
}

function GetAllPossibleOperators($ExcelFileName)
{
    $Operators = Import-Excel $ExcelFileName -StartRow 1 -EndRow 5 -StartColumn 6 -EndColumn 8 -WorksheetName "ServicePage" -ErrorAction Stop
 
    if(($Operators| gm | ?{$_.Name -eq "OperatorName" -or $_.Name -eq "Operator" -or $_.Name -eq "OperatorText"}).Count -eq 3)
    {
        $Operators | ?{$_ -ne $null}
    }
    else
    {
       throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet should containin: Row(1) Column(6) - 'OperatorName'; Row(1) Column(7) - 'Operator'; Row(1) Column(8) - 'OperatorText';" 
    }
}

function GetAllPossibleWinSizeGranularities($ExcelFileName)
{
    $WinSizeGranularities = Import-Excel $ExcelFileName -StartRow 1 -StartColumn 9 -EndColumn 9 -WorksheetName "ServicePage" -ErrorAction Stop
 
    if(($WinSizeGranularities| gm | ?{$_.Name -eq "WinSizeGranularities"}) -ne $null)
    {
        ($WinSizeGranularities | ?{$_.WinSizeGranularities -ne $null}).WinSizeGranularities
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet in Row(1) Column(9) should contain 'WinSizeGranularities'" 
    }
}

function GetAllPossibleSeverities($ExcelFileName)
{
    $Severities = Import-Excel $ExcelFileName -StartRow 8 -EndRow 13 -StartColumn 6 -EndColumn 6 -WorksheetName "ServicePage" -ErrorAction Stop
 
    if(($Severities| gm | ?{$_.Name -eq "Severity"}) -ne $null)
    {
        ($Severities | ?{$_.Severity -ne $null}).Severity
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet in Row(8) Column(6) should contain 'Severity'" 
    }
}

function GetAllPossibleAggregationFunctions($ExcelFileName)
{
    $AggregationFunctions = Import-Excel $ExcelFileName -StartRow 8 -EndRow 12 -StartColumn 8 -EndColumn 8 -WorksheetName "ServicePage" -ErrorAction Stop
 
    if(($AggregationFunctions| gm | ?{$_.Name -eq "AggregationFunctions"}) -ne $null)
    {
        ($AggregationFunctions | ?{$_.AggregationFunctions -ne $null}).AggregationFunctions
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet in Row(8) Column(8) should contain 'AggregationFunctions'" 
    }
}

function GetCacheSubscriptionIDs($ExcelFileName)
{
    $CacheSubscriptionIDs =  Import-Excel $ExcelFileName -StartRow 16 -StartColumn 6 -EndColumn 6 -WorksheetName "ServicePage" -ErrorAction Stop

    if(($CacheSubscriptionIDs| gm | ?{$_.Name -eq "Cache SubscriptionIDs"}) -ne $null)
    {
        ($CacheSubscriptionIDs | ?{$_."Cache SubscriptionIDs" -ne $null})."Cache SubscriptionIDs"
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet in Row(16) Column(6) should contain 'Cache SubscriptionIDs'" 
    }
}

function SetCacheSubscriptionIDs($ExcelFileName, [array]$SubscriptionIDs)
{
    $CacheSubscriptionIDs =  Import-Excel $ExcelFileName -StartRow 16 -StartColumn 6 -EndColumn 6 -WorksheetName "ServicePage" -ErrorAction Stop

    if(($CacheSubscriptionIDs| gm | ?{$_.Name -eq "Cache SubscriptionIDs"}) -ne $null)
    {
        $ExcelPkg = Open-ExcelPackage -Path $ExcelFileName

        for($i = 0; $i -lt $CacheSubscriptionIDs.Count; $i++)
        {
            $ExcelPkg.ServicePage.SetValue(17+$i, 6, $null)
        }

        for($i = 0; $i -lt $SubscriptionIDs.Count; $i++)
        {
            $ExcelPkg.ServicePage.SetValue(17+$i, 6, $SubscriptionIDs[$i])
        }

        $ExcelPkg.Save()
        Close-ExcelPackage $ExcelPkg
    }
    else
    {
        throw "Incorrect Excel format. 'ServicePage' Excel spreadsheet in Row(16) Column(6) should contain 'Cache SubscriptionIDs'" 
    }
}


<#
.SYNOPSIS
   Creating a Predefined Constants Object

.DESCRIPTION
   Creating a PredefinedConstants object from Excel file template.

.EXAMPLE
   $PredefConstant = New-PredefinedConstants -ExcelFileName '.\Template..xlsx'

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
function New-PredefinedConstants
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
            $PredefConstant = $null
            $PredefConstant = new-object psobject -Property @{
                                                                ExcelFileName=$ExcelFileName
                                                             }

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleResTypes" `
                                                       -Value {
                                                                    GetAllPossibleResTypes -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleUnits" `
                                                       -Value {
                                                                    GetAllPossibleUnits -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleOperators" `
                                                       -Value {
                                                                    GetAllPossibleOperators -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleWinSizeGranularities" `
                                                       -Value {
                                                                    GetAllPossibleWinSizeGranularities -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleSeverities" `
                                                       -Value {
                                                                    GetAllPossibleSeverities -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetAllPossibleAggregationFunctions" `
                                                       -Value {
                                                                    GetAllPossibleAggregationFunctions -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetCacheSubscriptionIDs" `
                                                       -Value {
                                                                    GetCacheSubscriptionIDs -ExcelFileName $this.ExcelFileName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant = $PredefConstant | Add-Member -MemberType ScriptMethod `
                                                       -Name "SetCacheSubscriptionIDs" `
                                                       -Value {
                                                                    param([array]$SubscriptionIDs)
                                                                    SetCacheSubscriptionIDs -ExcelFileName $this.ExcelFileName -SubscriptionIDs $SubscriptionIDs
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $PredefConstant

        }
        catch{ Write-Error -ErrorRecord $_ }
    }
}
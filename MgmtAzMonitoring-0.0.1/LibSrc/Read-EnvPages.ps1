function GetDefaultSubscriptionID($ExcelFileName, $WorksheetName)
{
    $SubscriptionID =  Import-Excel $ExcelFileName -HeaderName Name, Value -EndRow 1 -StartRow 1 -WorksheetName $WorksheetName -ErrorAction Stop
    if($SubscriptionID.Name -eq "Default SubscriptionID")
    {
        $SubscriptionID.Value
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(1) should contain 'Default SubscriptionID'" 
    }
}

function GetArrayOfResourceTypes($ExcelFileName, $WorksheetName)
{
    $ArrayOfResourceTypes = Import-Excel $ExcelFileName -StartRow 2 -StartColumn 1 -EndColumn 1 -WorksheetName $WorksheetName -ErrorAction Stop
 
    if(($ArrayOfResourceTypes| gm | ?{$_.Name -eq "ArrayOfResourceTypes"}) -ne $null)
    {
        ($ArrayOfResourceTypes | ?{$_.ArrayOfResourceTypes -ne $null}).ArrayOfResourceTypes
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(2) Column(1) should contain 'ArrayOfResourceTypes'" 
    }
}

function GetResourceGroupsPerSubID($ExcelFileName, $WorksheetName)
{
    $ResourceGroups = Import-Excel $ExcelFileName -StartRow 2 -StartColumn 2 -EndColumn 2 -WorksheetName $WorksheetName -ErrorAction Stop
 
    if(($ResourceGroups| gm | ?{$_.Name -eq "SubscriptionID | ResourceGroup"}) -ne $null)
    {
        $DefaultSubscriptionID = GetDefaultSubscriptionID -ExcelFileName $ExcelFileName -WorksheetName $WorksheetName
        
        $ResourceGroupsPerSub = @{}

        $ResourceGroups | ?{$_."SubscriptionID | ResourceGroup" -ne $null} | %{
            
            $Item = $_."SubscriptionID | ResourceGroup" -replace " ",""
            if($Item -match "([^|]+)\|([^|]+)")
            {
                $ResourceGroupsPerSub[$Matches[1]] += @($Matches[2].ToLower())
            }
            else
            {
                $ResourceGroupsPerSub[$DefaultSubscriptionID] += @($Item.ToLower())
            }
        }

        $ResourceGroupsPerSub
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(2) Column(2) should contain 'SubscriptionID | ResourceGroup'" 
    }
}

function IsEnvPage($ExcelFileName, $WorksheetName)
{
    $ResourceGroupsPerSub = GetResourceGroupsPerSubID -ExcelFileName $ExcelFileName -WorksheetName $WorksheetName
    $ResourceGroupsPerSub.Count -ne 0
}

function GetIncludedTags($ExcelFileName, $WorksheetName)
{
    $IncludedTags = Import-Excel $ExcelFileName -StartRow 2 -StartColumn 3 -EndColumn 3 -WorksheetName $WorksheetName -ErrorAction Stop
 
    if(($IncludedTags| gm | ?{$_.Name -eq "Included Only Tag"}) -ne $null)
    {
        ($IncludedTags | ?{$_."Included Only Tag" -ne $null})."Included Only Tag"
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(2) Column(3) should contain 'Included Only Tag'" 
    }
}

function GetIncludedTagsAsHashTable($ExcelFileName, $WorksheetName)
{
    $IncludedTags = Import-Excel $ExcelFileName -StartRow 2 -StartColumn 3 -EndColumn 3 -WorksheetName $WorksheetName -ErrorAction Stop
 
    if(($IncludedTags| gm | ?{$_.Name -eq "Included Only Tag"}) -ne $null)
    {
        $res = @{}
        ($IncludedTags | ?{$_."Included Only Tag" -ne $null})."Included Only Tag" | %{ if($_ -match "([^:]+):(.+)") { $res += @{$Matches[1] = $Matches[2]} } }
        $res
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(2) Column(3) should contain 'Included Only Tag'" 
    }
}

function GetExcludedResources($ExcelFileName, $WorksheetName)
{
    $ExcludedResources = Import-Excel $ExcelFileName -StartRow 2 -StartColumn 4 -EndColumn 4 -WorksheetName $WorksheetName -ErrorAction Stop
 
    if(($ExcludedResources| gm | ?{$_.Name -eq "ExcludedResources"}) -ne $null)
    {
        ($ExcludedResources | ?{$_."ExcludedResources" -ne $null}).ExcludedResources
    }
    else
    {
        throw "Incorrect Excel format. '$WorksheetName' Excel spreadsheet in Row(2) Column(4) should contain 'ExcludedResources'" 
    }
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
function New-Enviroment
{
    [cmdletBinding()] [OutputType([psobject])]
    Param
    (
        [Parameter(Mandatory=$true, HelpMessage="Full path to Excel file template.")]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String] $ExcelFileName,
        [String] $EnvWorksheetName
    )

    Process
    {
        try
        {
            $EnvResObject = $null
            $EnvResObject = new-object psobject -Property @{
                                                                ExcelFileName=$ExcelFileName
                                                                EnvWorksheetName=$EnvWorksheetName
                                                           }

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetDefaultSubscriptionID" `
                                                       -Value {
                                                                    GetDefaultSubscriptionID -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetArrayOfResourceTypes" `
                                                       -Value {
                                                                    GetArrayOfResourceTypes -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetResourceGroupsPerSubID" `
                                                       -Value {
                                                                    GetResourceGroupsPerSubID -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "IsEnvPage" `
                                                       -Value {
                                                                    IsEnvPage -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetIncludedTags" `
                                                       -Value {
                                                                    GetIncludedTags -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetIncludedTagsAsHashTable" `
                                                       -Value {
                                                                    GetIncludedTagsAsHashTable -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject = $EnvResObject | Add-Member -MemberType ScriptMethod `
                                                       -Name "GetExcludedResources" `
                                                       -Value {
                                                                    GetExcludedResources -ExcelFileName $this.ExcelFileName -WorksheetName $this.EnvWorksheetName
                                                              }  `
                                                       -PassThru `
                                                       -ErrorAction Stop `
                                                       -Force

            $EnvResObject

        }
        catch{ Write-Error -ErrorRecord $_ }
    }
}
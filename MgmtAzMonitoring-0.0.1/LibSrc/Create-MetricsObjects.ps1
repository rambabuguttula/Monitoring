<#
AppService 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/azr-arf-e2econtroltowerprod-development/providers/Microsoft.Web/sites/controltowerapi-dev

Application Service Slot 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.Web/sites/controltowerapi-dev/slots/controltowerapi-dev-stage

Application Service Plan 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.Web/serverFarms/AZR-ARF-ASP-NA-E2ECONTROLTOWERPROD-windows-Dev

DataBase   
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARQ-E2ECONTROLTOWERPROD-Production/providers/Microsoft.Sql/servers/controltower-prod/databases/e2e-Portal

Azure Bot 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.BotService/botServices/ControlTowerBot_Dev

Cache for Redis 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Production/providers/Microsoft.Cache/Redis/controltower-redis

Data Factory 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.DataFactory/factories/ADF-ControlTower-dev

Azure Cosmos DB account 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.DocumentDb/databaseAccounts/dpmdemo

Azure ML workspace 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.MachineLearningServices/workspaces/mlw-e2e-controltower-dev

Network interface 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-E2ECONTROLTOWERPROD-Development/providers/Microsoft.Network/networkInterfaces/AZR-ARF-E2ECT-ITSM-nic

Storage Account 
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourceGroups/AZR-ARF-DMT-DEV/providers/Microsoft.Storage/storageAccounts/azrarffunctionsdatadev

Storage Account queue  
/subscriptions/30db7e93-29f9-4a05-a9ee-8ee5295788bd/resourcegroups/azr-arf-e2econtroltowerprod-development/providers/microsoft.storage/storageaccounts/e2econtroltowerdev/queueservices/default

#>

function Get-ResTypeRegEx
{
    [cmdletBinding()] Param($AllPossibleResTypesItem)

    if($AllPossibleResTypesItem.ResType.Split('/').Count -eq 3)
    {
        ($AllPossibleResTypesItem.ResType -replace "([^/]+/[^/]+)/([^/]+)","/`$1/[^/]+/`$2").ToLower()
    }
    elseif($AllPossibleResTypesItem.ResType.Split('/').Count -eq 2)
    {
        ($AllPossibleResTypesItem.ResType -replace "(.+)","/`$1/[^/]+$").ToLower()
    }else
    {
        $AllPossibleResTypesItem.ResType.ToLower()
    }
}


function Add-ResTypeRegEx
{
    [cmdletBinding()] Param($AllPossibleResTypes)

    $AllPossibleResTypes = $AllPossibleResTypes | %{ $_ | Add-Member -MemberType NoteProperty `
                                                         -Name "ResTypeRegEx" `
                                                         -Value "$(Get-ResTypeRegEx -AllPossibleResTypesItem $_ -ErrorAction Stop)" `
                                                         -PassThru `
                                                         -ErrorAction Stop `
                                                         -Force 
                                                   }
    $AllPossibleResTypes
}

function Convert-AllPossibleResTypesToHashTable
{
    [cmdletBinding()] Param($AllPossibleResTypes)

    $Hash = @{}

    $AllPossibleResTypes | %{ $Hash["$($_.ResTypeDisplayName)"] = $_ }

    $Hash
}

function Convert-AllPossibleOperatorsToHashTable
{
    [cmdletBinding()] Param($AllPossibleOperators)

    $Hash = @{}

    $AllPossibleOperators | %{ $Hash["$($_.OperatorName)"] = $_ }

    $Hash
}

function Get-TypeTable
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        Convert-AllPossibleResTypesToHashTable -AllPossibleResTypes $(Add-ResTypeRegEx -AllPossibleResTypes $MonObj.PredefinedConstants.GetAllPossibleResTypes() -ErrorAction Stop) -ErrorAction Stop
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-TypeTable(): $($_.Exception.Message) ", $_.Exception))
    }
}

function Get-UnitsTable
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $Hash = @{}

        $MonObj.PredefinedConstants.GetAllPossibleUnits() | %{ $Hash += @{ $_.Unit = $_} }

        $Hash
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-AllPossibleUnitsHashTable(): $($_.Exception.Message) ", $_.Exception))
    }
}

function Get-MetricsObjects
{
    [cmdletBinding()] Param($MonObj)

    try
    {

        $MetricObjects = $MonObj.GetMetrics()
        
        $AllPossibleResTypesObjects = $MonObj.PredefinedConstants.GetAllPossibleResTypes()
        $AllPossibleResTypes_HashTable = Convert-AllPossibleResTypesToHashTable -AllPossibleResTypes $(Add-ResTypeRegEx -AllPossibleResTypes $AllPossibleResTypesObjects) -ErrorAction Stop

        $AllPossibleOperatorsObjects = $MonObj.PredefinedConstants.GetAllPossibleOperators()
        $AllPossibleOperators_HashTable = Convert-AllPossibleOperatorsToHashTable -AllPossibleOperators $AllPossibleOperatorsObjects -ErrorAction Stop


        $MetricObjects = $MetricObjects | %{ $_ | Add-Member -MemberType NoteProperty `
                                                             -Name "ResTypeName" `
                                                             -Value "$($AllPossibleResTypes_HashTable[$_.ResTypeDisplayName].ResTypeName)" `
                                                             -PassThru `
                                                             -ErrorAction Stop `
                                                             -Force |
                                                  Add-Member -MemberType NoteProperty `
                                                             -Name "ResType" `
                                                             -Value "$($AllPossibleResTypes_HashTable[$_.ResTypeDisplayName].ResType)" `
                                                             -PassThru `
                                                             -ErrorAction Stop `
                                                             -Force |
                                                  Add-Member -MemberType NoteProperty `
                                                             -Name "ResTypeRegEx" `
                                                             -Value "$($AllPossibleResTypes_HashTable[$_.ResTypeDisplayName].ResTypeRegEx)" `
                                                             -PassThru `
                                                             -ErrorAction Stop `
                                                             -Force |
                                                  Add-Member -MemberType NoteProperty `
                                                             -Name "OperatorSymbols" `
                                                             -Value "$($AllPossibleOperators_HashTable[$_.Operator].Operator)" `
                                                             -PassThru `
                                                             -ErrorAction Stop `
                                                             -Force |
                                                  Add-Member -MemberType NoteProperty `
                                                             -Name "OperatorText" `
                                                             -Value "$($AllPossibleOperators_HashTable[$_.Operator].OperatorText)" `
                                                             -PassThru `
                                                             -ErrorAction Stop `
                                                             -Force
                                          }

        $MetricObjects
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-MetricsObjects(): $($_.Exception.Message) ", $_.Exception))
    }
}
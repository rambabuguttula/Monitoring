. $PSScriptRoot\.\Read-ExcelTemplate.ps1

<#
$DSs = & curl  -H "Content-Type: application/json" `
               -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" `
               -LsS -k -X GET "$($MonObj.Config.GetGrafanaURL())/api/datasources" 2>&1 | ConvertFrom-Json

&  curl  -H "Content-Type: application/json" `
         -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" `
         -LsS -k -X GET "$($MonObj.Config.GetGrafanaURL())/api/datasources/name/AZR-ARF-GRAFANA-E2ECONTROLTOWERPROD-Development" 2>&1 | ConvertFrom-Json
#>

function Get-DatasourcesByName
{
    [cmdletBinding()] Param($MonObj, $DatasourcesName)

    try
    {
        $Json = &  curl  -H "Content-Type: application/json" `
                                -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" `
                                -LsS -k -X GET "$($MonObj.Config.GetGrafanaURL())/api/datasources/name/$DatasourcesName" 2>&1

        $StdError = $Json | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
        if($StdError -ne $null)
        {
            throw [Exception]::new("Error of datasources getting by curl -X GET $($MonObj.Config.GetGrafanaURL())/api/datasources/name/$DatasourcesName :`n$($StdError.Exception.Message) ", $StdError.Exception) 
        }

        $JsonObj = $Json | ConvertFrom-Json

        if($JsonObj.message -and $JsonObj.message -ne "Data source not found")
        {
            throw [Exception]::new("Error of datasources getting by curl -X GET $($MonObj.Config.GetGrafanaURL())/api/datasources/name/$DatasourcesName :`n$($JsonObj.message) ")
        }
        elseif($JsonObj.message -eq "Data source not found")
        {
        }
        else
        {
            $JsonObj
        }
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-DatasourcesByName(): $($_.Exception.Message) ", $_.Exception))
    }
}

# Uploade-DataSource -MonObj $MonObj -DatasourcesName "gdfgsdfg" -tenantId "3ac94b33-9135-4821-9502-eafda6592a35" -clientId "e02a4ee7-f0a9-4c7a-9d1d-49265439f082" -secretKey "ggsdfgdfrretwertwr"

function Uploade-DataSource
{
    [cmdletBinding()] Param($MonObj, $DatasourcesName, $tenantId, $ApplicationId, $secretKey)

    try
    {
        $newDatasourceJson =
"{ 
    `"name`" : `"$DatasourcesName`",
    `"type`" : `"grafana-azure-monitor-datasource`",
    `"access`" : `"proxy`",
    `"basicAuth`" : false,
    `"jsonData`" : {
        `"azureAuthType`" : `"clientsecret`",
        `"clientId`" : `"$ApplicationId`",
        `"cloudName`" : `"azuremonitor`",
        `"tenantId`" : `"$tenantId`"
    },
    `"secureJsonData`": {
        `"secretKey`" : `"$secretKey`"
    }
}
"
        Write-Host $newDatasourceJson 
        $UploadeJson = $newDatasourceJson | & curl  -H "Content-Type: application/json" `
                                                    -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" `
                                                    -LsS -k -X POST -d '@-' `
                                                    "$($MonObj.Config.GetGrafanaURL())/api/datasources" 2>&1

        $StdError = $UploadeJson | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
        if($StdError -ne $null)
        {
            throw [Exception]::new("Error of uploading '$DatasourcesName' DataSource by curl -X POST $($MonObj.Config.GetGrafanaURL())/api/datasources :`n$($StdError.Exception.Message) ", $StdError.Exception) 
        }

        $UploadeJson | ConvertFrom-Json -ErrorAction Stop

    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Uploade-DataSource(): $($_.Exception.Message) ", $_.Exception))
    }
}
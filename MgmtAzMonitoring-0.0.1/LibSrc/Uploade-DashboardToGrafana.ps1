. $PSScriptRoot\.\Read-ExcelTemplate.ps1

function Get-AllFolders
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $FoldersJson = & curl -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" -LsS -X GET "$($MonObj.Config.GetGrafanaURL())/api/folders" 2>&1
        $StdError = $FoldersJson | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
        if($StdError -ne $null)
        {
            throw [Exception]::new("Error curl -X GET $($MonObj.Config.GetGrafanaURL())/api/folders:`n$($StdError.Exception.Message) ", $StdError.Exception) 
        } 
    
        $FoldersJson | ConvertFrom-Json
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-AllFolders(): $($_.Exception.Message) ", $_.Exception))
    }
}

function Set-DashboardFolder
{
    [cmdletBinding()] Param($MonObj)

    try
    {
        $AllFolders = Get-AllFolders -MonObj $MonObj -ErrorAction Stop
        $WorkFolder = $AllFolders | ?{$_.title -eq $MonObj.Config.GetGrafanaDashboardsFolder() }
        if($WorkFolder -ne $null)
        {
           $WorkFolder
        }
        else
        {
            $FoldersJson = ""

            if($Host.Version.Major -lt 7)
            {
                $FoldersJson = & curl -H "Content-Type: application/json" -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" -LsS -k -X POST `
                                      -d "{ \`"uid\`": null, \`"title\`": \`"$($MonObj.Config.GetGrafanaDashboardsFolder())\`" }" `
                                      "$($MonObj.Config.GetGrafanaURL())/api/folders" 2>&1
            }
            else
            {
                $FoldersJson = & curl -H "Content-Type: application/json" -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" -LsS -k -X POST `
                                      -d "{ `"uid`": null, `"title`": `"$($MonObj.Config.GetGrafanaDashboardsFolder())`" }" `
                                      "$($MonObj.Config.GetGrafanaURL())/api/folders" 2>&1                
            }

            $StdError = $FoldersJson | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
            if($StdError -ne $null)
            {
                throw [Exception]::new("Error of creating folder '{ `"uid`": null, `"title`": `"$($MonObj.Config.GetGrafanaDashboardsFolder())`" }' by curl -X POST $($MonObj.Config.GetGrafanaURL())/api/folders:`n$($StdError.Exception.Message) ", $StdError.Exception) 
            }

            $FoldersJson | ConvertFrom-Json -ErrorAction Stop | Select-Object -Property id,uid,title -ErrorAction Stop
        } 
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Set-DashboardFolder(): $($_.Exception.Message) ", $_.Exception))
    }
}

function Get-AllDashboardsInFolder
{
    [cmdletBinding()] Param($MonObj, $DashboardFolder)

    try
    {
        $DashboardListJson = & curl -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" -LsS -k -X GET `
                                    "$($MonObj.Config.GetGrafanaURL())/api/search?folderIds=$($DashboardFolder.id)" 2>&1
        $StdError = $DashboardListJson | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
        if($StdError -ne $null)
        {
            throw [Exception]::new("Error of getting Dashbord list from '$($DashboardFolder.title)' folder by curl -X GET $($MonObj.Config.GetGrafanaURL())/api/search?folderIds=$($DashboardFolder.id):`n$($StdError.Exception.Message) ", $StdError.Exception) 
        }                            
                                    
        $Hash = @{}

        $DashboardListJson | ConvertFrom-Json -ErrorAction Stop | %{ $Hash["$($_.title)"] = $_ }

        $Hash
    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Get-AllDashboardInFolder(): $($_.Exception.Message) ", $_.Exception))
    }        
}

function Uploade-DashboardToFolder
{
    [cmdletBinding()] Param($MonObj, $Dashboard)

    try
    {
        $DashboardFolder = Set-DashboardFolder -MonObj $MonObj -ErrorAction Stop

        $newdashboardJson =
"{
  'dashboard': {},
  'folderId': 0,
  'folderUid': '$($DashboardFolder.uid)',
  'message': 'Made changes in $($Dashboard.title)',
  'overwrite': true
}"
        $newdashboardObj = $newdashboardJson | ConvertFrom-Json -ErrorAction Stop
        $newdashboardObj.dashboard = $Dashboard

        $newdashboardJson = $newdashboardObj | ConvertTo-Json -Depth 100 

        $UploadeJson = $newdashboardJson | & curl  -H "Content-Type: application/json" `
                                                   -H "Authorization: Bearer $($MonObj.Config.GetGrafanaAPIkey())" `
                                                   -LsS -k -X POST -d '@-' `
                                                   "$($MonObj.Config.GetGrafanaURL())/api/dashboards/db" 2>&1

        $StdError = $UploadeJson | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
        if($StdError -ne $null)
        {
            throw [Exception]::new("Error of uploading dashboard '$($Dashboard.title)' by curl -X POST $($MonObj.Config.GetGrafanaURL())/api/dashboards/db :`n$($StdError.Exception.Message) ", $StdError.Exception) 
        }

        $UploadeJson | ConvertFrom-Json -ErrorAction Stop

    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Uploade-DashboardToFolder(): $($_.Exception.Message) ", $_.Exception))
    }
}



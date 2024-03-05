. $PSScriptRoot\.\LogHelper.ps1
. $PSScriptRoot\.\Read-ExcelTemplate.ps1
. $PSScriptRoot\.\Uploade-DataSourceToGrafana.ps1

function Create-GrafanaAppReg
{
    [cmdletBinding()] Param([string] $ExcelFileName, [string] $LogFolder, [string] $CustomAppRegName )

    try
    {
        $LogFolder = Resolve-Path $LogFolder -ErrorAction Stop
        $DataStr = "$(Get-Date -Format "dd.MM.yyyy-HH.mm.ss")"

        $LogFile = Join-Path -Path $LogFolder -ChildPath "CreateGrafanaAppReg-$DataStr.log"
        $ErrFile = Join-Path -Path $LogFolder -ChildPath "CreateGrafanaAppReg-$DataStr.err"

        $Loger = New-Logger -ErrorLogFile $ErrFile -SummaryCSVFile $LogFile -SummaryCSVHeader "Status; Description"

        $MonObj = New-MonitoringObj -ExcelFileName $ExcelFileName -ErrorAction Stop

        if( $MonObj.Config.GetProjectID() -eq "")
        {
            throw "Excel file contain empty ProjectID in 'Monitoring Config' Excel spreadsheet in Row(1) Column(2)"
        }

        if( $MonObj.Config.GetProjectDisplayName() -eq "")
        {
            throw "Excel file contain empty 'Project Display Name' in 'Monitoring Config' Excel spreadsheet in Row(1) Column(2)"
        }

        if($CustomAppRegName)
        {
            $AppRegName =  $CustomAppRegName
        }
        else
        {
            $AppRegName = "$($MonObj.Config.GetProjectID())-GRAFNA-$($MonObj.Config.GetProjectDisplayName() -replace ' ','' )-Dev"
        }

        $ServicePrincipal = @()

        $ServicePrincipal = Get-AzADServicePrincipal -DisplayName "$AppRegName"

        if(($ServicePrincipal -eq $null) -or (($ServicePrincipal -eq $null) -eq $null))
        {
            $sp = New-AzADServicePrincipal -DisplayName "$AppRegName" -PasswordCredentials @{ DisplayName = "GrafnaSecret"} -ErrorAction Stop

            # $ApplicationId = $sp.AppId
            # $PasswordCredentials = $sp.PasswordCredentials.SecretText   


            Update-AzADApplication -ApplicationId $sp.AppId -Web @{ RedirectUri = @("$($MonObj.Config.GetGrafanaURL())/login/azuread",
                                                                                    "$($MonObj.Config.GetGrafanaURL())/login",
                                                                                    "$($MonObj.Config.GetGrafanaURL()):3000/login/azuread",
                                                                                    "$($MonObj.Config.GetGrafanaURL()):3000/login")}   -ErrorAction Stop
            # ApiId: 00000003-0000-0000-c000-000000000000 = Microsoft Graph 
            # PermissionId: e1fe6dd8-ba31-4d61-89e7-88639da4683d = User.Read
            # Tyoe: Scope = Delegated

            Add-AzADAppPermission -ApplicationId $sp.AppId -ApiId 00000003-0000-0000-c000-000000000000 -PermissionId e1fe6dd8-ba31-4d61-89e7-88639da4683d -Type Scope  -ErrorAction Stop

            $AppRoleAdmin = @{ allowedMemberTypes= @("User")
                            Description = "Grafana Admin Users"
                            DisplayName = "Grafana Admin"
                            Id= "$((New-Guid).Guid)"
                            IsEnabled = $true
                            Value= "Admin" }

            $AppRoleViewer = @{ allowedMemberTypes= @("User")
                            Description = "Grafana read only Users"
                            DisplayName = "Grafana Viewer"
                            Id= "$((New-Guid).Guid)"
                            IsEnabled = $true
                            Value= "Viewer" }

            $AppRoleEditor = @{ allowedMemberTypes= @("User")
                            Description = "Grafana Editor Users"
                            DisplayName = "Grafana Editor"
                            Id= "$((New-Guid).Guid)"
                            IsEnabled = $true
                            Value= "Editor" }

            $AppRoleGrafnaAdmin = @{ allowedMemberTypes= @("User")
                            Description = "Grafna Server Admin Users"
                            DisplayName = "Grafna Server Admin"
                            Id= "$((New-Guid).Guid)"
                            IsEnabled = $true
                            Value= "GrafnaAdmin" }


            Update-AzADApplication -ApplicationId $sp.AppId -AppRole @( $AppRoleAdmin, $AppRoleViewer, $AppRoleEditor, $AppRoleGrafnaAdmin)  -ErrorAction Stop

            $ServicePrincipal = $sp
        }

        $Scopes = @("EnvPageDev", "EnvPageQa", "EnvPageProd") | %{

                        $Env = $_

                        @($MonObj.GetActiveSubscriptionIDs()) | %{

                            $SubscriptionID = $_

                            $MonObj.Config."$Env".GetResourceGroupsPerSubID()[$SubscriptionID] | ?{$_} | %{

                                "/subscriptions/$SubscriptionID/resourceGroups/$_"

                            }

                        }
                    }

        $Scopes += @("/subscriptions/$($MonObj.Config.GetWorkspaceSubscription())/resourceGroups/$($MonObj.Config.GetWorkspaceRg())")

        $Scopes | Select-Object -Unique | %{

            New-AzRoleAssignment -RoleDefinitionName "Monitoring Data Reader" -ApplicationId $ServicePrincipal.AppId -Scope $_  -ErrorAction Stop
            New-AzRoleAssignment -RoleDefinitionName "Monitoring Reader" -ApplicationId $ServicePrincipal.AppId -Scope $_  -ErrorAction Stop        
        }

        if((Get-DatasourcesByName -DatasourcesName $AppRegName -MonObj $MonObj -ErrorAction Stop) -eq $null)
        { 
             # Uploade-DataSource
             Uploade-DataSource -MonObj $MonObj -DatasourcesName $AppRegName `
                                                -tenantId (Get-AzContext).Tenant.Id `
                                                -clientId $ServicePrincipal.AppId `
                                                -secretKey $ServicePrincipal.PasswordCredentials.SecretText
        }

    }
    catch
    {
        Write-Error -Exception ([Exception]::new("Error in Create-GrafanaAppReg(): $($_.Exception.Message) ", $_.Exception))
    }
}


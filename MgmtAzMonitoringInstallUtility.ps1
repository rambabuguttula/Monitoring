Remove-Item Alias:\curl -Force -ErrorAction SilentlyContinue
Remove-Item Alias:\curl -Force -ErrorAction SilentlyContinue

function Install-MgmtAzMonitoring
{
    [CmdletBinding()]
    param(
        # JNJ Username
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,
        # JNJ User password
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPassword,
        # MgmtAzMonitoring package version
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$MgmtAzMonitoringPackageVersion
    )

    $PSModulePath = @($Env:PSModulePath -split ";") | ?{$_ -match "Documents\\WindowsPowerShell" }

    if( (get-command curl -ErrorAction SilentlyContinue).DisplayName -eq "curl -> Invoke-WebRequest" )
    {
        Write-Host "------- Remove alias:curl -------"

        If (Test-Path Alias:curl) {Remove-Item Alias:curl -Force}
        If (Test-Path Alias:curl) {Remove-Item Alias:curl -Force}
    }

    if( (get-command pwsh -ErrorAction SilentlyContinue).Name -ne "pwsh.exe" )
    {
        Write-Host "------- Install PowerShell 7 -------"
        & winget install --id Microsoft.PowerShell --scope machine
    }
    
    if( "Az" -notin @(Get-Module Az -ListAvailable).Name )
    {
        Write-Host "------- Install Module Az -------"

        Find-Module -Name 'Az' -Repository 'PSGallery' | Save-Module -Path $PSModulePath -Force  
    }

    Write-Host "------- Install Module MgmtAzMonitoring -------"

    $TmpDir = [System.IO.Path]::GetTempPath()
    
    $TmpZipFile = "$($TmpDir.FullName)\MgmtAzMonitoring-$MgmtAzMonitoringPackageVersion.zip"

    curl -u "$($Username):$($UserPassword)" -X GET "https://artifactrepo.jnj.com/artifactory/jaov-generic-release/devops/MgmtAzMonitoring/MgmtAzMonitoring-$MgmtAzMonitoringPackageVersion.zip" --output "$TmpZipFile"

    Expand-Archive -Path $TmpZipFile -DestinationPath "$PSModulePath\MgmtAzMonitoring" -Force 
      
    Remove-Item $TmpZipFile -Force

    Write-Host "------- Download AzMonitoringMetricsTemplate.xlsx to current folder -------"

    curl -u "$($Username):$($UserPassword)" -X GET "https://artifactrepo.jnj.com/artifactory/jaov-generic-release/devops/MgmtAzMonitoring/AzMonitoringMetricsTemplate.xlsx" --output ".\AzMonitoringMetricsTemplate.xlsx"

}
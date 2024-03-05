<#
.SYNOPSIS
   Remove ESC sumbols
#>

function Filter-StringNoColor {
    [CmdletBinding()]
    Param(
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [string]$InputObject
    )

    Process {
        $InputObject -replace '\x1b\[\d+(;\d+)?m'
    }
}

#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Gett all Inner Exceptions
#>
function Get-InnerExceptions($ErrorRecord)
{
    $ErrorRecord
    while($ErrorRecord.Exception.InnerException)
    {
       $ErrorRecord = $_.Exception.InnerException
       $ErrorRecord.ErrorRecord
    }
}


#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Writing an error to LogFile

.EXAMPLE
    $AzOutput =  ... 2>&1                           

    $AzOutput | ?{ $_ -is [System.Management.Automation.ErrorRecord] } | Out-Error -ErrorFileLog $OutErrorLog  
                                                                                   -ContextInfo "VmID = $($VM.id)"

.EXAMPLE
    $AzOutput =  ... 2>&1

    $stderr = $AzOutput | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
    $stderr | Out-Error -ErrorFileLog $OutErrorLog  -ContextInfo "VmID = $($VM.id)"
#>
function Out-ErrorLog
{
    [CmdletBinding()]
    Param
    (
        # std error stream
        [Parameter(ValueFromPipeline=$true)]
        $StreamErr,

        # Error Log file name
        [Parameter(Mandatory=$true)]
        $ErrorLogFile,

        # Context where error arise
        [Parameter(Mandatory=$true)]
        $ContextInfo,

        # Format of Data
        [Parameter(Mandatory=$false)]
        [string]
        $FormatData="",
        
        # don't add data
        [Parameter(Mandatory=$false)]
        [switch]
        $IsNotData
    )

    Process
    {
        if($StreamErr -ne $__null__)
        {
            "================================"             | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append
            if($IsNotData)
            {
                $ContextInfo                               | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append
            }
            else
            {
                $DataStr = "$(Get-Date -Format $FormatData)"
                ("[$DataStr] " + $ContextInfo)             | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append
            }
            "--------------------------------"             | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append    
            $(Get-InnerExceptions $StreamErr | Out-String) | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append

            if( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent -and
                (Get-Command -Name "Get-Error" -ErrorAction SilentlyContinue) -ne $null )
            {
                "--------------------------------"         | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append
                $($StreamErr | Get-Error | Out-String)     | Filter-StringNoColor | Out-File -LiteralPath $ErrorLogFile  -Append
            }
        }
    }
}

#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Writing an summary CSV file of results

.EXAMPLE
    $AzOutput =  ... 2>&1  

    $stderr = $AzOutput | ?{ $_ -is [System.Management.Automation.ErrorRecord] }
    $stderr | Out-SummaryCSV -SummaryResultsCSV $OutSummaryResultsCSV  `
                             -SuccessValue "$($Vm.id); success" `
                             -FailureValue "$($Vm.id); failure"
#>
function Out-SummaryCSV
{
    [CmdletBinding()]
    Param
    (
        # std error stream
        [Parameter(ValueFromPipeline=$true)]
        $StreamErr,

        # Summary CSV file name
        [Parameter(Mandatory=$true)]
        $SummaryResultsCSV,

        # Success CSV Line
        [Parameter(Mandatory=$true)]
        $SuccessValue,

        # Failure CSV Line
        [Parameter(Mandatory=$true)]
        $FailureValue

    )

    Process
    {
        if($StreamErr -ne $__null__)
        {
            $FailureValue | Out-File  -LiteralPath $SummaryResultsCSV  -Append 
        }
        else
        {
            $SuccessValue | Out-File -LiteralPath $SummaryResultsCSV  -Append
        }
    }
}

#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Writing an summary result line to CSV file

.EXAMPLE
    Out-SummaryCSV -SummaryResultsCSV $OutSummaryResultsCSV -CSVLine "$($Vm.id); $($Vm.status)" `                             
#>
function Out-SummaryLineCSV
{
    [CmdletBinding()]
    Param
    (
        # Summary CSV file name
        [Parameter(Mandatory=$true)]
        $SummaryResultsCSV,

        #CSV Line
        [Parameter(Mandatory=$true)]
        $CSVLine,

        # Format of Data
        [Parameter(Mandatory=$false)]
        [string]
        $FormatData="",
        
        # don't add data
        [Parameter(Mandatory=$false)]
        [switch]
        $IsNotData

    )

    Process
    {
        If($IsNotData)
        {
            $CSVLine | Out-File  -LiteralPath $SummaryResultsCSV  -Append
        }
        else
        {
            $DataStr = "$(Get-Date -Format $FormatData)"
            ("[$DataStr]; " + $CSVLine) | Out-File  -LiteralPath $SummaryResultsCSV  -Append
        }
    }
}

#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Creating a Logger Object

.DESCRIPTION
   Creating a Logger object to write Error Log File and Summary CSV File of results

.EXAMPLE   
   $Logger = New-Logger -ErrorLogFile $OutErrorLog -SummaryCSVFile $OutSummaryResultsCSV -SummaryCSVHeader "VmID; VM Status"
   ...

   $AzOutput =  ... 2>&1
                            
   $stderr = $AzOutput | ?{ $_ -is [System.Management.Automation.ErrorRecord] }

   $Logger.OutErrorLog($stderr, "VmID = $($VM.id)")
   $Logger.OutSummaryCSV($stderr,"$($VM.id); success", "$($VM.id); failure")

.OUTPUTS
   [PSCustomObject] @{                        
                        SummaryCSVFile = "..."
                        ErrorLogFile   = "..."

                        OutSummaryCSV($StreamErr, $SuccessValue, $FailureValue)
                        OutErrorLog($StreamErr, $ContextInfo)
                        OutSummaryLineCSV($CSVLine)
    }
#>
function New-Logger
{
    [OutputType([psobject])]
    Param
    (
        # Error Log file name
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]
        $ErrorLogFile,

        # Summary CSV file name
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]
        $SummaryCSVFile,

        # Header of summary CSV file
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]
        $SummaryCSVHeader,

        # Date will not be added to the log automatically
        [Parameter(Mandatory=$false)]
        [switch]
        $IsNotData
    )

    Process
    {
        "SEP=;" | Out-File -LiteralPath $SummaryCSVFile
        If($IsNotData)
        {
            $SummaryCSVHeader | Out-File -LiteralPath $SummaryCSVFile -Append
        }
        else
        {
            ("Time;" + $SummaryCSVHeader) | Out-File -LiteralPath $SummaryCSVFile -Append
        }

        '' | Out-File -LiteralPath $ErrorLogFile

        $LogCSVObject = new-object psobject -Property @{
                                                            ErrorLogFile=$ErrorLogFile
                                                            SummaryCSVFile=$SummaryCSVFile
                                                            IsNotData=$IsNotData
                                                            FormatData="dd MMM yyyy-HH:mm:ss"
                                                       }

        $LogCSVObject = $LogCSVObject | Add-Member -MemberType ScriptMethod `
                                                   -Name "OutSummaryCSV" `
                                                   -Value { param($StreamErr, $SuccessValue, $FailureValue) `
                                                             Out-SummaryCSV -StreamErr $StreamErr `
                                                                            -SummaryResultsCSV $this.SummaryCSVFile `
                                                                            -SuccessValue $SuccessValue  `
                                                                            -FailureValue $FailureValue `
                                                          }  `
                                                   -PassThru `
                                                   -Force

        $LogCSVObject = $LogCSVObject | Add-Member -MemberType ScriptMethod `
                                                   -Name "OutErrorLog" `
                                                   -Value { param($StreamErr, $ContextInfo, [switch] $Verbose) `
                                                            Out-ErrorLog -StreamErr $StreamErr `
                                                                         -ErrorLogFile $this.ErrorLogFile `
                                                                         -ContextInfo $ContextInfo  `
                                                                         -FormatData $this.FormatData `
                                                                         -IsNotData:$($this.IsNotData) `
                                                                         -Verbose:$Verbose  `
                                                          }  `
                                                   -PassThru `
                                                   -Force

        $LogCSVObject = $LogCSVObject | Add-Member -MemberType ScriptMethod `
                                                   -Name "OutSummaryLineCSV" `
                                                   -Value { param($CSVLine) `
                                                            Out-SummaryLineCSV -SummaryResultsCSV $this.SummaryCSVFile `
                                                                               -CSVLine $CSVLine  `
                                                                               -FormatData $this.FormatData `
                                                                               -IsNotData:$($this.IsNotData) `
                                                          }  `
                                                   -PassThru `
                                                   -Force

        $LogCSVObject
    }
}

#------------------------------------------------------------------------------------

<#
.SYNOPSIS
   Creating a Logger Object

.DESCRIPTION
   Creating a Logger object to write Error Log File and Summary CSV File of results

.EXAMPLE   
   $Logger = New-CSVLog -SummaryCSVFile $OutSummaryResultsCSV -SummaryCSVHeader "VmID; VM Status"
   ...
   $Logger.OutSummaryLineCSV($CSVLine)

.OUTPUTS
   [PSCustomObject] @{                        
                        SummaryCSVFile = "..."

                        OutSummaryLineCSV($CSVLine)
    }
#>
function New-CSVLog
{
    [OutputType([psobject])]
    Param
    (
        # Summary CSV file name
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]
        $SummaryCSVFile,

        # Header of summary CSV file
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String]
        $SummaryCSVHeader
    )

    Process
    {
        "SEP=;" | Out-File -LiteralPath $SummaryCSVFile
        $SummaryCSVHeader | Out-File -LiteralPath $SummaryCSVFile -Append


        $LogCSVObject = new-object psobject -Property @{
                                                            SummaryCSVFile=$SummaryCSVFile
                                                       }


        $LogCSVObject = $LogCSVObject | Add-Member -MemberType ScriptMethod `
                                                   -Name "OutSummaryLineCSV" `
                                                   -Value { param($CSVLine) `
                                                            Out-SummaryLineCSV -SummaryResultsCSV $this.SummaryCSVFile `
                                                                               -CSVLine $CSVLine  `
                                                          }  `
                                                   -PassThru `
                                                   -Force

        $LogCSVObject
    }
}
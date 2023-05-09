Param( )

PROCESS{
    Write-Log "User executing: $scriptUser"

    Write-Log "Is Script being ran as Admin?: $asAdmin "

    ##### clear the cubes
    Invoke-ASCMDCommand "CLEAR" $SSAS_LocalPathASCMDCommands $configDbConnectionString

    ##### run the DSS Full Load job
    $dssJobName = $config.dssJobName
    Write-Log "Executing the sql job $dssJobName"
    Invoke-SqlNonQuery $configDbConnectionString "use msdb;EXEC dbo.sp_start_job N'$dssJobName'"

    ## wait for job to finish executing..
    $IsJobFinished = 1
    While (!($IsJobFinished -eq 4))
    {
        Start-Sleep -seconds 15
        $IsJobFinished = Invoke-SqlScalar $configDbConnectionString "declare @jobID uniqueidentifier set @jobID = (select job_id from msdb.dbo.sysjobs where name = '$dssJobName') exec [sys].[sp_MSget_jobstate] @jobID"

    }
    #### check if dss job failed or not.
    $jobOutcome = Invoke-SqlScalar $configDbConnectionString "select (case tsh.run_status
                                                                    when 0 then 'Failed'
                                                                    when 1 then 'Succeeded'
                                                                    when 2 then 'Retry'
                                                                    when 3 then 'Canceled'
                                                                    when 4 then 'In progress'
                                                                end) as RunStatus
                                                                from msdb.dbo.sysjobs j
                                                                outer apply (
                                                                    select
                                                                        top (1)
                                                                        sh.run_status as run_status
                                                                    from msdb.dbo.sysjobhistory sh
                                                                    where sh.job_id = j.job_id
                                                                        and sh.step_id = 0		-- job outcome
                                                                    order by sh.instance_id desc
                                                                ) tsh
                                                                WHERE j.name = '$dssJobName'"
    
    if ($jobOutcome -eq "Succeeded"){
        Write-Log "$dssJobName job succeeded"
    }
    else {
        Write-Log "$dssJobName job last run had a status of '$jobOutcome' "
        [System.Environment]::Exit(1)
    }


    ##### cache credentials for transfering to TROVMDSSREGRESS
    Write-Log "Cache credentials for transfer to TROVMDSSREGRESS"

    $AbfFilesDest = $config.SSASDbLocalPath.Replace('C:',$config.dssRegressServer)
	net use $config.dssRegressServer 'Gr33kMyth!' /USER:"DEV\tro.devuser"

    ## retrieve and store the DSS build number in a created file
    $RegObj = Get-ItemProperty -Path $config.dssBuildNumberRegPath -Name $config.dssBuildNumberRegKey
    $BuildNumber = $RegObj.InstallationVersion
    $BuildFilename = "$env:COMPUTERNAME"+"DSSBuildNumber.txt"
    $contents = "$env:COMPUTERNAME Build Number: $BuildNumber"
    New-Item -Path $PSScriptRoot -Name $BuildFilename  -ItemType "file" -Value $contents  -Force

    #### Take backups of the SSAS database
    Invoke-ASCMDCommand "BACKUP" $SSAS_LocalPathASCMDCommands $configDbConnectionString

    #### copy.abf files from c:\processingEngine\Azcmd\Commands to TROVMDSSREGRESS
    Write-Log "Transfering .abf files from $SSAS_LocalPathASCMDCommands to $AbfFilesDest"

    $AbfFiles = Get-ChildItem -Path $SSAS_LocalPathASCMDCommands | Where-Object {$_.Extension -eq ".abf"}

    Set-Location $SSAS_LocalPathASCMD

    foreach ($f in $AbfFiles){
        Write-Log "Copying $f to $AbfFilesDest"
        
        $n = 1
        while ($n){
            if (!(Test-IsFileLocked -Path $f.FullName)){
                try {
                    Copy-item -Path $f.FullName -Destination $AbfFilesDest -Force -ErrorAction Stop
                    $n = 0
                }
                catch {
                    Write-Log "*ERROR*: $($_.exception.message)"
                    [System.Environment]::Exit(1)
                }
                
            }
            else {
                Start-Sleep -Seconds 3
            }
        }
    }

    ## copy build number file
    Write-Log "Copy build number file to $AbfFilesDest"
    if ($BuildFilename) {
        Move-item -Path $PSScriptRoot\$BuildFilename -Destination $AbfFilesDest -Force
    }

    ## Execute SQL Command to Donwload Images
    Write-Log "Download Images from Database to the File Upload Directory"
    Invoke-Sqlcmd -Query "exec NWSDSSRegression.reg.exportImagesAll 'C:\apps\DBTools\DSS\DSSRegression\MDXScripts\FileUpload'" -ConnectionString $config.localDbConnectionString
    
}
BEGIN{
    ## import lib
    . $PSScriptRoot\lib\Invoke-PsFunctions.ps1
    
    ## set paths
    $RootDir = (Split-Path $PSScriptRoot -Parent)
    $Logfile = "$RootDir\logs\BackupSSASDbLog_$(gc env:computername)_$((Get-Date).ToString('yyyyMMddhhmmssfffftt')).log"
    $SSAS_LocalPathASCMDCommands = "$RootDir\ascmd\Commands\"
    $SSAS_LocalPathASCMD = "$RootDir\ascmd\"

    ## create log file
    New-Item -path $Logfile -type "file" -Force | out-null

    ## import config settings
    $configFileName = "BackupSSASDbConfig.json"
    $config = Get-Content -Raw -Path $RootDir\$configFileName | ConvertFrom-Json
    $configDbConnectionString = $config.localDbConnectionString

    ## set vars
    $scriptUser = [Environment]::UserDomainName + "\" + [Environment]::UserName
    $asAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
END{
    Write-Log "Ending Invoke-BackupSSASDbs on $env:COMPUTERNAME"
}
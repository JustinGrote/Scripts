#.Synopsis
#    Takes any command with multiple targets and enables it to run multithreaded using Powershell Runspaces
#    
#.Description
#    This script will allow any general, external script to be multithreaded by providing a single
#    argument to that script and opening it in a seperate thread.  It works as a filter in the 
#    pipeline, or as a standalone script.  It will read the argument either from the pipeline
#    or from a filename provided.  It will send the results of the child script down the pipeline,
#    so it is best to use a script that returns some sort of object.
#
#    Authored by Ryan Witschger - http://www.Get-Blog.com
#    
#.PARAMETER Command
#    This is where you provide the PowerShell Cmdlet / Script file that you want to multithread.  
#    You can also choose a built in cmdlet.  Keep in mind that your script.  This script is read into 
#    a scriptblock, so any unforeseen errors are likely caused by the conversion to a script block.
#    
#.PARAMETER ObjectList
#    The objectlist represents the arguments that are provided to the child script.  This is an open ended
#    argument and can take a single object from the pipeline, an array, a collection, or a file name.  The 
#    multithreading script does it's best to find out which you have provided and handle it as such.  
#    If you would like to provide a file, then the file is read with one object on each line and will 
#    be provided as is to the script you are running as a string.  If this is not desired, then use an array.
#    
#.PARAMETER InputParam
#    This allows you to specify the parameter for which your input objects are to be evaluated.  As an example, 
#    if you were to provide a computer name to the Get-Process cmdlet as just an argument, it would attempt to 
#    find all processes where the name was the provided computername and fail.  You need to specify that the 
#    parameter that you are providing is the "ComputerName".
#
#.PARAMETER AddParam
#    This allows you to specify additional parameters to the running command.  For instance, if you are trying
#    to find the status of the "BITS" service on all servers in your list, you will need to specify the "Name"
#    parameter.  This command takes a hash pair formatted as follows:  
#
#    @{"ParameterName" = "Value"}
#    @{"ParameterName" = "Value" ; "ParameterTwo" = "Value2"}
#
#.PARAMETER AddSwitch
#    This allows you to add additional switches to the command you are running.  For instance, you may want 
#    to include "RequiredServices" to the "Get-Service" cmdlet.  This parameter will take a single string, or 
#    an aray of strings as follows:
#
#    "RequiredServices"
#    @("RequiredServices", "DependentServices")
#
#.PARAMETER MaxThreads
#    This is the maximum number of threads to run at any given time.  If resources are too congested try lowering
#    this number.  The default value is 20.
#    
#.PARAMETER SleepTimer
#    This is the time between cycles of the child process detection cycle.  The default value is 200ms.  If CPU 
#    utilization is high then you can consider increasing this delay.  If the child script takes a long time to
#    run, then you might increase this value to around 1000 (or 1 second in the detection cycle).
#
#    
#.EXAMPLE
#    Both of these will execute the script named ServerInfo.ps1 and provide each of the server names in AllServers.txt
#    while providing the results to the screen.  The results will be the output of the child script.
#    
#    gc AllServers.txt | .\Invoke-CommandMultiThreaded.ps1 -Command .\ServerInfo.ps1
#    .\Invoke-CommandMultiThreaded.ps1 -Command .\ServerInfo.ps1 -ObjectList (gc .\AllServers.txt)
#
#.EXAMPLE
#    The following demonstrates the use of the AddParam statement
#    
#    $ObjectList | .\Invoke-CommandMultiThreaded.ps1 -Command "Get-Service" -InputParam ComputerName -AddParam @{"Name" = "BITS"}
#    
#.EXAMPLE
#    The following demonstrates the use of the AddSwitch statement
#    
#    $ObjectList | .\Invoke-CommandMultiThreaded.ps1 -Command "Get-Service" -AddSwitch @("RequiredServices", "DependentServices")
#
#.EXAMPLE
#    The following demonstrates the use of the script in the pipeline
#    
#    $ObjectList | .\Invoke-CommandMultiThreaded.ps1 -Command "Get-Service" -InputParam ComputerName -AddParam @{"Name" = "BITS"} | Select Status, MachineName
#


Param($Command = $(Read-Host "Enter the script file"), 
    [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]$ObjectList,
    $InputParam = $Null,
    [int]$MaxThreads = 20,
    [int]$SleepTimer = 200,
    [int]$MaxResultTime = 120,
    [HashTable]$AddParam = @{},
    [Array]$AddSwitch = @()
)

Begin{
    $ISS = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $ISS, $Host)
    $RunspacePool.Open()
        
    If ($(Get-Command | Select-Object Name) -match $Command){
        $Code = $Null
    }Else{
        $OFS = "`r`n"
        $Code = [ScriptBlock]::Create($(Get-Content $Command))
        Remove-Variable OFS
    }
    $Jobs = @()
}

Process{
    Write-Progress -Activity "Preloading threads" -Status "Starting Job $($jobs.count)"
    ForEach ($Object in $ObjectList){
        If ($Code -eq $Null){
            $PowershellThread = [powershell]::Create().AddCommand($Command)
        }Else{
            $PowershellThread = [powershell]::Create().AddScript($Code)
        }
        If ($InputParam -ne $Null){
            $PowershellThread.AddParameter($InputParam, $Object.ToString()) | out-null
        }Else{
            $PowershellThread.AddArgument($Object.ToString()) | out-null
        }
        ForEach($Key in $AddParam.Keys){
            $PowershellThread.AddParameter($Key, $AddParam.$key) | out-null
        }
        ForEach($Switch in $AddSwitch){
            $Switch
            $PowershellThread.AddParameter($Switch) | out-null
        }
        $PowershellThread.RunspacePool = $RunspacePool
        $Handle = $PowershellThread.BeginInvoke()
        $Job = "" | Select-Object Handle, Thread, object
        $Job.Handle = $Handle
        $Job.Thread = $PowershellThread
        $Job.Object = $Object.ToString()
        $Jobs += $Job
    }
        
}

End{
    $ResultTimer = Get-Date
    While (@($Jobs | Where-Object {$_.Handle -ne $Null}).count -gt 0)  {
    
        $Remaining = "$($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False}).object)"
        If ($Remaining.Length -gt 60){
            $Remaining = $Remaining.Substring(0,60) + "..."
        }
        Write-Progress `
            -Activity "Waiting for Jobs - $($MaxThreads - $($RunspacePool.GetAvailableRunspaces())) of $MaxThreads threads running" `
            -PercentComplete (($Jobs.count - $($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False}).count)) / $Jobs.Count * 100) `
            -Status "$(@($($Jobs | Where-Object {$_.Handle.IsCompleted -eq $False})).count) remaining - $remaining" 

        ForEach ($Job in $($Jobs | Where-Object {$_.Handle.IsCompleted -eq $True})){
            $Job.Thread.EndInvoke($Job.Handle)
            $Job.Thread.Dispose()
            $Job.Thread = $Null
            $Job.Handle = $Null
            $ResultTimer = Get-Date
        }
        If (($(Get-Date) - $ResultTimer).totalseconds -gt $MaxResultTime){
            Write-Error "Child script appears to be frozen, try increasing MaxResultTime"
            Exit
        }
        Start-Sleep -Milliseconds $SleepTimer
        
    } 
    $RunspacePool.Close() | Out-Null
    $RunspacePool.Dispose() | Out-Null
} 
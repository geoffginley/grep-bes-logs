<#
 
.DESCRIPTION
    Grep-BesLogs will take a search string and grep logs locally or remotely. You can also have the cmdlet collect the full logs in addition to the grepped logs and then zip them.
 
.SYNOPSIS
    There are 3 main functions within this cmdlet LocalGrep, RemoteGrep and RemotePSGrep

		LocalGrep - Will search for a string local to were the cmdlet is run

		RemoteGrep - Will search for a string from the local powershell session to a remote machine using a UNC path. This is ideal for smaller logs like controller

		RemotePSGrep - Will create a session to a the remote machines winrm interface and leverage the remote machine for the grepping
 
.PARAMETER $logDate
    The convention for this date is yyyyMMdd e.g 20130725. The default value is the current date.
 
.PARAMETER $lcoalSearch
    This is a boolean value of $true or $false. The default is $false

.PARAMETER $remoteSearch
    This is a boolean value of $true or $false. The default is $false

.PARAMETER $remotePSSearch
    This is a boolean value of $true or $false. The default is $false

.PARAMETER $machine
    This is a string of the machine(s) you would like to grep. If you input multiple please enclose in qoutes and separate with a comma (no spaces) e.g. 'machine1,machine2'
 
.PARAMETER $csvFile
    This is the path of a file (text or csv) of machine(s) you would like to grep. the format is line seperated (machine name per line)

.PARAMETER $besLogType
    This is a string that must include wilcards and the part file name of the type of log you would like to grep. e.g. '*ctrl*' or '*mdat*' or '*magt*' etc.. the default value is '*alrt*'

.PARAMETER $errorToMatch
    This is a string that must include wilcards and the part line you would like to grep. e.g. '*exception*' or '*error*' etc.. the default value is '*'

.PARAMETER $logDir
    This is a string of the directory where the logs will be copied e.g c:\temp. The default value is "${env:TEMP}\bb_logs"

.PARAMETER $logDrive
    This is a string of the drive where all the are stored. This will be ignored if $logPath parameter is not set. The default value is 'c'
 
.PARAMETER $logPath
    This is a string of the path where all the are stored. If this is not set the script will pull this value from the registry of the machine you will be grepping. The default value is $null
 
.PARAMETER $logZip
    This is a boolean value of $true or $false. The default is $false

.PARAMETER $withCopy
    This is a boolean value of $true or $false. This will copy all the logs of the type you have specified and the date you specified. The default is $false

.PARAMETER $withCopyAll
    This is a boolean value of $true or $false. This will copy all the logs of for the date you specified. The default is $false
 
.EXAMPLE
    Grep-BesLogs
 
.EXAMPLE
    Grep-BesLogs -logDate 20131010
 
.EXAMPLE
    Grep-BesLogs -logDate '20131005' -remotePSSearch $true -besLogType '*magt*' -errorToMatch 'unhandled' -machine 'machine1,machine2' -withCopy $true
 
.EXAMPLE
    Grep-BesLogs -logDate '20131005' -remoteSearch $true -besLogType '*ctrl*' -errorToMatch 'heartbeats. Restarting' -csvFile 'c:\temp\mybesservers.csv' -withCopyAll $true -logZip $true
 

.NOTES
    Author: Geoff Ginley
 
#>

# Some commands that can be recycled for other cmdlets within the module
$command = {param($besLog, $logDate, $besLogType, $errorToMatch) Get-Content -ErrorAction Stop -Path ($besLog + $logDate + $besLogType) | where {$_ -match $errorToMatch} }
$command1 = {get-itemproperty -ErrorAction Stop 'HKLM:\SOFTWARE\Wow6432Node\Research In Motion\BlackBerry Enterprise Service\Logging Info' | select -ExpandProperty LogRoot }

Function Grep-BesLogs(){
	param(
	[Parameter(Position = 0)]
	[bool]$remoteSearch = $false,
	[Parameter(Position = 1)]
	[bool]$remotePSSearch = $false,
	[Parameter(Position = 2)]
	[bool]$localSearch = $true,
	[Parameter(Position = 3)]
	[string]$machine = $null,
	[Parameter(Position = 4)]
	[string]$csvFile = $null,
	[Parameter(Position = 5)]
	[int]$logDate = (get-Date -format "yyyyMMdd"),
	[Parameter(Position = 6)]
	[string]$logDir = "${env:TEMP}\bb_logs",
	[Parameter(Position = 6)]
	[string]$logDrive = 'c', 
	[Parameter(Position = 7)]
	[string]$logPath = $null,
	[Parameter(Position = 8)]
	[string]$besLogType = '*alrt*',
	[Parameter(Position = 9)]
	[string]$errorToMatch = '*',
	[Parameter(Position = 10)]
	[bool]$logZip = $false,
	[Parameter(Position = 11)]
	[bool]$withCopy = $false,
	[Parameter(Position = 12)]
	[bool]$withCopyAll = $false
	)
	
	#Converting int to string to appeand the \
	[string] $logDate = [System.Convert]::ToString($logDate)  
	$logDate = $logDate + '\'

	# This will create a log directory if one doesn't already exist
	if (!(Test-Path $logDir)){
		New-Item -Path $logDir -ItemType directory -Force | Out-Null
	}

	if($remoteSearch -or $remotePSSearch) {
		if($remoteSearch -and $remotePSSearch){
			Write-Host 'You can only specify either a remotePSSearch or remoteSearch, not both '
			return
		}
		$localSearch = $false
	}
	
	if(($machine -or $csvFile) -and (!($remoteSearch -or $remotePSSearch))){
		write-host 'You have either provided a machine or file as a parameter, please set remoteSearch or remotePSSearch to true or alternatively remove the parametr for a local search '
		return
	}
	
	if(!($localSearch)){
		if ($machine -and $csvFile) {
			Write-Host 'You can only specify either a machine or a csv file, not both '
			return
		}
		if(!($machine -or $csvFile)){
			Write-Host 'You must specify either a machine or a csv file '
			return
		}
		else{
			if($machine){
				$csv = $machine.Split(',')
			}
			if($csvFile){
				$csv = Get-Content $csvFile 
			}
			if($remoteSearch){
				remoteGrep	
			}
			if($remotePSSearch){
				remotePSGrep
			}
		}
	}	
	else{
		$csv = 'localhost'
		localgrep
	}

	if($logZip){
		zipLogs ($logDir)
	}

	Write-Host 'Please collect the logs from' $logDir
}

Function writeHost(){
	Write-Host ''
    write-host 'Machine: ' $line
	write-host 'Search Path: ' $besLog$logDate$besLogType
	write-host 'Search String: ' $errorToMatch
	Write-Host $logLineCount 'line(s) found that matches search string '
	Write-Host ''
}

Function writeLog(){
	'Machine: ' + $line | out-file ($logDir + '\' + 'grep.log') -append
	'Search Path: ' + $besLog + $logDate + $besLogType | out-file ($logDir + '\' + 'grep.log') -append
	'Search String: ' + $errorToMatch | out-file ($logDir + '\' + 'grep.log') -append
	"$logLineCount line(s) found that matches search string " | out-file ($logDir + '\' + 'grep.log') -append
	$remoteLog | out-file ($logDir + '\' + 'grep.log') -append
	$_.Exception.Message | out-file ($logDir + '\' + 'grep.log') -append
	'' | out-file ($logDir + '\' + 'grep.log') -append
}

Function copyLog(){
	if (!(Test-Path ($logDir + $logDate))){
		New-Item -Path ($logDir + '\' + $logDate) -ItemType directory -Force | Out-Null		
	}
	if($beslog -match ':' -and $remotePSSearch){
		$beslog = "$csv\$beslog"
		$beslog = $beslog.Insert(0,'\\') -replace ':','$'
	}
	if($withcopy -and $withCopyAll -or $withCopyAll){
		Get-ChildItem -Recurse -Path ($besLog + $logDate) | Copy-Item -Destination ($logDir + '\' + $logDate) -Force 
	}
	if($withcopy){
		Get-ChildItem -Recurse -Path ($besLog + $logDate + $besLogType) | Copy-Item -Destination ($logDir + '\' + $logDate) -Force 
	}
}


Function localGrep(){
	$line = $csv
	If (!($logPath)){
		try{
			$besLog = Invoke-Command -ScriptBlock $command1 
		}
		Catch [System.Exception]{
			$_.Exception.Message
			Write-Host 'You may not have rights to the registry, you could specify the path to logs maually (-logPath) '
		}
	}
	Else {
		$besLog = $logDrive + ':' + $logPath + $logDate
	}
	Try{
	$remoteLog = Invoke-Command -ScriptBlock $command -ArgumentList $besLog, $logDate, $besLogType, $errorToMatch
	$logLineCount = $remoteLog | Measure-Object -Line | select -ExpandProperty Lines #' Found that matches your search criteria ' 
	writeHost
	writeLog
	}
	Catch [System.Exception]{
	$_.Exception.Message
	writeLog
	} 
}

Function remoteGrep(){
	foreach ($line in $csv){
		If (!($logPath)){
			try{
				$remotereg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine", $line) 
				$key = $remotereg.OpenSubKey('SOFTWARE\\Wow6432Node\\Research In Motion\\BlackBerry Enterprise Service\\Logging Info')
				$logRootValue = $key.GetValue('LogRoot')
				$besLog = '\\' + $line + '\' + $logRootValue
				$besLog = $besLog -replace ':','$'
			}
			Catch [System.Exception]{
				$_.Exception.Message
				Write-Host 'You may not have rights to the registry, you could specify the path to logs maually (-logPath) '
			}
		}
		Else {
			$besLog = '\\' + $line + '\' + $logDrive + '$' + $logPath + $logDate
		}
		
		Try{
			$remoteLog = Invoke-Command -ScriptBlock $command -ArgumentList $besLog, $logDate, $besLogType, $errorToMatch
			$logLineCount = $remoteLog | Measure-Object -Line | select -ExpandProperty Lines #' Found that matches your search criteria ' 
			writeHost
			writeLog
		}
		Catch [System.Exception]{
			$_.Exception.Message
			writeLog
		}
		if($withcopy -or $withCopyAll){
			copyLog
		}
	}
}

Function remotePSGrep(){
	foreach ($line in $csv){
		$session = New-PSSession -ComputerName $line
		If (!($logPath)){
			try{
				$besLog = Invoke-Command -Session $session -ScriptBlock $command1 
			}
			Catch [System.Exception]{
				$_.Exception.Message
				Write-Host 'You may not have rights to the registry, you could specify the path to logs maually (-logPath) '
			}
		}
		Else{
			$besLog = $logDrive + ':' + $logPath + $logDate
		}
		Try{
		$remoteLog = Invoke-Command -Session $session -ScriptBlock $command -ArgumentList $besLog, $logDate, $besLogType, $errorToMatch
		$logLineCount = $remoteLog | Measure-Object -Line | select -ExpandProperty Lines #' Found that matches your search criteria ' 
		writeHost
		writeLog
		}
		Catch [System.Exception]{
			$_.Exception.Message
			writeLog
		}
		if($withcopy -or $withCopyAll){
			copyLog
		}
		Remove-PSSession $session
	}
}

Function zipLogs(){
	param(
	[Parameter(Position = 0)]
	[string]$ZipDir = $null
	)
	
	Write-Host "Zipping the contents of $ZipDir"
	$ZipName = "$ZipDir\bblogs_$(get-date -Format "yyyymmdd_HHmm").zip"
	$Files = get-item $ZipDir
	If (!($ZipName.EndsWith('.zip'))){
		$ZipName += '.zip'
	}
	If (!(test-path $ZipName)){
		set-content $ZipName ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18))
	}
	$ZipFile = (new-object -com shell.application).NameSpace($ZipName)
	$files | foreach {$zipfile.CopyHere($_.fullname)}
}


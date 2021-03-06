Param(
	[Parameter(Mandatory=$true)][Int]$GracePeriod
	)

Function Check-NewUpdates {

<#
	.SYNOPSIS
		Get list of available Windows updates.

	.DESCRIPTION
		Use Check-NewUpdates to determine if there are additional updates that have not been applied to a Microsoft Windows machine. 
		
	.PARAMETER Type
		Pre-search criteria. Finds updates of a specific type, such as 'Driver' and 'Software'. Default value contains all updates.

	.EXAMPLE

			PS D:\Powershell> .\Check-Updates.ps1 -GracePeriod 117
			116 Days since last update. Within grace period - 2 Critical Updates:{KB4023307.KB4041693.} - 6 Important Updates:{KB3159398.KB3169704.KB3172729.KB3175024.KB3178539.KB4041085.} - 1 Moderate Updates:{KB4049179.} - 2 Unspecified Updates:{KB3173424.KB890830.} 
			| CriticalUpdates=2;0;0;0;0 ImportantUpdates=6;0;0;0;0 ModerateUpdates=1;0;0;0;0 LowUpdates=0;0;0;0;0 UnspecifiedUpdates=2;0;0;0;0

	.NOTES
		Author: Spenser Reinhardt & Juan Granados & Sean Preece
		Company: Nagios Enterprises LLC
		Version: 1.2
			Output performance data
			Fix bug with empty InstalledOn WMI data (http://britv8.com/powershell-get-the-actual-installed-dates-of-hotfixes/)
			Made Parameter mandatory for easy use of GracePeriod feature with icinga

	.LINK
		http://www.nagios.com

#>

Param(
	[Parameter(Mandatory=$true)][Int]$GracePeriod
	)

if(-not($GracePeriod)) { Throw “You must supply a value for -GracePeriod” }

## Start Main Script

$OSVersion = Check-OSVersion

If ( $GracePeriod -ne $null ) { #If GracePeriod is set
	$UpdateTime = Check-LastUpdate $GracePeriod
	If ($UpdateTime.IsOver -eq $true) { #If is outside of GP, check for updates and return
	$Updates = Check-Updates
	$Output = Create-Output $Updates
	}
	ElseIF ($UpdateTime.IsOver -eq $false) { #If within GP, return days since check with OK status
		$Updates = Check-Updates
		$Output = Create-Output $Updates
		if(!($Output.Output -match ". There are no updates to be done.")){
			$Output.Output = ". Within grace period" + $Output.Output
		}
		$Output.ExitCode = 0
	}
} #ends if GP is set
	
Else { # If no grace period has been set, check and return
	$UpdateTime = Check-LastUpdate 0
	$Updates = Check-Updates
	$Output = Create-Output $Updates
}

$days = $UpdateTime.Days
$OutputString = $Output.Output
Write-Output "$days Days since last update$OutputString DaysSinceLastUpdate=$days;0;0;0;0"
Exit $Output.ExitCode
}

# Function to check OS Version and return string with 7 or XP depending. Returns [string]
Function Check-OSVersion {
	$version = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
	switch ($($version.CurrentVersion).split(".")[0]){
		6 { [string]$Return = "7" }
		5 { [string]$Return = "XP" }
	} ## End of Switch to check versioning
	Return $Return
} ## End of Function

# Checks for updates using winupdate api, returns hashtable with all listed updates not including hidden ones. Returns [Array](KBImportance)KB and [Int](KBImportance)Number
Function Check-Updates {
	$Return = @{}
	[string]$Return.CriticalKB = ""
	[Int]$Return.CriticalNumber = 0
	[string]$Return.ImportantKB = ""
	[Int]$Return.ImportantNumber = 0
	[string]$Return.ModerateKB = ""
	[Int]$Return.ModerateNumber = 0
	[string]$Return.LowKB = ""
	[Int]$Return.LowNumber = 0
    [string]$Return.UnspecifiedKB = ""
	[Int]$Return.UnspecifiedNumber = 0
	$Updates = $( New-Object -ComObject Microsoft.Update.Session ).CreateUpdateSearcher().Search("IsHidden=0 and IsInstalled=0").Updates
	ForEach ($Update in $Updates){
		if ($Update.MsrcSeverity -eq "Critical"){
			$Return.CriticalNumber++
			$Return.CriticalKB += "KB"+$update.KBArticleIDs+","
		}
		Elseif($Update.MsrcSeverity -eq "Important"){
			$Return.ImportantNumber++
			$Return.ImportantKB += "KB"+$update.KBArticleIDs+","
		}
		Elseif($Update.MsrcSeverity -eq "Moderate"){
			$Return.ModerateNumber++
			$Return.ModerateKB += "KB"+$update.KBArticleIDs+","
		}
		Elseif($Update.MsrcSeverity -eq "Low"){
			$Return.LowNumber++
			$Return.LowKB += "KB"+$update.KBArticleIDs+","
		}
		Else{
			$Return.UnspecifiedNumber++
			$Return.UnspecifiedKB += "KB"+$update.KBArticleIDs+","
		}
	}
	Return $Return
} # Ends Function

# Checks if last update installed was within Grace Period, Returns [Int]Days and [Boolean]IsOver
Function Check-LastUpdate {
	Param([Parameter(Mandatory=$true)][Int]$GracePeriod)
	$Return = @{}
	#Gets DateTime Object with last update installed
	if ($(Check-OSVersion) -eq "7") {
		$WMIData = Get-WmiObject -Class Win32_QuickFixEngineering 
	}
	Else { $WMIData = $null }
		If ( $WMIData -eq $null ) { ## No data for installed on, run update check, might be issue with os version too
			$Return.Days = 0
			$Return.IsOver = $true
		}
	Else { ## has data and should be processed
		$Session = New-Object -ComObject Microsoft.Update.Session            
		$Searcher = $Session.CreateUpdateSearcher()         
		$HistoryCount = $Searcher.GetTotalHistoryCount()
		[DateTime]$Date = (            
			# http://msdn.microsoft.com/en-us/library/windows/desktop/aa386532%28v=vs.85%29.aspx            
			$Searcher.QueryHistory(0,$HistoryCount) | ForEach-Object -Process {            
				$Title = $null            
				if($_.Title -match "\(KB\d{6,7}\)"){            
					# Split returns an array of strings            
					$Title = ($_.Title -split '.*\((KB\d{6,7})\)')[1]            
				}else{            
					$Title = $_.Title            
				}  
				# http://msdn.microsoft.com/en-us/library/windows/desktop/aa387095%28v=vs.85%29.aspx            
				$Result = $null            
				Switch ($_.ResultCode){            
					0 { $Result = 'NotStarted'}            
					1 { $Result = 'InProgress' }            
					2 { $Result = 'Succeeded' }            
					3 { $Result = 'SucceededWithErrors' }            
					4 { $Result = 'Failed' }            
					5 { $Result = 'Aborted' }            
					default { $Result = $_ }            
				}            
				New-Object -TypeName PSObject -Property @{            
				ComputerName = $ENV:Computername;
				InstalledOn = Get-Date -Date $_.Date;            
				KBArticle = $Title;            
				Name = $_.Title;            
				Status = $Result            
				}                     
			} | 
			Sort-Object -Descending:$true -Property InstalledOn |             
			Select-Object -Property * | Sort InstalledOn -Descending -Unique -ErrorAction 'SilentlyContinue' | Select InstalledOn -First 1
		).InstalledOn
		$Return.Days =  $( $(Get-Date) - $Date).Days
		If ( $Return.Days -gt $GracePeriod ) { #if true has been longer than grace period
			$Return.IsOver = $true
		}
		Else { #if within Grace Period
			$Return.IsOver = $false
		}
	}
	Return $Return
}

# Creates write-ouput text for returning data to nagios, Returns [int]ExitCode and [string]Output
Function Create-Output {
	Param ( [Parameter(Mandatory=$true)]$Updates )
	$Return = @{}
	[Int]$Return.ExitCode = 3 # Sets to unknown by default
	[String]$Return.Output = ""
	If ( $Updates.CriticalNumber -gt 0 ) { # If any Critical updates, writes output line and sets exit code to 2(critical)
		$Return.ExitCode = 2
		$Return.Output += " - "+$Updates.CriticalNumber+" Critical Updates:"
		$Return.Output += "{$($Updates.CriticalKB.TrimEnd(","))}"
	} #Ends Critical If
	If ( $Updates.ImportantNumber -gt 0 ) { # If any Important updates, writes output line and sets exit code to 2(critical)
		$Return.ExitCode = 2
		$Return.Output += " - "+$Updates.ImportantNumber+" Important Updates:"
		$Return.Output += "{$($Updates.ImportantKB.TrimEnd(","))}"
	} #Ends Important If
	If ( $Updates.ModerateNumber -gt 0 ) { # If any Moderate updates, writes output line and sets exit code to 1(Warning)
		$Return.ExitCode = 1
		$Return.Output += " - "+$Updates.ModerateNumber+" Moderate Updates:"
		$Return.Output += "{$($Updates.ModerateKB.TrimEnd(","))}"
	} #Ends Moderate If
	If ( $Updates.LowNumber -gt 0 ) { # If any Low updates, writes output line and sets exit code to 1(Warning)
		$Return.ExitCode = 1
		$Return.Output += " - "+$Updates.LowNumber+" Low Updates:"
		$Return.Output += "{$($Updates.LowKB.TrimEnd(","))}"  
	} #Ends Low If
	If ($Updates.UnspecifiedNumber -gt 0) { # If number of Unspecified severity updates are available sets exit to 1(warning)
		$Return.ExitCode = 1
		$Return.Output += " - "+$Updates.UnspecifiedNumber+" Unspecified Updates:"
		$Return.Output += "{$($Updates.UnspecifiedKB.TrimEnd(","))}"
	}
	If ( ($Updates.CriticalNumber -eq 0) -and ($Updates.ImportantNumber -eq 0) -and ($Updates.ModerateNumber -eq 0) -and ($Updates.LowNumber -eq 0) -and ($Updates.UnspecifiedNumber -eq 0) ) { #If no updates, writes output and sets exit 0(OK)
		$Return.ExitCode = 0
		$Return.Output = ". There are no updates to be done."
	}
	if($Return.Output -eq ""){
		Return.Output = "Output creation failed, something is not working!"
	}
	$TotalUpdates=$Updates.CriticalNumber+$Updates.ImportantNumber+$Updates.ModerateNumber+$Updates.LowNumber+$Updates.UnspecifiedNumber
	$Return.Output = $Return.Output + " | TotalUpdates=$($TotalUpdates);0;0;0;0 CriticalUpdates=$($Updates.CriticalNumber);0;0;0;0 ImportantUpdates=$($Updates.ImportantNumber);0;0;0;0 ModerateUpdates=$($Updates.ModerateNumber);0;0;0;0 LowUpdates=$($Updates.LowNumber);0;0;0;0 UnspecifiedUpdates=$($Updates.UnspecifiedNumber);0;0;0;0"
	Return $Return
}

Check-NewUpdates $GracePeriod
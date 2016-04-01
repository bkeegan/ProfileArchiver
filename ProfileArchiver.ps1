<# 
.SYNOPSIS 
	Auto-archives user profile folders.
.DESCRIPTION 
    This script is designed to auto-archive user profiles created via Windows Folder Redirection policies (Group Policy) for users that no longer exist on the domain. This script will email a report of the results in text format.
.NOTES 
    File Name  : ProfileArchiver.ps1
    Author     : Brenton keegan - brenton.keegan@gmail.com 
    Licenced under GPLv3  
.LINK 
	https://github.com/bkeegan/ProfileArchiver
    License: http://www.gnu.org/copyleft/gpl.html
.EXAMPLE 
	ProfileArchiver -s "\\server\share\profiles" -d "\\archiveserver\shares\profiles" -To "ArchiveAlerts@contoso.com" -From "ArchiveAlerts@contoso.com" -smtp "smtp.contoso.com"
.EXAMPLE 

#> 
import-module activedirectory

Function ProfileArchiver 
{

	[cmdletbinding()]
	Param
	(
		[parameter(Mandatory=$true)]
		[alias("s")] #"source"
		[string]$foldersToCheck,
		
		[parameter(Mandatory=$true)]
		[alias("d")]#"destination"
		[string]$archiveLocation,
		
		[parameter(Mandatory=$true)]
		[alias("To")]
		[string]$emailRecipient,
		
		[parameter(Mandatory=$true)]
		[alias("From")]
		[string]$emailSender,
		
		[parameter(Mandatory=$true)]
		[alias("smtp")]
		[string]$emailServer,
		
		[parameter(Mandatory=$false)]
		[alias("Subject")]
		[string]$emailSubject="AutoArchive Report"
	)

	#$foldersToCheck = "\\limcollege.edu\root\profiles\undergrad"
	#$archiveLocation = "\\limcollege.edu\root\profiles\graduated\u"

	#stores profile information for profiles with no matching AD user and no abnormalities in the ACL
	$usersNotExist = @()

	#stores profile information for profiles with abnormal ACL. will be reported on for manual intervention
	$foldersWithAbnormalACL = @()

	#stores profile paths of profiles that were unable to archive successfully - will be reported on for manual intervention
	$errorArchiving =@()

	#stores profile paths of profiles that archived successfully but could not be deleted - will be reported on for manual intervention
	$errorDeleting =@()

	#stores profile paths that were successfully archived and originals were deleted. 
	$successArchiveDelete = @()


	$profileFolders = get-childitem -Directory -path $foldersToCheck

	#datestamp - a folder will be created under the archive location where old profiles will be archived to. This is to prevent issues and/or data being overwritten from consectuive archive attempts
	#each archive attempt should be a new file location
	[string]$dateStamp = Get-Date -UFormat "%Y%m%d_%H%M%S"


	foreach($folder in $profileFolders)
	{
		$userToCheck = $folder.Name
		Try
		{ 
			#profiles should be named the same as the username. This checks active directory for a name matching the profile name. If a user is returned, then no action occurs. 
			#However if the user does not actually exist on the domain, this cmdlet will return an error and the code under the Catch codeblock is executued.
			Get-ADuser $userToCheck | Out-Null
		}
		Catch
		{
			#retrieves the ACL of the profile in question. The ACL will be checked for abnormalities that might indicate a special situation where autoarchiving is not desired.
			$ACLToCheck = Get-ACL $folder.FullName
			#splits the ACL entries into an array (`r`n chiecks for carriage returns or new lines - this is based on the format the the cmdlet Get-ACL returns)
			$ACLEntries = $ACLToCheck.AccessToString.Split("`r`n")
			
			#sets default values, necessary to ensure values do not carry over from previous profile 
			$abnormalEntries = $false
			$brokenSID = $false
			
			
			Foreach($ACLEntry in $ACLEntries)
			{
				switch -regex ($ACLEntry)
				{
					#expected ACL entries to ignore - if additional ACL entries are identified as expected, add to here
					"CREATOR OWNER Allow  FullControl" {}
					"NT AUTHORITY\\SYSTEM Allow  FullControl" {}
					"LIM\\User Profile IT Access Allow  FullControl" {}
					"BUILTIN\\Administrators Allow  FullControl" {}
					"LIM\\bkadmin Allow  FullControl" {}
					"LIM\\Domain Admins Allow  FullControl" {}
					"CREATOR OWNER Allow  268435456" {}
					"BUILTIN\\Users Allow  CreateFiles" {}
					"BUILTIN\\Users Allow  ReadAndExecute, Synchronize" {}
					"BUILTIN\\Users Allow  AppendData" {}
					#regex to detect broken SID
					"S-1-5.+" {
						
						$brokenSID = $true
					}
					
					#if entry is not expected, or not a broken SID. ACL is not normal. 
					default {
					
						$abnormalEntries = $true 
					}
					
				}
				
			
			}
			if($abnormalEntries -eq $true)
			{
				$foldersWithAbnormalACL += $folder.FullName
			}
			
			if(($brokenSID -eq $true) -and ($abnormalEntries -eq $false))
			{
				
				$archError = $false
				
				if(!(Test-Path "$archiveLocation\$dateStamp"))
				{
					New-Item -Type Directory -Path "$archiveLocation\$dateStamp" | Out-Null
				}
				
				Try
				{
					$usersNotExist += $folder.Fullname
					Add-Type -Assembly "System.IO.Compression.FileSystem" ;
					[System.IO.Compression.ZipFile]::CreateFromDirectory("$($folder.FullName)", "$archiveLocation\$dateStamp\$userToCheck.zip") ;
				}
				Catch
				{
					$archError = $true
					$errorArchiving += $Folder.FullName
				}

				if(!($archError))
				{
					$deleteError = $false
					Try
					{
						#Remove-Item $folder.Fullname -Force -Recurse
					}
					Catch
					{
						$errorDeleting += $folder.FullName
						$deleteError = $true
					}
					
					if(!($deleteError))
					{
						$successArchiveDelete += $folder.FullName
					}
				}	
			}
		}
	}

	#special builtin variable "Output Field Seperator" 
	#default is a single whitespace, change below makes it a new line. This makes it so when the arrays are put in the here-string each entry is put on a new line.
	$ofs = "`r`n"

#string cannot be indented because tab will be interpreted in the string output.
$emailBody = "
=======================================ABNORMAL ACL====================================
THESE PATHS LEAST ONE ACL ENTRY THAT IS NOT A SYSTEM ACCOUNT OR A BROKEN SID. 
TYPICALLY THIS IS ANOTHER USER ACCOUNT. MANUAL INTERVENTION IS REQUIRED.

$foldersWithAbnormalACL
================================FOLDERS UNABLE TO ARCHIVE==============================
THE ZIP OPERATION FAILED ON THE FOLLOWING PATHS. 
ATTEMPT MANUAL ZIP AND COPY TO ARCHIVE LOCATION. DELETE ORIGINAL PATH ONCE COMPLETED 

$errorArchiving
===================================UNABLE TO DELETE======================================
PATHS BELOW WERE SUCCESSFULLY ARCHIVED BUT COULD NOT BE DELETED. 
ENTERIES HERE SHOULD BE DELETED MANUALLY.

$errorDeleting
====================FOLDERS SUCCESSFULLY ARCHIVED AND DELETED==========================
PATHS BELOW WERE SUCCESSFULLY ARCHIVED AND ORIGINALS WERE DELETED.
NO ADDITIONAL ACTION REQUIRED.

$successArchiveDelete"
	
	
	Send-MailMessage -To $emailRecipient -Subject $emailSubject -smtpServer $emailServer -From $emailSender -body $emailBody
}

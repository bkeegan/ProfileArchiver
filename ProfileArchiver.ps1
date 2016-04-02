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
#> 

#Imports
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
		[string]$emailSubject="AutoArchive Report",
		
		[parameter(Mandatory=$false)]
		[alias("body")]
		[string]$emailBody="Archive Report - See Attachment"
	)

	$archiveResults = new-object 'system.collections.generic.dictionary[string,string]'	
	$profileFolders = get-childitem -Directory -path $foldersToCheck

	#datestamp - a folder will be created under the archive location where old profiles will be archived to. This is to prevent issues and/or data being overwritten from consectuive archive attempts
	#each archive attempt should be a new file location
	[string]$dateStamp = Get-Date -UFormat "%Y%m%d_%H%M%S"
	$tempFolder = get-item env:temp

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
					"BUILTIN\\Administrators Allow  FullControl" {}
					"LIM\\Domain Admins Allow  FullControl" {}
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
				$archiveResults.Add($folder.FullName,"Abnormal ACL")

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
					$archiveResults.Add($folder.FullName,"ArchiveError")
				}

				if(!($archError))
				{
					$deleteError = $false
					Try
					{
						Remove-Item $folder.Fullname -Force -Recurse
					}
					Catch
					{
						$archiveResults.Add($folder.FullName,"DeleteError")
						$deleteError = $true
					}
					
					if(!($deleteError))
					{
						$archiveResults.Add($folder.FullName,"Success")
					}
				}	
			}
		}
	}
	
	$archiveResults.GetEnumerator() | Sort-Object -property Value | ConvertTo-HTML | Out-File "$($tempFolder.value)\$dateStamp-Report.html"
	Send-MailMessage -To $emailRecipient -Subject $emailSubject -smtpServer $emailServer -From $emailSender -body $emailBody -Attachments "$($tempFolder.value)\$dateStamp-Report.html"

}

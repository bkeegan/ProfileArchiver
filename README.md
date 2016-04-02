# ProfileArchiver
ProfileArchiver is a PowerShell script designed to automatically archive profile folders created by Group Policy's Folder Redirection policies. This script was designed with a particular work-flow in mind where a user account is deleted when they leave the organization. This script performs an Active Directory query for the user for which the profile is named. If this user acount is not found, it further checks for abnormal ACL entries. Abnormal ACL enteries are considered to be any entry that's not defined in the script or a broken SID (resulting from a deleted user account) This script can be modified based on the target profile shares to include additional ACL entries that should exist on all profiles. 

If the script concludes that a profile has no user by the name, has a broken SID in it's ACL and no additional ACL entries beyond the standard set, it will be become subject to archival. Any entries with non-standard ACL entries will be skipped for archival and reported on.

Archive location can be defined as a parameter. A folder will be created with a current date/timestamp in the archive location and each profile will be put in a .zip file and copied to this location. If .zip creation/copy is successful it will attempt to delete the original. If .zip creation/copy is not successful, it will be reported on. If deletion is non successful, it will also be reported on.

A final report will be emailed to a specified contact with an .html report attached, listing the outcome of each profile folder that does not have a user by that same name. 

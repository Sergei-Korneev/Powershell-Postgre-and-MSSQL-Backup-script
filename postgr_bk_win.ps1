# Windows Postgre backup and ftp upload for Windows
# Sergei Korneev 2024



##################################################################################################
# Config
##################################################################################################



#Get Script Path

#$MyInvocation.MyCommand.Path
 
#Get script folder

$spath  = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

 
# Ftp Credentials

$ftpuser = "rsync"

$ftphost = "192.168.1.101"

$ftppath = "1CBit"

$ftppassfile = "ftp.pwd"

# DB Credentials

$dbuser = "postgres"

$dbhost = "127.0.0.1"

$dbport = "5432"

$pgbin = "C:\Program Files\PostgreSQL\15\bin\pg_dump.exe"

$DBnamesarray = @('zarmed','zm_tests')

$dbprefix = "db_bk_"

$BackupPath = "c:\DbBk"

$dbpassfile = "db.pwd"

if ( -not (Test-Path  $BackupPath)  -eq "True " ){
   Write-Host "$BackupPath does not exist, creating..."
   New-Item -ItemType "directory" -Path "$BackupPath"    
}

# Delete backups older than 

$Days=80;

##################################################################################################
# Credentials
##################################################################################################

function GetSetCredentials($Action, $FileName){

if ($Action -eq  "set") {

##### Create file to store password into profile of account that will execute the manual tasks/scheduled tasks
# Path for password file
$AccountFile = "$BackupPath\$FileName"

# Check for password file
if ((Test-Path $AccountFile) -eq "True") {
Write-Host "The file $AccountFile exist. Skipping credential setup"
}
else {
Write-Host ("The value $AccountFile not found," +
" creating credentials file.")

# Create credential object by prompting user for data. Only the password is used. For user name use $username.  As per post https://stackoverflow.com/questions/13992772/how-do-i-avoid-saving-usernames-and-passwords-in-powershell-scripts
$Credential = Get-Credential

# Encrypt the password to disk
$Credential.Password | ConvertFrom-SecureString | Out-File "$AccountFile"
}


}


if ($Action -eq  "get") {
# Path for password file
$AccountFile = "$BackupPath\$FileName"

# Check for password file
if ((Test-Path $AccountFile) -eq "True") {

##### Read password for DBhost login #####
# Read password from file
$SecureString = Get-Content $AccountFile | ConvertTo-SecureString

if ($SecureString -eq $null){
  Write-Host "The file $AccountFile is empty. Skipping credential request"
  exit
}

# Create credential object programmatically
$NewCred = New-Object System.Management.Automation.PSCredential("Account",$SecureString)

# Variable password in clear text
$pass = $NewCred.GetNetworkCredential().Password
 
return $pass

}
else {
Write-Host ("The file $AccountFile not found.")
 
}

}



}


function CheckDiskSpace([string] $BackupPath) {
 
    $currentDrive = Split-Path -qualifier $BackupPath;
    $logicalDisk = Get-WmiObject Win32_LogicalDisk -filter "DeviceID = '$currentDrive'";
 
    if ($logicalDisk.DriveType -eq 3) {
        $freeSpace = $logicalDisk.FreeSpace;
 
        $lastBackup = Get-ChildItem -Directory $BackupPath | sort CreationTime -desc | select -f 1;
        $lastBackupDir = Join-Path $BackupPath $lastBackup;
        $totalSize = Get-ChildItem -path $lastBackupDir | Measure-Object -property length -sum;
 
        if($totalSize.sum -ge $freeSpace){
            $sizeMB = "{0:N2}" -f ($totalSize.sum / 1MB) + " MB";
            $spaceError = "Not enough free space on  $BackupPath, last backup size is $lastBackup $sizeMB";
            echo $spaceError >> $LogFile;
            Exit 1;
        }
    }
}

##################################################################################################
# FTP Client
##################################################################################################



function uploadToFTPServer($remote, $local) {
 

$ftppass = GetSetCredentials  "get" $ftppassfile

if ($ftppass -eq $null){
Write-Host  "Set ftp password"
exit
}



$ftp = "ftp://${ftpuser}:${ftppass}@${ftphost}/$remote"

"ftp url: $ftp"

$webclient = New-Object System.Net.WebClient
$uri = New-Object System.Uri($ftp)

"Uploading to ftp $File..."

$webclient.UploadFile($uri, $local)


}


function downloadFromFTPServer($remote, $local) {

$ftppass = GetSetCredentials  "get" "ftp.pwd"

if ($ftppass -eq $null){
Write-Host  "Set ftp password"
exit
}




$ftp = "ftp://${ftpuser}:${ftppass}@${ftphost}/$remote"

"ftp url: $ftp"

$webclient = New-Object System.Net.WebClient
$uri = New-Object System.Uri($ftp)

"Downloading $File..."

$webclient.DownloadFile($uri, $local)
}


# Delete files older than $days

function DeleteOlderThan() {
 Write-Host  "
 
 Deleting all backups older than $Days...
 "
Get-ChildItem -path $BackupPath | 
        where {!$_.PSIsContainer  -and $_.FullName -ne $ftppassfile -and $_.FullName -ne $dbpassfile  -and $_.creationtime -lt $(Get-Date).adddays($Days*-1)}  | 
        Remove-Item -Force -Recurse;

Get-ChildItem -path $BackupPath"\*" | 
    ?{ $_.PSIsContainer  -and $_.FullName -ne $ftppassfile -and $_.FullName -ne $dbpassfile  -and $_.creationtime -lt $(Get-Date).adddays($Days*-1)} | 
    Remove-Item -Force -Recurse;
}

##################################################################################################
# BackUp
##################################################################################################

function BackUpDb(){

 
if ( -not  (Test-Path $pgbin) -eq "True") {
 Write-Host "The file $pgbin does not exist. Skipping."
 exit
}




$dbpass = GetSetCredentials  "get" "$dbpassfile"

if ($dbpass -eq $null){
Write-Host  "Set database password"
exit
}

$env:PGPASSWORD = $dbpass




foreach ($dbname in $DBnamesarray) {


 $dbfname = "${dbprefix}${dbname}_$(Get-Date -format "yyyy.MM.dd_HH-mm-ss")"

 Write-Host "Backuping the database $dbname to  $BackupPath with name $dbfname ..."

 echo "Database $dbname backup started at $(Get-Date -format "yyyy.MM.dd_HH-mm-ss")" >>"$BackupPath\backuplog.log"

 Start-Process "$pgbin"  -ArgumentList "-h $dbhost  -p $dbport -d $dbname -Fc  -U $dbuser -f $BackupPath\$dbfname "   -Wait  -NoNewWindow 
 # -RedirectStandardError "$BackupPath\dump.log"
  
 if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne  $null ){
  Write-Host "Unsuccesful! ($LASTEXITCODE)"
  echo  "Unsuccesful! ($LASTEXITCODE)"  >>"$BackupPath\backuplog.log"
  return 1
 }else{
 Write-Host "
 Calculating MD5 hash...
 "
 $md5 = [String](Get-FileHash "$BackupPath\$dbfname" -Algorithm MD5).Hash
 Move-Item -Path "$BackupPath\$dbfname" -Destination "$BackupPath\${dbfname}_${md5}"
 
 uploadToFTPServer "/$ftppath/${dbfname}_${md5}" "$BackupPath\${dbfname}_${md5}"
 } 


}

}




##################################################################################################
# Cmd Line
##################################################################################################

if ($args[0] -eq "SetFtpPass") {
   GetSetCredentials  "set" "$ftppassfile"
}elseif ($args[0] -eq "SetDBPass") {
   GetSetCredentials  "set" "$dbpassfile"
}elseif ($args[0] -eq "BackUpDb") {
   BackUpDb
}elseif ($args[0] -eq "Purge") {
   DeleteOlderThan
}else{
  Write-Host "
  Usage:

  script.ps1 SetFtpPass - set secured ftp password
  
  script.ps1 SetDBPass - set secured database password
  
  script.ps1 BackUpDb - perform backup
  
  script.ps1 Purge - delete files older than $Days days
  
  "
  exit
}


<#

Script to pull a recent, 13 day server utilization report for Virtual Machines in CenturyLink Cloud

Author: Matt Schwabenbauer
Created: March 30, 2016
E-mail: Matt.Schwabenbauer@ctl.io

Step 1 -
In order to enable scripts on your machine, first run the following command:
Set-ExecutionPolicy RemoteSigned

Step 2 - Press F5 to run the script

Step 3 - Enter your API Key 
    This can be found on the API section in Control
    If your name is not listed among the API users, create a ticket requesting access

Step 4 - Enter your API password

Step 5 - Enter your control portal account login information

Step 6 - Enter Customer account alias

Step 7 - The Output file will be in C:\users\Public\CLC\

#>

Write-Verbose "This script will collect server metrics and account utilization data for CenturyLink Cloud resources over the past 13 days." -Verbose
Write-Verbose "It will also identify any machines that had an average CPU, RAM or HD utilization exceeding 70%, or under 25% over a 24 hour period at any time in the past 13 days." -Verbose
Write-Verbose "An output file showing resource counts and average utilization over a 13 day time period will be opened at the end of the operation." -Verbose

# Get the parent account alias from the user

$AccountAlias = Read-Host "Please enter a parent account alias"

#generate very specific date and time for final exported file's filename

$genday = Get-Date -Uformat %a
$genmonth = Get-Date -Uformat %b
$genyear = Get-Date -Uformat %Y
$genhour = Get-Date -UFormat %H
$genmins = Get-Date -Uformat %M
$gensecs = Get-Date -Uformat %S

$gendate = "Generated-$genday-$genmonth-$genyear-$genhour-$genmins-$gensecs"

<# Create Directory #>

$dir = "C:\users\Public\CLC\$AccountAlias\WeeklyUtilizationReports\$gendate\"

Write-Verbose "Creating the directory $dir. Note: a number of temp files will be created in this location and then deleted at the end of the operation." -Verbose
Write-Verbose "Reports identifying Virtual Machines with high or low resource utilization will be located in $dir at the end of the operation. There will also be a report with utilization metrics over the same time period for all Virtual Machines in $accountalias." -Verbose

New-Item -ItemType Directory -Force -Path $dir

$filename = "$dir\$accountAlias-ServerMetrics-$gendate.csv"

#Create a file name for the temp file that will hold the group names

$date = Get-Date -Format Y
$groupfilename = "$dir\$AccountAlias-AllGroups-$date.csv"
$aliasfilename = "$dir\$AccountAlias-AllAliases-$date.csv"

<# API V1 Login #>

Write-Verbose "Logging in to CenturyLink Cloud v1 API." -Verbose

$APIKey = Read-Host "Please enter your CenturyLink Cloud v1 API Key"
$APIPass = Read-Host "Please enter your CenturyLink Cloud v1 API Password"

$body = @{APIKey = $APIKey; Password = $APIPass } | ConvertTo-Json

$restreply = Invoke-RestMethod -uri "https://api.ctl.io/REST/Auth/Logon/" -ContentType "Application/JSON" -Body $body -Method Post -SessionVariable session 
$global:session = $session 
Write-Host $restreply.Message

if ($restreply.StatusCode -eq 100)
{
   Write-Verbose "Error logging in to CLC API V1." -Verbose
   exit 1
}
Else
{
}

<# API V2 Login: Creates $HeaderValue for Passing Auth (highlight and press F8) #>

Write-Verbose "Logging in to CenturyLink Cloud v2 API." -Verbose

try
{
$global:CLCV2cred = Get-Credential -message "Please enter your Control portal Logon" -ErrorAction Stop 
$body = @{username = $CLCV2cred.UserName; password = $CLCV2cred.GetNetworkCredential().password} | ConvertTo-Json 
$global:resttoken = Invoke-RestMethod -uri "https://api.ctl.io/v2/authentication/login" -ContentType "Application/JSON" -Body $body -Method Post 
$HeaderValue = @{Authorization = "Bearer " + $resttoken.bearerToken} 
}
catch
{
    exit 2
}

# Create variable for data centers

$datacenterList = "DE1,GB1,GB3,SG1,WA1,CA1,UC1,UT1,NE1,IL1,CA3,CA2,VA1,NY1"
$datacenterList = $datacenterList.Split(",")

# Create a bunch of variables to be used in the functions. Null them out in case this script is run twice in a row.

$val=$null
$result = $null
$groups = $null
$allGroups = $null
$serverNames = $null
$allrows = @()
$allmetrics = @()

#Function to return a list of hardware groups

function getServers
{
    $Location = $args[0]
    $JSON = @{AccountAlias = $AccountAlias; Location = $Location} | ConvertTo-Json 
    $result = Invoke-RestMethod -uri "https://api.ctl.io/REST/Server/GetAllServersForAccountHierarchy/" -ContentType "Application/JSON" -Method Post -WebSession $session -Body $JSON 
    $result.AccountServers.Servers | Export-Csv "$dir\RawData.csv" -Append -ErrorAction SilentlyContinue -NoTypeInformation
    $allGroups += $result.AccountServers.Servers.HardwareGroupUUID
    $result.AccountServers | Export-Csv "$dir\rawdata2.csv" -Append -ErrorAction SilentlyContinue -NoTypeInformation
}

# Run getServers for each data center

Foreach ($i in $datacenterList)
{
    getServers($i)
}

# Import the temp file with the group names, filter it for just the hardware groups, then export it with a nice, readable and unique file name

Import-Csv "$dir\RawData.csv" | Select HardwareGroupUUID -Unique  | Export-Csv $groupfilename  -NoTypeInformation
Import-Csv "$dir\RawData2.csv" | Select AccountAlias -Unique  | Export-Csv $aliasfilename  -NoTypeInformation

# Import the parsed list of groups to a variable

$groups = Import-csv $groupfilename
$aliases = Import-csv $aliasfilename

<# Begin main script #>

Write-Verbose "Beginning data collection for parent account alias $AccountAlias." -Verbose

Write-Verbose "Warning: This operation may take up to an hour, depending on the amount of Virtual Machines being queried." -Verbose

<# Get server metrics for today -1 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-1).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-1).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-1).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
   
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
  $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for today -1

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias." -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow


<# Get server metrics for today -2 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-2).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-2).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-2).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for today -2

    Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

<# Get server metrics for today -3 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-3).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-3).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-3).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

<# Get server metrics for today -4 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-4).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-4).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-4).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -5 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-5).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-5).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-5).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -6 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-6).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-6).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-6).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -7 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-7).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-7).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-7).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -8 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-8).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-8).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-8).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose

  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -9 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-9).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-9).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-9).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -10 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-10).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-10).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-10).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -11 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-11).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-11).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-11).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -12 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-12).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-12).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-12).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

  <# Get server metrics for today -13 #>

# declare date for storing this day's data
$countDate = ((Get-Date).addDays(-13).toUniversalTime()).ToString("yyyy-MM-dd")

# Declare start and end date for the function that will return the server metrics from the API
$start = ((get-date).addDays(-13).ToUniversalTime()).ToString("yyyy-MM-dd")+"T00:00:01.000z"
$end = ((get-date).addDays(-13).ToUniversalTime()).ToString("yyyy-MM-dd")+"T23:59:59.000Z"

# Create a variable outside the loop for the day of data you are pulling

$theserows = @()

# Foreach loop to get the server metrics data from the API

Foreach ($alias in $aliases)
{
    $result = $null
    $writeAlias = $Alias.AccountAlias
    Write-Verbose "Processing data for $countdate for subaccount $writeAlias." -Verbose
Foreach ($group in $groups)
{
    $result = $null
    $thisgroup = $group.HardwareGroupUUID
    $thisalias = $alias.AccountAlias
    $url = "https://api.ctl.io/v2/groups/$thisalias/$thisgroup/statistics?type=hourly&start=$start&end=$end&sampleInterval=23:59:58"
    try
    {
     $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    }
    catch
    {
    }
    if ($result)
    {

  Foreach ($i in $result)
  {
    $totalstorageusage = $null
    Foreach ($j in $i.stats.guestDiskUsage)
    {
    $StorageUsage = $j.consumedMB
    $totalstorageusage += $storageusage
    }
  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Server Name" -Value $i.name 
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date & Time" -Value $i.stats.timestamp
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUAmount" -Value $i.stats.cpu
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPUUtil" -Value $i.stats.cpuPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryMB" -Value $i.stats.memoryMB
  $thisrow | Add-Member -MemberType NoteProperty -Name "MemoryUtil" -Value $i.stats.memoryPercent
  $thisrow | Add-Member -MemberType NoteProperty -Name "Storage" -Value $i.stats.diskUsageTotalCapacityMB
  if ($totalstorageusage -eq $null)
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value "0"
  }
  else
  {
    $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUsage" -Value $totalstorageusage
  }
  $storageutilization = (($totalstorageusage)/$i.stats.diskUsageTotalCapacityMB)*100
  $storageutilization = "{0:N0}" -f $storageutilization
  $thisrow | Add-Member -MemberType NoteProperty -Name "StorageUtil" -Value $storageutilization
  $allrows += $thisrow
    $theserows += $thisrow
  } # end foreach result
    } # end if result
    else
    { 
    }
} # end foreach group
} # end foreach alias

  #Calculate metrics for this day

  Write-Verbose "Calculating server metrics for $countdate for $AccountAlias " -Verbose
  
  $allCPU = $theserows.CPUAmount | Measure-Object -Sum
  $allCPU = $allCPU.sum
  $allRAM = $theserows.MemoryMB | Measure-Object -Sum
  $allRAM = ($allRAM.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $allStorage = $theserows.Storage | Measure-Object -Sum
  $allStorage = ($allStorage.sum)/1000
  $allRAM = "{0:N0}" -f $allRAM
  $averageCPU = $theserows.CPUutil | Measure-Object -Average
  $averageCPU = $averageCPU.Average
  $averageCPU = "{0:N1}" -f $averageCPU
  $averageRAM = $theserows.MemoryUtil | Measure-Object -Average
  $averageRAM = $averageRAM.Average
  $averageRAM = "{0:N1}" -f $averageRAM
  $averageStorage = $theserows.StorageUtil | Measure-Object -Average
  $averageStorage = $averageStorage.Average
  $averageStorage = "{0:N1}" -f $averageStorage

  $thisrow = New-object system.object
  $thisrow | Add-Member -MemberType NoteProperty -Name "Date" -value $countDate
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated CPUs" -value $allCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "CPU Utilization" -value $averageCPU
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated RAM" -value $allRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "RAM Utilization" -value $averageRAM
  $thisrow | Add-Member -MemberType NoteProperty -Name "Allocated HD GB" -value $allStorage
  $thisrow | Add-Member -MemberType NoteProperty -Name "HD Utilization" -value $averageStorage

  $allMetrics += $thisrow

# Filter high/low utilization servers

Write-Verbose "Calculating servers with high resource utilization" -Verbose

$highCPUUtil = @()
$highRAMUtil = @()
$highHDUtil = @()
$lowCPUUtil = @()
$lowRAMUtil = @()
$lowHDUtil = @()

$highCPUUtil += $allrows | Select-Object | Where-Object {[int]$_.CPUUtil -gt 70}
$highRAMUtil += $allrows | Select-Object | Where-Object {[int]$_.MemoryUtil -gt 70}
$highHDUtil += $allrows | Select-Object | Where-Object {[int]$_.StorageUtil -gt 70}

$lowCPUUtil += $allrows | Select-Object | Where-Object {[int]$_.CPUUtil -lt 25}
$lowRAMUtil += $allrows | Select-Object | Where-Object {[int]$_.MemoryUtil -lt 25}
$lowHDUtil += $allrows | Select-Object | Where-Object {[int]$_.StorageUtil -lt 25}

# Check to see if there aren't any servers with high/ow utilization, and give the user some direction if so

if (!$highCPUUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with CPU utilization over 70%"
    $highCPUUtil = $thisrow
  }

  if (!$highRAMUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with RAM utilization over 70%"
    $highRAMUtil = $thisrow
  }

  if (!$highHDUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with storage utilization over 70%"
    $highHDUtil = $thisrow
  }

  if (!$lowCPUUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with CPU utilization under 25%"
    $highCPUUtil = $thisrow
  }

  if (!$lowRAMUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with RAM utilization under 25%"
    $highRAMUtil = $thisrow
  }

  if (!$lowHDUtil)
  {
    $thisrow = New-object system.object
    $thisrow | Add-Member -MemberType NoteProperty -Name "No Data" -Value "No servers were identified with storage utilization under 25%"
    $highHDUtil = $thisrow
  }

# export everything to a few CSVs

Write-Verbose "Exporting Server Metrics data for $AccountAlias." -Verbose

$allrows | Select-Object @{Name="Server Name";Expression={$_."Server Name"}}, @{Name="Date & Time";Expression={$_."Date & Time"}}, @{Name="Total CPUs";Expression={$_."CPUAmount"}}, @{Name="CPU Utilization %";Expression={$_."CPUUtil"}}, @{Name="Total Memory in MB";Expression={$_."MemoryMB"}}, @{Name="Memory Utilization %";Expression={$_."MemoryUtil"}}, @{Name="Total Storage in MB";Expression={$_."Storage"}}, @{Name="Total Storage Usage in MB";Expression={$_."StorageUsage"}}, @{Name="Storage Utilization %";Expression={$_."StorageUtil"}} | export-csv $filename -NoTypeInformation

Write-Verbose "Exporting the past 13 days of daily utilization metrics for $AccountAlias." -Verbose

$allMetrics | export-csv "$dir\$AccountAlias-UtilizationMetrics-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting High CPU Utilization data for $AccountAlias." -Verbose

$highCPUUtil | export-csv "$dir\$AccountAlias-HighCPU-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting High RAM Utilization data for $AccountAlias." -Verbose

$highRAMUtil | export-csv "$dir\$AccountAlias-HighRAM-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting High HD Utilization data for $AccountAlias." -Verbose

$highHDUtil | export-csv "$dir\$AccountAlias-HighHD-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting low CPU Utilization data for $AccountAlias." -Verbose

$lowCPUUtil | export-csv "$dir\$AccountAlias-LowCPU-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting low RAM Utilization data for $AccountAlias." -Verbose

$lowRAMUtil | export-csv "$dir\$AccountAlias-LowRAM-$gendate.csv" -NoTypeInformation

Write-Verbose "Exporting low HD Utilization data for $AccountAlias." -Verbose

$lowHDUtil | export-csv "$dir\$AccountAlias-LowHD-$gendate.csv" -NoTypeInformation

# open the CSV we just exported

Write-Verbose "Opening Server Utilization Metrics for $AccountAlias." -Verbose
Write-Verbose "The data will be stored locally at $dir." -Verbose

$file = & "$dir\$AccountAlias-UtilizationMetrics-$gendate.csv"
 
# log out of v1 API

Write-Verbose "Logging out of API" -Verbose

$restreply = Invoke-RestMethod -uri "https://api.ctl.io/REST/Auth/Logout/" -ContentType "Application/JSON" -Method Post -SessionVariable session 
$global:session = $session
Write-Host $restreply.Message

# delete temp files

Write-Verbose "Deleting temp files" -Verbose

Remove-Item "$dir\RawData.csv"
Remove-Item "$dir\RawData2.csv"
Remove-Item $groupfilename
Remove-Item $aliasfilename

Write-Verbose "Operation Complete." -verbose
Write-Verbose "Reports identifying Virtual Machines with high or low resource utilization will be located in $dir. There will also be a report with utilization metrics over a 13 day period for all Virtual Machines in $accountalias." -Verbose

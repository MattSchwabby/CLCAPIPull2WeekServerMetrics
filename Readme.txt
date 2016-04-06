Goal

Instructions on how to run an attached PowerShell script which will generate a 13 day server utilization report, rolling up to the parent account alias.

The report will display the past 13 days of resource counts for the given account alias, including subaccounts. You will be given a report containing resource and utilization metrics for every server in the account for the past 13 days. Reports will also be generated identifying servers with average CPU, RAM or Storage utilization over 70% and under 25% over 24 hours for the time period.

 

Audience

Any CenturyLink Cloud employee

CenturyLink Cloud customers

 

Prerequisites

Access to the Control Portal with at least account viewer or billing manager privileges

CenturyLink Cloud API v1 Key and Password, associated with your Control Portal account

PowerShell

Running either locally on a Windows laptop or remotely in a Windows Server Virtual Machine

It is recommended that you run this script from the ISE with administrator privileges

An application that can open .csv files

 

Steps

In order to enable scripts on your machine, first run the following command in PowerShell:
Set-ExecutionPolicy RemoteSigned
Note: You may need to launch PowerShell with elevated privileges
Download the PowerShell script "CLCAPIPull2weekServerMetricsV2 - Public.ps1" that is attached to this article
Run the script you just downloaded
Enter the alias of the account you will be creating the report for
Enter your API v1 key
Enter your API v1 Password
Enter your control portal username
Enter your control portal password
The metrics over the past 13 days will be displayed in a .csv file. This file, and reports identifying high/low resource utilization as well as metrics over the time period for each server will be stored locally at C:\Users\Public\CLC\
 

Version History

4/6/2016 - Script updated - Matt Schwabenbauer

4/4/2016 - Version 3 uploaded - Matt Schwabenbauer

4/1/2016 - Version 2 uploaded - Matt Schwabenbauer

Support

Matt.Schwabenbauer@ctl.io

@mattschwabby on Slack
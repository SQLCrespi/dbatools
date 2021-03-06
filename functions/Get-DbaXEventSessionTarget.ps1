﻿function Get-DbaXEventSessionTarget {
 <#
	.SYNOPSIS
	Get a list of Extended Events Session Targets

	.DESCRIPTION
	Retrieves a list of Extended Events Session Targets
	
	.PARAMETER SqlInstance
	SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

	.PARAMETER SqlCredential
	SqlCredential object to connect as. If not specified, current Windows login will be used.

	.PARAMETER Session
	Only return a specific session. This parameter is auto-populated.
	
	.PARAMETER Target
	Only return a specific target. 
	
	.PARAMETER SessionObject
	Internal pipeline parameter
	
	.PARAMETER Silent
	If this switch is enabled, the internal messaging functions will be silenced.

	.NOTES
	Tags: Xevent
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
	.LINK
	https://dbatools.io/Get-DbaXEventSessionTarget
	
	.EXAMPLE
	Get-DbaXEventSessionTarget -SqlInstance ServerA\sql987 -Session system_health

	Shows targets for the system_health session on ServerA\sql987

	.EXAMPLE
	Get-DbaXEventSession -SqlInstance sql2016 -Session system_health | Get-DbaXEventSessionTarget
	
	Returns the targets for the system_health session on sql2016
	
	.EXAMPLE
	Get-DbaXEventSession -SqlInstance sql2016 -Session system_health | Get-DbaXEventSessionTarget -Target package0.event_file
	
	Return only the package0.event_file target for the system_health session on sql2016 
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(ValueFromPipeline, ParameterSetName = "instance", Mandatory)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[string[]]$Session,
		[string[]]$Target,
		[parameter(ValueFromPipeline, ParameterSetName = "piped", Mandatory)]
		[Microsoft.SqlServer.Management.XEvent.Session[]]$SessionObject,
		[switch]$Silent
	)
	
	begin {
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null) {
			Stop-Function -Message "SMO version is too old. To collect Extended Events, you must have SQL Server Management Studio 2012 or higher installed."
			return	
		}
		
		function Get-Target {
			[CmdletBinding()]
			param (
				$Sessions,
				$Session,
				$Server,
				$Target
			)
			
			foreach ($xsession in $Sessions) {
				
				if ($null -eq $server) {
					$server = $xsession.Parent
				}
				
				if ($Session -and $xsession.Name -notin $Session) { continue }
				$status = switch ($xsession.IsRunning) { $true { "Running" } $false { "Stopped" } }
				$sessionname = $xsession.Name
				
				foreach ($xtarget in $xsession.Targets) {
					if ($Target -and $xtarget.Name -notin $Target) { continue }
					
					$files = $xtarget.TargetFields | Where-Object Name -eq Filename | Select-Object -ExpandProperty Value
					
					$filecollection = $remotefile = @()
					
					if ($files) {
						foreach ($file in $files) {
							if ($file -notmatch ':\\' -and $file -notmatch '\\\\') {
								$directory = $server.ErrorLogPath.TrimEnd("\")
								$file = "$directory\$file"
							}
							$filecollection += $file
							$remotefile += Join-AdminUnc -servername $server.netName -filepath $file
						}
					}
					
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name Session -Value $sessionname
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SessionStatus -Value $status
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name TargetFile -Value $filecollection
					Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile
					
					Select-DefaultView -InputObject $xtarget -Property ComputerName, InstanceName, SqlInstance, Session, SessionStatus, Name, ID, 'TargetFields as Field', PackageName, 'TargetFile as File', Description, ScriptName
				}
			}
		}
	}
	
	process {
		if (Test-FunctionInterrupt) { return }
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			$SqlConn = $server.ConnectionContext.SqlConnectionObject
			$SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
			$xsessionEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
			
			Write-Message -Level Verbose -Message "Getting XEvents Session Targets on $instance."
			
			$xsessions = $xsessionEStore.sessions
			
			if ($Session) {
				$xsessions = $xsessions | Where-Object { $_.Name -in $Session }
			}
			
			Get-Target -Sessions $xsessions -Session $Session -Server $server -Target $Target
		}
		
		if ((Test-Bound -ParameterName SqlInstance -Not)) {
			Get-Target -Sessions $SessionObject -Session $Session -Target $Target
		}
	}
}
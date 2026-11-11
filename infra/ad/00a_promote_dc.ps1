param([string]$Dsrm)
$ErrorActionPreference = 'Stop'
"== Install-WindowsFeature AD-Domain-Services"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Format-List Success,RestartNeeded,ExitCode
Import-Module ADDSDeployment
$s = ConvertTo-SecureString $Dsrm -AsPlainText -Force
"== Install-ADDSForest polycorp.test"
Install-ADDSForest -DomainName 'polycorp.test' -DomainNetbiosName 'POLYCORP' -ForestMode 'WinThreshold' -DomainMode 'WinThreshold' -InstallDns:$true -CreateDnsDelegation:$false -DatabasePath 'C:\Windows\NTDS' -LogPath 'C:\Windows\NTDS' -SysvolPath 'C:\Windows\SYSVOL' -SafeModeAdministratorPassword $s -NoRebootOnCompletion:$true -Force:$true -WarningAction SilentlyContinue | Format-List Status,Message,RebootRequired
shutdown /r /t 15 /c "Promotion AD DS"
"reboot scheduled"

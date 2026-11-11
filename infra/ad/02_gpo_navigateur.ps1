# GPO ordinateur : autoriser l'authentification integree (SPNEGO) vers sso.polycorp.test
Import-Module GroupPolicy
$n='PRJ-SSO-Navigateur'; $t='OU=Workstations,DC=polycorp,DC=test'
if (-not (Get-GPO -Name $n -ErrorAction SilentlyContinue)) { New-GPO -Name $n -Comment 'Projet 2 : SPNEGO vers Keycloak' | New-GPLink -Target $t | Out-Null }
# Internet Explorer / Windows : Site to Zone Assignment List -> zone 1 (Intranet local)
Set-GPRegistryValue -Name $n -Key 'HKLM\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings' -ValueName ListBox_Support_ZoneMapKey -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $n -Key 'HKLM\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMapKey' -ValueName 'http://sso.polycorp.test' -Type String -Value '1' | Out-Null
# Microsoft Edge : serveurs autorises pour l'authentification integree
Set-GPRegistryValue -Name $n -Key 'HKLM\SOFTWARE\Policies\Microsoft\Edge' -ValueName AuthServerAllowlist -Type String -Value 'sso.polycorp.test' | Out-Null
# Confort du labo : pas d'assistant de premier lancement d'Edge
Set-GPRegistryValue -Name $n -Key 'HKLM\SOFTWARE\Policies\Microsoft\Edge' -ValueName HideFirstRunExperience -Type DWord -Value 1 | Out-Null
(Get-GPInheritance -Target $t).GpoLinks | Format-Table DisplayName,Enabled,Target -AutoSize | Out-String -Width 160
Get-GPRegistryValue -Name $n -Key 'HKLM\SOFTWARE\Policies\Microsoft\Edge' | Format-Table ValueName,Value,Type -AutoSize | Out-String
Get-GPRegistryValue -Name $n -Key 'HKLM\Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMapKey' | Format-Table ValueName,Value -AutoSize | Out-String

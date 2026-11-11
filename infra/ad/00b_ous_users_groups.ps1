param([string]$UserPass)
$ErrorActionPreference = 'Continue'
Import-Module ActiveDirectory; Import-Module GroupPolicy
$base = 'DC=polycorp,DC=test'
Add-DnsServerForwarder -IPAddress 168.63.129.16 -ErrorAction SilentlyContinue
foreach ($ou in 'People','Groups','Workstations','Tests') {
  if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'")) { New-ADOrganizationalUnit -Name $ou -Path $base -ProtectedFromAccidentalDeletion $true } }
$pw = ConvertTo-SecureString $UserPass -AsPlainText -Force
$users = @(
 @('Alice','Martin','amartin','CEO','alice.martin@polycorp.com'),
 @('Bob','Dupont','bdupont','Lead Developer','bob.dupont@polycorp.com'),
 @('Clara','Durand','cdurand','Developer','clara.durand@polycorp.com'),
 @('David','Bernard','dbernard','Marketing Manager','david.bernard@polycorp.com'),
 @('Emma','Petit','epetit','Support Engineer','emma.petit@polycorp.com'))
foreach ($u in $users) { $n = "$($u[0]) $($u[1])"
  if (-not (Get-ADUser -Filter "sAMAccountName -eq '$($u[2])'")) {
    New-ADUser -Name $n -GivenName $u[0] -Surname $u[1] -DisplayName $n -SamAccountName $u[2] -UserPrincipalName "$($u[2])@polycorp.test" -Title $u[3] -EmailAddress $u[4] -Path "OU=People,$base" -AccountPassword $pw -ChangePasswordAtLogon $true -Enabled $true } }
foreach ($g in 'Admins','Developers','Staff') {
  if (-not (Get-ADGroup -Filter "Name -eq '$g'")) { New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Groups,$base" } }
Add-ADGroupMember Admins -Members amartin
Add-ADGroupMember Developers -Members bdupont,cdurand
Add-ADGroupMember Staff -Members amartin,bdupont,cdurand,dbernard,epetit
Set-ADUser amartin -OfficePhone '1 23 45 67 89'
"== OUs"; Get-ADOrganizationalUnit -Filter * | Sort-Object Name | Format-Table Name,DistinguishedName -AutoSize | Out-String -Width 160
"== People"; Get-ADUser -SearchBase "OU=People,$base" -Filter * -Properties mail,title | Format-Table SamAccountName,Name,UserPrincipalName,Title,mail -AutoSize | Out-String -Width 200
"== Groups"; foreach ($g in 'Admins','Developers','Staff') { "{0}: {1}" -f $g, ((Get-ADGroupMember $g | Sort-Object SamAccountName).SamAccountName -join ', ') }

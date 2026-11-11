param([string]$LdapPass,[string]$HttpPass)
# Projet 2 - cote AD : comptes de service, SPN, keytab, DNS
Import-Module ActiveDirectory
$base='DC=polycorp,DC=test'
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Services'")) { New-ADOrganizationalUnit -Name Services -Path $base -ProtectedFromAccidentalDeletion $true }
$ou="OU=Services,$base"
function NewSvc($sam,$desc,$pw){ if (-not (Get-ADUser -Filter "sAMAccountName -eq '$sam'")) {
  New-ADUser -Name $sam -SamAccountName $sam -UserPrincipalName "$sam@polycorp.test" -Description $desc -Path $ou -AccountPassword (ConvertTo-SecureString $pw -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true -AccountNotDelegated $true } }
NewSvc 'svc-kc-ldap' 'Keycloak - lecture LDAP seule (bind)' $LdapPass
NewSvc 'svc-kc-http' 'Keycloak - porteur du SPN HTTP/sso.polycorp.test' $HttpPass
# compte de lecture : pas de connexion interactive possible (Deny logon locally via groupe ? -> ici : membre de Domain Users uniquement)
Set-ADUser svc-kc-http -Replace @{'msDS-SupportedEncryptionTypes'=24}   # AES128 + AES256 seulement
"== SPN"
setspn -S HTTP/sso.polycorp.test POLYCORP\svc-kc-http
setspn -L POLYCORP\svc-kc-http
"== ktpass"
Remove-Item C:\Users\Public\sso.keytab -ErrorAction SilentlyContinue
ktpass -out C:\Users\Public\sso.keytab -princ HTTP/sso.polycorp.test@POLYCORP.TEST -mapuser POLYCORP\svc-kc-http -pass $HttpPass -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL 2>&1 | Select-String -Pattern 'Successfully|Key created|Output keytab|kvno|vno|Account' | % { $_.Line }
"== DNS"
foreach($n in 'sso','app'){ if (-not (Get-DnsServerResourceRecord -ZoneName polycorp.test -Name $n -ErrorAction SilentlyContinue)) { Add-DnsServerResourceRecordA -ZoneName polycorp.test -Name $n -IPv4Address 192.168.50.30 } }
Get-DnsServerResourceRecord -ZoneName polycorp.test -RRType A | ? HostName -in 'sso','app','dc01','CL01' | Format-Table HostName,@{n='IP';e={$_.RecordData.IPv4Address}} -AutoSize | Out-String
"== comptes"
Get-ADUser -SearchBase $ou -Filter * -Properties servicePrincipalName,msDS-SupportedEncryptionTypes,PasswordNeverExpires,AccountNotDelegated | Format-Table SamAccountName,Enabled,PasswordNeverExpires,AccountNotDelegated,msDS-SupportedEncryptionTypes,@{n='SPN';e={$_.servicePrincipalName -join ','}} -AutoSize | Out-String -Width 200
# Le keytab reste sur DC01 (C:\Users\Public\sso.keytab) : le copier sur la VM sso dans keycloak/sso.keytab (chmod 600), puis le supprimer du DC.

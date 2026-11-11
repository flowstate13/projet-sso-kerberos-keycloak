# A lancer sur CL01 dans la session d'un utilisateur du domaine (ex. POLYCORP\bdupont).
# Verifie toute la chaine : DNS, SPN, ticket HTTP, reponse SPNEGO de Keycloak.
$ErrorActionPreference = 'Continue'
"== 1. DNS";       Resolve-DnsName sso.polycorp.test,app.polycorp.test -Type A | Format-Table Name,IPAddress -AutoSize | Out-String
"== 2. SPN";       setspn -Q HTTP/sso.polycorp.test
"== 3. Ticket";    klist get HTTP/sso.polycorp.test | Select-String 'retrieved|Server:|Start|End|Encryption' | % { $_.Line.Trim() }
"== 4. GPO";       (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Edge -ErrorAction SilentlyContinue).AuthServerAllowlist
"== 5. SPNEGO";    try {
  $r = Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -MaximumRedirection 10 'http://app.polycorp.test:8181/rh'
  if ($r.Content -match 'accès accordé à (\w+)') { "OK : application ouverte pour " + $Matches[1] + " sans saisie de mot de passe" } else { "KO : formulaire affiche" }
} catch { "Erreur : " + $_.Exception.Message }

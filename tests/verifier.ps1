# A lancer sur CL01 dans la session d'un utilisateur du domaine (ex. POLYCORP\bdupont).
# Verifie toute la chaine : DNS, SPN, ticket HTTP, SPNEGO vers Keycloak, assertion SAML acceptee par l'application.
$ErrorActionPreference = 'Continue'
"== 1. DNS";    foreach ($n in 'sso.polycorp.test','app.polycorp.test') { $a = Resolve-DnsName $n -Type A; "{0} -> {1}" -f $n, $a.IPAddress }
"== 2. SPN";    setspn -Q HTTP/sso.polycorp.test | Select-String 'CN=|HTTP/' | % { $_.Line.Trim() }
"== 3. Ticket"; klist get HTTP/sso.polycorp.test | Select-String 'retrieved|Server: HTTP|Encryption Type' | Select -First 3 | % { $_.Line.Trim() }
"== 4. GPO";    "AuthServerAllowlist = " + (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Edge -ErrorAction SilentlyContinue).AuthServerAllowlist
"== 5. SPNEGO + SAML"
try {
  # a) l'application redirige vers Keycloak ; Keycloak repond 401 Negotiate ; PowerShell renvoie le ticket (UseDefaultCredentials)
  $r = Invoke-WebRequest -UseBasicParsing -UseDefaultCredentials -SessionVariable s -MaximumRedirection 10 'http://app.polycorp.test:8181/rh'
  $m = [regex]::Match($r.Content, '(?is)action="([^"]+)".*?name="SAMLResponse"\s+value="([^"]+)"')
  if (-not $m.Success) { "KO : Keycloak a renvoye le formulaire de connexion (pas de SPNEGO)"; return }
  "Keycloak a accepte le ticket : SAMLResponse recue ({0} caracteres), destination {1}" -f $m.Groups[2].Value.Length, $m.Groups[1].Value
  # b) comme le navigateur : POST de l'assertion vers l'ACS de l'application
  $r2 = Invoke-WebRequest -UseBasicParsing -WebSession $s -Method Post -Uri $m.Groups[1].Value -Body @{ SAMLResponse = $m.Groups[2].Value } -MaximumRedirection 5
  $u = [regex]::Match($r2.Content, 'accord\S* \S+ (\w+)')
  if ($u.Success) { "OK : application ouverte pour " + $u.Groups[1].Value + " sans saisie de mot de passe" } else { "KO : assertion refusee par l'application" }
} catch { "Erreur : " + $_.Exception.Message }

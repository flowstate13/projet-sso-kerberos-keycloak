#!/bin/bash
# Configuration reproductible de Keycloak pour le projet 2 (a lancer dans le conteneur).
# Variables attendues : ADMIN_PW (admin Keycloak), LDAP_PW (svc-kc-ldap)
set -euo pipefail
KC=/opt/keycloak/bin/kcadm.sh
R=polycorp
$KC config credentials --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PW" >/dev/null
$KC get realms/$R >/dev/null 2>&1 || $KC create realms -s realm=$R -s enabled=true -s displayName="Polycorp SSO" -s loginWithEmailAllowed=false
RID=$($KC get realms/$R --fields id --format csv --noquotes)

# 1. Federation Active Directory (lecture seule) + integration Kerberos
LDAP_ID=$($KC get components -r $R -q name=ad-polycorp --fields id --format csv --noquotes || true)
if [ -z "$LDAP_ID" ]; then
LDAP_ID=$($KC create components -r $R -i -s name=ad-polycorp -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider -s parentId=$RID \
 -s 'config.enabled=["true"]' -s 'config.priority=["0"]' -s 'config.vendor=["ad"]' \
 -s 'config.connectionUrl=["ldap://dc01.polycorp.test:389"]' -s 'config.authType=["simple"]' \
 -s 'config.bindDn=["CN=svc-kc-ldap,OU=Services,DC=polycorp,DC=test"]' -s "config.bindCredential=[\"$LDAP_PW\"]" \
 -s 'config.usersDn=["OU=People,DC=polycorp,DC=test"]' -s 'config.searchScope=["1"]' \
 -s 'config.usernameLDAPAttribute=["sAMAccountName"]' -s 'config.rdnLDAPAttribute=["cn"]' -s 'config.uuidLDAPAttribute=["objectGUID"]' \
 -s 'config.userObjectClasses=["person, organizationalPerson, user"]' -s 'config.editMode=["READ_ONLY"]' \
 -s 'config.importEnabled=["true"]' -s 'config.syncRegistrations=["false"]' -s 'config.trustEmail=["true"]' -s 'config.pagination=["true"]' \
 -s 'config.fullSyncPeriod=["-1"]' -s 'config.changedSyncPeriod=["-1"]' -s 'config.cachePolicy=["NO_CACHE"]' \
 -s 'config.allowKerberosAuthentication=["true"]' -s 'config.kerberosRealm=["POLYCORP.TEST"]' \
 -s 'config.serverPrincipal=["HTTP/sso.polycorp.test@POLYCORP.TEST"]' -s 'config.keyTab=["/opt/keycloak/conf/sso.keytab"]' \
 -s 'config.useKerberosForPasswordAuthentication=["true"]' -s 'config.debug=["true"]')
fi
echo "LDAP component: $LDAP_ID"

mk_mapper(){ # name providerId config...
  local n=$1 p=$2; shift 2
  [ -n "$($KC get components -r $R -q parent=$LDAP_ID -q name="$n" --fields id --format csv --noquotes)" ] && return 0
  $KC create components -r $R -s name="$n" -s providerId=$p -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper -s parentId=$LDAP_ID "$@" >/dev/null
}
mk_mapper groupes-ad group-ldap-mapper -s 'config."groups.dn"=["OU=Groups,DC=polycorp,DC=test"]' -s 'config."group.name.ldap.attribute"=["cn"]' \
  -s 'config."group.object.classes"=["group"]' -s 'config."membership.ldap.attribute"=["member"]' -s 'config."membership.attribute.type"=["DN"]' \
  -s 'config."membership.user.ldap.attribute"=["sAMAccountName"]' -s 'config.mode=["READ_ONLY"]' -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
  -s 'config."memberof.ldap.attribute"=["memberOf"]' -s 'config."preserve.group.inheritance"=["false"]' -s 'config."drop.non.existing.groups.during.sync"=["false"]' -s 'config."groups.path"=["/"]'
mk_mapper title user-attribute-ldap-mapper -s 'config."user.model.attribute"=["title"]' -s 'config."ldap.attribute"=["title"]' -s 'config."read.only"=["true"]' -s 'config."always.read.value.from.ldap"=["true"]' -s 'config."is.mandatory.in.ldap"=["false"]'
mk_mapper upn user-attribute-ldap-mapper -s 'config."user.model.attribute"=["upn"]' -s 'config."ldap.attribute"=["userPrincipalName"]' -s 'config."read.only"=["true"]' -s 'config."always.read.value.from.ldap"=["true"]' -s 'config."is.mandatory.in.ldap"=["false"]'
echo "LDAP mappers:"; $KC get components -r $R -q parent=$LDAP_ID --fields name,providerId --format csv --noquotes

# 2. Synchronisation des utilisateurs et des groupes
$KC create user-storage/$LDAP_ID/sync?action=triggerFullSync -r $R 2>/dev/null | tr -d '\n'; echo
GM=$($KC get components -r $R -q parent=$LDAP_ID -q name=groupes-ad --fields id --format csv --noquotes)
$KC create user-storage/$LDAP_ID/mappers/$GM/sync?direction=fedToKeycloak -r $R 2>/dev/null | tr -d '\n'; echo

# 3. Flux "browser" : etape Kerberos en ALTERNATIVE
EX=$($KC get authentication/flows/browser/executions -r $R --format csv --noquotes --fields id,displayName,requirement | grep -i kerberos)
EXID=${EX%%,*}
$KC update authentication/flows/browser/executions -r $R -b "{\"id\":\"$EXID\",\"requirement\":\"ALTERNATIVE\"}"
echo "Flux browser :"; $KC get authentication/flows/browser/executions -r $R --format csv --noquotes --fields displayName,requirement

# 4. Client SAML de l'application
CID=http://app.polycorp.test:8181/saml/metadata
if [ -z "$($KC get clients -r $R -q clientId=$CID --fields id --format csv --noquotes)" ]; then
cat > /tmp/client.json <<JSON
{"clientId":"$CID","name":"Application Polycorp (SP SAML)","protocol":"saml","enabled":true,
 "redirectUris":["http://app.polycorp.test:8181/saml/acs"],"baseUrl":"http://app.polycorp.test:8181/",
 "frontchannelLogout":true,
 "attributes":{"saml_assertion_consumer_url_post":"http://app.polycorp.test:8181/saml/acs","saml.assertion.signature":"true",
  "saml.server.signature":"true","saml.client.signature":"false","saml.force.post.binding":"true","saml_name_id_format":"username",
  "saml.force.name.id.format":"true","saml.authnstatement":"true","saml.signature.algorithm":"RSA_SHA256"},
 "protocolMappers":[
  {"name":"email","protocol":"saml","protocolMapper":"saml-user-property-mapper","config":{"user.attribute":"email","attribute.name":"email","friendly.name":"email","attribute.nameformat":"Basic"}},
  {"name":"givenName","protocol":"saml","protocolMapper":"saml-user-property-mapper","config":{"user.attribute":"firstName","attribute.name":"givenName","attribute.nameformat":"Basic"}},
  {"name":"sn","protocol":"saml","protocolMapper":"saml-user-property-mapper","config":{"user.attribute":"lastName","attribute.name":"sn","attribute.nameformat":"Basic"}},
  {"name":"upn","protocol":"saml","protocolMapper":"saml-user-attribute-mapper","config":{"user.attribute":"upn","attribute.name":"upn","attribute.nameformat":"Basic"}},
  {"name":"title","protocol":"saml","protocolMapper":"saml-user-attribute-mapper","config":{"user.attribute":"title","attribute.name":"title","attribute.nameformat":"Basic"}},
  {"name":"groupes","protocol":"saml","protocolMapper":"saml-group-membership-mapper","config":{"attribute.name":"memberOf","full.path":"false","single":"false","attribute.nameformat":"Basic"}}
 ]}
JSON
$KC create clients -r $R -f /tmp/client.json >/dev/null
fi
echo "Client SAML :"; $KC get clients -r $R -q clientId=$CID --fields clientId,protocol,enabled --format csv --noquotes
echo "Utilisateurs importes :"; $KC get users -r $R --fields username,email,federationLink,enabled --format csv --noquotes
echo "Groupes :"; $KC get groups -r $R --fields name --format csv --noquotes

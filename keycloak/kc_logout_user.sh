#!/bin/bash
# usage (dans le conteneur) : ADMIN_PW=... bash kc_logout_user.sh <username>  -> ferme les sessions Keycloak de l'utilisateur
KC=/opt/keycloak/bin/kcadm.sh; $KC config credentials --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PW" >/dev/null
ID=$($KC get users -r polycorp -q username=$1 -q exact=true --fields id --format csv --noquotes)
$KC create users/$ID/logout -r polycorp >/dev/null 2>&1; echo "sessions Keycloak de $1 fermees ; restantes : $($KC get users/$ID/sessions -r polycorp --format csv --noquotes | wc -l)"

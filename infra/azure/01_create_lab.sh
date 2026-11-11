#!/bin/bash
set -euo pipefail
AZ=az; source ./.secrets   # DC_USER DC_PASS CL_USER CL_PASS (non versionne)
RG=rg-iam-tp2; L=francecentral; MYIP=${MYIP:?mettre votre IP publique}
$AZ group create -n $RG -l $L -o none
$AZ network nsg create -g $RG -n nsg-lab -o none
$AZ network nsg rule create -g $RG --nsg-name nsg-lab -n allow-rdp-my-ip --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes $MYIP/32 --destination-port-ranges 3389 -o none
$AZ network vnet create -g $RG -n vnet-polycorp --address-prefixes 192.168.50.0/24 --subnet-name snet-lab --subnet-prefixes 192.168.50.0/24 --network-security-group nsg-lab -o none
for vm in DC01:192.168.50.10 CL01:192.168.50.20; do n=${vm%%:*}; ip=${vm##*:}
  $AZ network public-ip create -g $RG -n pip-$n --sku Standard --allocation-method Static -o none
  $AZ network nic create -g $RG -n nic-$n --vnet-name vnet-polycorp --subnet snet-lab --private-ip-address $ip --public-ip-address pip-$n -o none
done
$AZ vm create -g $RG -n TP2-DC01 --computer-name DC01 --nics nic-DC01 --image MicrosoftWindowsServer:WindowsServer:2019-datacenter-gensecond:latest --size ${SIZE:-Standard_B2as_v2} --admin-username "$DC_USER" --admin-password "$DC_PASS" -o table &
$AZ vm create -g $RG -n TP2-CL01 --computer-name CL01 --nics nic-CL01 --image MicrosoftWindowsDesktop:Windows-10:win10-22h2-pro-g2:latest --license-type Windows_Client --size ${SIZE:-Standard_B2as_v2} --admin-username "$CL_USER" --admin-password "$CL_PASS" -o table &
wait
$AZ vm list -g $RG -d --query "[].{name:name, state:powerState, priv:privateIps, pub:publicIps, size:hardwareProfile.vmSize}" -o table

# VM Linux du fournisseur d'identite (Keycloak) - 192.168.50.30
$AZ network public-ip create -g $RG -n pip-SSO --sku Standard --allocation-method Static -o none
$AZ network nic create -g $RG -n nic-SSO --vnet-name vnet-polycorp --subnet snet-lab --private-ip-address 192.168.50.30 --public-ip-address pip-SSO -o none
$AZ network nsg rule create -g $RG --nsg-name nsg-lab -n allow-ssh-my-ip --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes $MYIP/32 --destination-port-ranges 22 8080 8181 -o none
$AZ vm create -g $RG -n PRJ-SSO --computer-name sso --nics nic-SSO --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2als_v2 --admin-username azureuser --ssh-key-values ~/.ssh/id_ed25519.pub -o table
# Apres la promotion de DC01 : le DNS du reseau virtuel pointe sur DC01
# $AZ network vnet update -g $RG -n vnet-polycorp --dns-servers 192.168.50.10

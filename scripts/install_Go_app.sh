#!/usr/bin/env bash
set -x

source /usr/local/bootstrap/var.env

if [ -d /vagrant ]; then
  LOG="/vagrant/logs/VaultServiceIDFactory_${HOSTNAME}.log"
else
  LOG="VaultServiceIDFactory_${HOSTNAME}.log"
fi

# check goapp binary

export GOPATH=$HOME/gopath
export PATH=$HOME/gopath/bin:$PATH
mkdir -p $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory
cp -r /usr/local/bootstrap/. $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory/
cd $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory
go get -t -v ./...
go build -o VaultServiceIDFactory main.go
chmod +x VaultServiceIDFactory
killall VaultServiceIDFactory &>/dev/null
cp VaultServiceIDFactory /usr/local/bin/.
VaultServiceIDFactory &> ${LOG} &


sleep 5

# Put new API Test Here
curl -sSf http://localhost:8314/initialiseme
curl -sSf -X POST http://localhost:8314/initialiseme
curl -sSf http://localhost:8314/approlename
curl -sSf  -X POST http://localhost:8314/approlename
curl -sSf http://localhost:8314/health

# Initialise with Vault Token
export WRAPPED_VAULT_TOKEN=`cat /usr/local/bootstrap/.wrapped-provisioner-token`

curl --header "Content-Type: application/json" \
  --request POST \
  --data "{\"token\":\"${WRAPPED_VAULT_TOKEN}\"}" \
  http://localhost:8314/initialiseme

curl -sSf http://localhost:8314/health 


echo finished!!


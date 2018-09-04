#!/usr/bin/env bash

setup_environment () {

    set -x
    source /usr/local/bootstrap/var.env

    IP=${LEADER_IP}
    if [ "${TRAVIS}" == "true" ]; then
        IP="127.0.0.1"
    fi

    export VAULT_ADDR=http://${IP}:8200
    export VAULT_SKIP_VERIFY=true

    if [ -d /vagrant ]; then
    LOG="/vagrant/logs/VaultServiceIDFactory_${HOSTNAME}.log"
    else
    LOG="VaultServiceIDFactory.log"
    fi




}

install_go_application () {

    # export GOPATH=$HOME/gopath
    # export PATH=$HOME/gopath/bin:$PATH
    # sudo mkdir -p $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory
    # sudo cp -r /usr/local/bootstrap/. $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory/
    # cd $HOME/gopath/src/github.com/allthingsclowd/VaultServiceIDFactory
    go get -t ./...
    go build -o VaultServiceIDFactory main.go
    chmod +x VaultServiceIDFactory
    killall VaultServiceIDFactory &>/dev/null
    sudo cp VaultServiceIDFactory /usr/local/bin/.
    VaultServiceIDFactory vault=${VAULT_ADDR} &> ${LOG} &
    sleep 5

}

verify_go_application () {

    curl http://localhost:8314/health 
    # Initialise with Vault Token
    WRAPPED_VAULT_TOKEN=`cat /usr/local/bootstrap/.wrapped-provisioner-token`
    curl --header "Content-Type: application/json" \
    --request POST \
    --data "{\"token\":\"${WRAPPED_VAULT_TOKEN}\"}" \
    http://localhost:8314/initialiseme

    curl http://localhost:8314/health 
    # Get a secret ID and test access to the Vault KV Secret
    ROLENAME="id-factory"

    curl --header "Content-Type: application/json" \
    --request POST \
    --data "{\"RoleName\":\"${ROLENAME}\"}" \
    http://localhost:8314/approlename

    WRAPPED_SECRET_ID=`curl --header "Content-Type: application/json" \
    --request POST \
    --data "{\"RoleName\":\"${ROLENAME}\"}" \
    http://localhost:8314/approlename | awk '/Token Received:/{print $NF}'`

    echo "WRAPPED_SECRET_ID : ${WRAPPED_SECRET_ID}"

    SECRET_ID=`curl --header "X-Vault-Token: ${WRAPPED_SECRET_ID}" \
        --request POST \
        ${VAULT_ADDR}/v1/sys/wrapping/unwrap | jq -r .data.secret_id`
    
    echo "SECRET_ID : ${SECRET_ID}"
    
    # retrieve the appRole-id from the approle - /usr/local/bootstrap/.appRoleID
    APPROLEID=`cat /usr/local/bootstrap/.appRoleID`

    echo "APPROLEID : ${APPROLEID}"

    # login
    tee id-factory-secret-id-login.json <<EOF
    {
    "role_id": "${APPROLEID}",
    "secret_id": "${SECRET_ID}"
    }
EOF

    APPTOKEN=`curl \
        --request POST \
        --data @id-factory-secret-id-login.json \
        ${VAULT_ADDR}/v1/auth/approle/login | jq -r .auth.client_token`


    echo "Reading secret using newly acquired token"

    curl \
        --header "X-Vault-Token: ${APPTOKEN}" \
        ${VAULT_ADDR}/v1/kv/example_password | jq -r .


    curl http://localhost:8314/health 

}

echo 'Start of Application Installation and Test'
setup_environment
install_go_application
verify_go_application
echo 'End of Application Installation and Test'


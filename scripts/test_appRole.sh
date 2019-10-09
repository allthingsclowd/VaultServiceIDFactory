#!/usr/bin/env bash

setup_environment () {

    set -x
    
    IFACE=`route -n | awk '$1 == "192.168.9.0" {print $8}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.9" {print $2}'`
    IP=${CIDR%%/24}

    if [ "${TRAVIS}" == "true" ]; then
    IP=${IP:-127.0.0.1}
    fi

    echo 'Set environmental bootstrapping data in VAULT'
    export VAULT_CLIENT_KEY=/usr/local/bootstrap/certificate-config/hashistack-client-key.pem
    export VAULT_CLIENT_CERT=/usr/local/bootstrap/certificate-config/hashistack-client.pem
    export VAULT_CACERT=/usr/local/bootstrap/certificate-config/hashistack-ca.pem
    export VAULT_ADDR=http://${IP}:8322
    export VAULT_SKIP_VERIFY=true

    VAULT_TOKEN=`cat /usr/local/bootstrap/.vault-token`

}

get_approle_id () {
    
    # retrieve the appRole-id from the approle
    APPROLEID=`curl -s  \
    --cacert "/usr/local/bootstrap/certificate-config/hashistack-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/hashistack-client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/hashistack-client.pem" \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    ${VAULT_ADDR}/v1/auth/approle/role/id-factory/role-id | jq -r .data.role_id`

}

set_test_secret_data () {
    
    # Put Test Data (Password) in Vault
    MASTER_PASSWORD="You_have_successfully_accessed_a_secret_password"
    VAULT_ADDR="https://${IP}:8322" vault login ${VAULT_TOKEN}
    VAULT_ADDR="https://${IP}:8322" vault kv put kv/example_password value=${MASTER_PASSWORD}

}

get_secret_id () {

    # Generate a new secret-id
    SECRET_ID=`curl -s \
        --cacert "/usr/local/bootstrap/certificate-config/hashistack-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/hashistack-client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/hashistack-client.pem" \
        --location \
        --header "X-Vault-Token: ${VAULT_TOKEN}" \
        --request POST \
        ${VAULT_ADDR}/v1/auth/approle/role/id-factory/secret-id | jq -r .data.secret_id`

}

verify_approle_credentials () {

    # login
    tee id-factory-secret-id-login.json <<EOF
    {
    "role_id": "${APPROLEID}",
    "secret_id": "${SECRET_ID}"
    }
EOF

    APPTOKEN=`curl -s \
        --cacert "/usr/local/bootstrap/certificate-config/hashistack-ca.pem" \
        --key "/usr/local/bootstrap/certificate-config/hashistack-client-key.pem" \
        --cert "/usr/local/bootstrap/certificate-config/hashistack-client.pem" \
        --request POST \
        --data @id-factory-secret-id-login.json \
        ${VAULT_ADDR}/v1/auth/approle/login | jq -r .auth.client_token`


    echo "Reading secret using newly acquired token"
    VAULT_ADDR="https://${IP}:8322" vault login ${APPTOKEN}
    VAULT_ADDR="https://${IP}:8322" vault kv get kv/example_password

}

echo 'Start Vault AppRole Test'
setup_environment
set_test_secret_data
get_secret_id
get_approle_id
verify_approle_credentials
get_secret_id
get_approle_id
verify_approle_credentials
echo 'End Vault AppRole Test'
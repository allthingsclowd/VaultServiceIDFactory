#!/usr/bin/env bash

set -x

IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8}'`
CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
IP=${CIDR%%/24}

if [ "${TRAVIS}" == "true" ]; then
IP=${IP:-127.0.0.1}
fi

if [ -d /vagrant ]; then
  LOG="/vagrant/logs/vault_audit_${HOSTNAME}.log"
else
  LOG="vault_audit.log"
fi

export VAULT_ADDR=http://${IP}:8200
export VAULT_SKIP_VERIFY=true

VAULT_TOKEN=`cat /usr/local/bootstrap/.admin-token`

##--------------------------------------------------------------------
## Configure Audit Backend

VAULT_AUDIT_LOG="${LOG}"

tee audit-backend-file.json <<EOF
{
  "type": "file",
  "options": {
    "path": "${VAULT_AUDIT_LOG}"
  }
}
EOF

curl \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request PUT \
    --data @audit-backend-file.json \
    ${VAULT_ADDR}/v1/sys/audit/file-audit


##--------------------------------------------------------------------
## Create ACL Policy

# Policy to apply to AppRole token
tee id-factory-secret-read.json <<EOF
{"policy":"path \"kv/development/redispassword\" {capabilities = [\"read\", \"list\"]}"}
EOF

# Write the policy
curl \
    --location \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request PUT \
    --data @id-factory-secret-read.json \
    ${VAULT_ADDR}/v1/sys/policy/id-factory-secret-read | jq .

##--------------------------------------------------------------------

# List ACL policies
curl \
    --location \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request LIST \
    ${VAULT_ADDR}/v1/sys/policy | jq .

##--------------------------------------------------------------------
## Enable & Configure AppRole Auth Backend

# AppRole auth backend config
tee approle.json <<EOF
{
  "type": "approle",
  "description": "Demo AppRole auth backend for id-factory deployment"
}
EOF

# Create the approle backend
curl \
    --location \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data @approle.json \
    ${VAULT_ADDR}/v1/sys/auth/approle | jq .

# Check if AppRole Exists
APPROLEID=`curl  \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   ${VAULT_ADDR}/v1/auth/approle/role/id-factory/role-id | jq -r .data.role_id`

if [ "${APPROLEID}" == null ]; then
    # AppRole backend configuration
    tee id-factory-approle-role.json <<EOF
    {
        "role_name": "id-factory",
        "bind_secret_id": true,
        "secret_id_ttl": "24h",
        "secret_id_num_uses": "0",
        "token_ttl": "10m",
        "token_max_ttl": "30m",
        "period": 0,
        "policies": [
            "id-factory-secret-read"
        ]
    }
EOF

    # Create the AppRole role
    curl \
        --location \
        --header "X-Vault-Token: ${VAULT_TOKEN}" \
        --request POST \
        --data @id-factory-approle-role.json \
        ${VAULT_ADDR}/v1/auth/approle/role/id-factory | jq .

    APPROLEID=`curl  \
   --header "X-Vault-Token: ${VAULT_TOKEN}" \
   ${VAULT_ADDR}/v1/auth/approle/role/id-factory/role-id | jq -r .data.role_id`

fi

echo -e "\n\nApplication RoleID = ${APPROLEID}\n\n"
echo -n ${APPROLEID} > /usr/local/bootstrap/.approle-id

# Write minimal secret-id payload
tee secret_id_config.json <<EOF
{
  "metadata": "{ \"tag1\": \"id-factory production\" }"
}
EOF

SECRET_ID=`curl \
    --location \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    ${VAULT_ADDR}/v1/auth/approle/role/id-factory/secret-id | jq -r .data.secret_id`

# login
tee id-factory-secret-id-login.json <<EOF
{
  "role_id": "${APPROLEID}",
  "secret_id": "${SECRET_ID}"
}
EOF

curl \
    --request POST \
    --data @id-factory-secret-id-login.json \
    ${VAULT_ADDR}/v1/auth/approle/login 





#!/usr/bin/env bash
set -x
echo 'Start Vault Role/Policy Configuration'

IFACE=`route -n | awk '$1 == "192.168.9.0" {print $8}'`
CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.9" {print $2}'`
IP=${CIDR%%/24}

if [ "${TRAVIS}" == "true" ]; then
IP=${IP:-127.0.0.1}
fi

if [ -d /vagrant ]; then
  LOG="/vagrant/logs/vault_audit_${HOSTNAME}.log"
else
  LOG="vault_audit.log"
fi

echo 'Set environmental bootstrapping data in VAULT'
export VAULT_ADDR=https://${IP}:8322
export VAULT_CLIENT_KEY=/usr/local/bootstrap/certificate-config/vault/vault-client-key.pem
export VAULT_CLIENT_CERT=/usr/local/bootstrap/certificate-config/vault/vault-client.pem
export VAULT_CACERT=/usr/local/bootstrap/certificate-config/hashistack/hashistack-ca.pem

# enable secret KV version 1
VAULT_TOKEN=`cat /usr/local/bootstrap/.vault-token`
VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault secrets enable -version=1 kv

# configure Audit Backend

VAULT_AUDIT_LOG="${LOG}"

tee audit-backend-file.json <<EOF
{
  "type": "file",
  "options": {
    "path": "${VAULT_AUDIT_LOG}"
  }
}
EOF

curl -s \
    --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --cacert "/usr/local/bootstrap/certificate-config/hashistack/hashistack-ca.pem" \
    --key "/usr/local/bootstrap/certificate-config/vault/vault-client-key.pem" \
    --cert "/usr/local/bootstrap/certificate-config/vault/vault-client.pem" \
    --request PUT \
    --data @audit-backend-file.json \
    ${VAULT_ADDR}/v1/sys/audit/file-audit

# use root policy to create admin & provisioner policies
# see https://www.hashicorp.com/resources/policies-vault

# admin policy hcl definition file
tee admin_policy.hcl <<EOF
# Manage auth backends broadly across Vault
path "auth/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List, create, update, and delete auth backends
path "sys/auth/*"
{
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# List existing policies
path "sys/policy"
{
  capabilities = ["read"]
}

# Create and manage ACL policies broadly across Vault
path "sys/policy/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List, create, update, and delete key/value secrets
path "secret/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List, create, update, and delete key/value secrets
path "kv/*"
{
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage and manage secret backends broadly across Vault.
path "sys/mounts/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Read health checks
path "sys/health"
{
  capabilities = ["read", "sudo"]
}
EOF

# create the admin policy in vault
VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault policy write admin admin_policy.hcl

# create an admin token
ADMIN_TOKEN=`VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault token create -policy=admin -field=token`
sudo echo -n ${ADMIN_TOKEN} > /usr/local/bootstrap/.admin-token

sudo chmod ugo+r /usr/local/bootstrap/.admin-token


# provisioner policy hcl definition file
tee provisioner_policy.hcl <<EOF
# Manage auth backends broadly across Vault
path "auth/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List, create, update, and delete auth backends
path "sys/auth/*"
{
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

# List existing policies
path "sys/policy"
{
  capabilities = ["read"]
}

# Create and manage ACL policies
path "sys/policy/*"
{
  capabilities = ["create", "read", "update", "delete", "list"]
}

# List, create, update, and delete key/value secrets
path "secret/*"
{
  capabilities = ["create", "read", "update", "delete", "list"]
}

# List, create, update, and delete key/value secrets
path "kv/*"
{
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# create provisioner policy
VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault policy write provisioner provisioner_policy.hcl

# create a provisioner token
PROVISIONER_TOKEN=`VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault token create -policy=provisioner -field=token`
sudo echo -n ${PROVISIONER_TOKEN} > /usr/local/bootstrap/.provisioner-token
sudo chmod ugo+r /usr/local/bootstrap/.provisioner-token
# create a wrapped provisioner token by adding -wrap-ttl=60m
WRAPPED_PROVISIONER_TOKEN=`VAULT_TOKEN=${VAULT_TOKEN} VAULT_ADDR="https://${IP}:8322" vault token create -policy=provisioner -wrap-ttl=60m -field=wrapping_token`
sudo echo -n ${WRAPPED_PROVISIONER_TOKEN} > /usr/local/bootstrap/.wrapped-provisioner-token
sudo chmod ugo+r /usr/local/bootstrap/.wrapped-provisioner-token

# # revoke ROOT token now that admin token has been created
# ROOT_TOKEN=`cat /usr/local/bootstrap/.vault-token`
# VAULT_ADDR="https://${IP}:8322" vault token revoke ${ROOT_TOKEN}

# # Verify root token revoked
# VAULT_ADDR="https://${IP}:8322" vault status

# # Set new admin vault token & verify
# export VAULT_TOKEN=${ADMIN_TOKEN}
VAULT_ADDR="https://${IP}:8322" vault status

echo 'Finished Vault Role/Policy Configuration'

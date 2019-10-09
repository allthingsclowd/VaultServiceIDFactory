#!/bin/bash

# Start the first process
./VaultServiceIDFactory -vault="http://192.168.9.11:8322"&
status=$?
if [ ${status} -ne 0 ]; then
  echo "Failed to start VaultServiceIDFactory: ${status}"
  exit ${status}
fi

if [ -f /usr/local/bootstrap/.provisioner-token ]; then
  echo "Running Docker locally with access to vagrant instance filesystem"
  VAULT_TOKEN=`cat /usr/local/bootstrap/.provisioner-token`
else
  echo "Looking for secret keys on Kubernetes"
  # Get the container token
  KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  # Authenticate against Vault backend and get a Vault token
  VAULT_TOKEN=$(curl --request POST \
                          --data '{"jwt": "'"$KUBE_TOKEN"'", "role": "demo"}' \
                          http://192.168.9.11:8322/v1/auth/kubernetes/login | jq -r .auth.client_token)
fi

WRAPPED_PROVISIONER_TOKEN=$(curl --request POST \
                                  --data '{
                                            "policies": [
                                              "provisioner"
                                              ],
                                            "metadata": {
                                              "user": "Grahams Demo"
                                              },
                                            "ttl": "1h",
                                            "renewable": true
                                          }' \
                                  --header "X-Vault-Token: ${VAULT_TOKEN}" \
                                  --header "X-Vault-Wrap-TTL: 60" \
                              http://192.168.9.11:8322/v1/auth/token/create | jq -r .wrap_info.token)


curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{\"token\":\"${WRAPPED_PROVISIONER_TOKEN}\"}" \
        http://127.0.0.1:8314/initialiseme

curl -s http://127.0.0.1:8314/health 

# Naive check runs checks once a minute to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container exits with an error
# if it detects that either of the processes has exited.
# Otherwise it loops forever, waking up every 60 seconds

while sleep 60; do
  ps aux |grep VaultServiceIDFactory |grep -q -v grep
  PROCESS_1_STATUS=$?
  # If the greps above find anything, they exit with 0 status
  # If they are not both 0, then something is wrong
  if [ ${PROCESS_1_STATUS} -ne 0 ]; then
    echo "VaultServiceIDFactory has already exited."
    exit 1
  fi
done
#!/usr/bin/env bash

register_secret_id_service_with_consul () {
    
    echo 'Start to register secret_id service with Consul Service Discovery'

    # configure web service definition
    sudo tee /etc/consul.d/secretid_service.json <<EOF
        {
      "service": {
        "name": "approle",
        "port": 8314,
        "connect": { "sidecar_service": {} }
      }
      
    }
EOF
      # Register the service in consul via the local Consul agent api
    consul reload
    sleep 5

  # Register the service in consul via the local Consul agent api
  curl \
      -v \
      --request PUT \
      --data @secretid_service.json \
      http://127.0.0.1:8500/v1/agent/service/register

  # List the locally registered services via local Consul api
  curl \
    -v \
    http://127.0.0.1:8500/v1/agent/services | jq -r .

  # List the services regestered on the Consul server
  curl \
  -v \
  http://${LEADER_IP}:8500/v1/catalog/services | jq -r .
   
    echo 'Register Vault Secret ID Factory Service with Consul Service Discovery Complete'

}

create_service () {
  # create a new systemd service
  # param 1 ${1}: service/serviceuser name
  # param 2 ${2}: service description
  # param 3 ${3}: service start command
  if [ ! -f /etc/systemd/system/${1}.service ]; then
    
    create_service_user ${1}
    
    sudo tee /etc/systemd/system/${1}.service <<EOF
### BEGIN INIT INFO
# Provides:          ${1}
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${1} service
# Description:       ${2}
### END INIT INFO

[Unit]
Description=${2}
Requires=network-online.target
After=network-online.target

[Service]
User=${1}
Group=${1}
PIDFile=/var/run/${1}/${1}.pid
PermissionsStartOnly=true
ExecStartPre=-/bin/mkdir -p /var/run/${1}
ExecStartPre=/bin/chown -R ${1}:${1} /var/run/${1}
ExecStart=${3}
ExecReload=/bin/kill -HUP ${MAINPID}
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload

  fi

}

create_service_user () {
  
  if ! grep ${1} /etc/passwd >/dev/null 2>&1; then
    echo "Creating ${1} user to run the ${1} service"
    sudo useradd --system --home /etc/${1}.d --shell /bin/false ${1}
    sudo mkdir --parents /opt/${1} /usr/local/${1} /etc/${1}.d
    sudo chown --recursive ${1}:${1} /opt/${1} /etc/${1}.d /usr/local/${1}
  fi

}

start_app_proxy_service () {
  # start the new service mesh proxy for the application
  # param 1 ${1}: app-proxy name
  # param 2 ${2}: app-proxy service description

  create_service "${1}" "${2}" "/usr/local/bin/consul connect proxy -sidecar-for ${1}"
  sudo systemctl start ${1}
  sudo systemctl status ${1}
  echo "${1} Proxy App Service Build Complete"
}

start_client_proxy_service () {
    # start the new service mesh proxy for the client
    # param 1 ${1}: client-proxy name
    # param 2 ${2}: client-proxy service description
    # param 3 ${3}: client-proxy upstream consul service name
    # param 4 ${4}: client-proxy local service port number
    

    create_service "${1}" "${2}" "/usr/local/bin/consul connect proxy -service ${1} -upstream ${3}:${4}"
    sudo systemctl start ${1}
    sudo systemctl status ${1}
    echo "${1} Proxy Client Service Build Complete"
}


setup_environment () {

    
    source /usr/local/bootstrap/var.env
    
    IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8}'`
    CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
    IP=${CIDR%%/24}
    VAULT_IP=${LEADER_IP}
    
    if [ "${TRAVIS}" == "true" ]; then
        IP="127.0.0.1"
        VAULT_IP=${IP}
    fi

    export VAULT_ADDR=http://${VAULT_IP}:8200
    export VAULT_SKIP_VERIFY=true

    if [ -d /vagrant ]; then
        LOG="/vagrant/logs/VaultServiceIDFactory_${HOSTNAME}.log"
    else
        LOG="${TRAVIS_HOME}/VaultServiceIDFactory.log"
    fi

}

install_go_application () {
    
    pushd /usr/local/bootstrap
    go get -t ./...
    go build -o VaultServiceIDFactory main.go
    killall VaultServiceIDFactory &>/dev/null
    sudo cp VaultServiceIDFactory /usr/local/bin/.
    popd
    sudo chmod +x /usr/local/bin/VaultServiceIDFactory
    if [ ! "${TRAVIS}" == "true" ]; then
        create_service factory "SecretID Factory Service" "/usr/local/bin/VaultServiceIDFactory -ip=127.0.0.1 -vault=\"${VAULT_ADDR}\""
        sudo systemctl start factory
        sudo systemctl status factory
        register_secret_id_service_with_consul
    else
        sudo /usr/local/bin/VaultServiceIDFactory -vault="${VAULT_ADDR}" &> ${LOG} &
    fi


    # start connect application proxy
    start_app_proxy_service approle "App Role Vailt Secret ID Factory"
    sleep 5

}

verify_go_application () {

    if [ "${TRAVIS}" == "true" ]; then

        curl http://${IP}:8314/health 

        IP=127.0.0.1
        curl -s http://${IP}:8314/health 
        # Initialise with Vault Token
        WRAPPED_VAULT_TOKEN=`cat /usr/local/bootstrap/.wrapped-provisioner-token`
        curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{\"token\":\"${WRAPPED_VAULT_TOKEN}\"}" \
        http://${IP}:8314/initialiseme

        curl -s http://${IP}:8314/health 
        # Get a secret ID and test access to the Vault KV Secret
        ROLENAME="id-factory"

        WRAPPED_SECRET_ID=`curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{\"RoleName\":\"${ROLENAME}\"}" \
        http://127.0.0.1:8314/approlename`

        echo "WRAPPED_SECRET_ID : ${WRAPPED_SECRET_ID}"

        SECRET_ID=`curl -s --header "X-Vault-Token: ${WRAPPED_SECRET_ID}" \
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

        APPTOKEN=`curl -s \
            --request POST \
            --data @id-factory-secret-id-login.json \
            ${VAULT_ADDR}/v1/auth/approle/login | jq -r .auth.client_token`

        cat ${LOG}
        
        echo "Reading secret using newly acquired token"

        RESULT=`curl -s \
            --header "X-Vault-Token: ${APPTOKEN}" \
            ${VAULT_ADDR}/v1/kv/example_password | jq -r .data.value`

        if [ "${RESULT}" != "You_have_successfully_accessed_a_secret_password" ];then
            echo "APPLICATION VERIFICATION FAILURE"
            exit 1
        fi

        echo "APPLICATION VERIFICATION SUCCESSFUL"

        curl -s http://${IP}:8314/health 
    else
        # start client client proxy
        start_client_proxy_service democlientproxy "Demo consul connect client proxy" "approle" "9991"

        curl http://${IP}:8314/health 
        # converting for consul connect - point to loopback
        IP=127.0.0.1
        curl -s http://${IP}:9991/health 
        # Initialise with Vault Token
        WRAPPED_VAULT_TOKEN=`cat /usr/local/bootstrap/.wrapped-provisioner-token`
        curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{\"token\":\"${WRAPPED_VAULT_TOKEN}\"}" \
        http://${IP}:8314/initialiseme

        curl -s http://${IP}:9991/health 
        # Get a secret ID and test access to the Vault KV Secret
        ROLENAME="id-factory"

        WRAPPED_SECRET_ID=`curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{\"RoleName\":\"${ROLENAME}\"}" \
        http://127.0.0.1:9991/approlename`

        echo "WRAPPED_SECRET_ID : ${WRAPPED_SECRET_ID}"

        SECRET_ID=`curl -s --header "X-Vault-Token: ${WRAPPED_SECRET_ID}" \
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

        APPTOKEN=`curl -s \
            --request POST \
            --data @id-factory-secret-id-login.json \
            ${VAULT_ADDR}/v1/auth/approle/login | jq -r .auth.client_token`

        cat ${LOG}
        
        echo "Reading secret using newly acquired token"

        RESULT=`curl -s \
            --header "X-Vault-Token: ${APPTOKEN}" \
            ${VAULT_ADDR}/v1/kv/example_password | jq -r .data.value`

        if [ "${RESULT}" != "You_have_successfully_accessed_a_secret_password" ];then
            echo "APPLICATION VERIFICATION FAILURE"
            exit 1
        fi

        echo "APPLICATION VERIFICATION SUCCESSFUL"

        curl -s http://${IP}:9991/health 
    fi



}

set -x
echo 'Start of Factory Service Initialisation and Test'
setup_environment
verify_go_application
echo 'End of Factory Service Initialisation and Test'
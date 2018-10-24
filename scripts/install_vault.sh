#!/usr/bin/env bash
create_service () {
  if [ ! -f /etc/systemd/system/${1}.service ]; then
    
    create_service_user ${1}
    
    sudo tee /etc/systemd/system/${1}.service <<EOF
### BEGIN INIT INFO
# Provides:          ${1}
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${1} agent
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

set -x

IFACE=`route -n | awk '$1 == "192.168.2.0" {print $8}'`
CIDR=`ip addr show ${IFACE} | awk '$2 ~ "192.168.2" {print $2}'`
IP=${CIDR%%/24}

if [ -d /vagrant ]; then
  LOG="/vagrant/logs/vault_${HOSTNAME}.log"
else
  LOG="vault.log"
fi

if [ "${TRAVIS}" == "true" ]; then
IP=${IP:-127.0.0.1}
fi

which /usr/local/bin/vault &>/dev/null || {
    pushd /usr/local/bin
    [ -f vault_0.11.1_linux_amd64.zip ] || {
        sudo wget -q https://releases.hashicorp.com/vault/0.11.1/vault_0.11.1_linux_amd64.zip
    }
    sudo unzip vault_0.11.1_linux_amd64.zip
    sudo chmod +x vault
    popd
}


if [[ "${HOSTNAME}" =~ "leader" ]] || [ "${TRAVIS}" == "true" ]; then
  #lets kill past instance
  sudo killall vault &>/dev/null

  #lets delete old consul storage
  sudo consul kv delete -recurse vault

  #delete old token if present
  [ -f /usr/local/bootstrap/.vault-token ] && sudo rm /usr/local/bootstrap/.vault-token

  #start vault
  if [ "${TRAVIS}" == "true" ]; then
    create_service_user vault
    sudo -u vault cp -r /usr/local/bootstrap/conf/vault.d/* /etc/vault.d/.
    sudo /usr/local/bin/vault server  -dev -dev-listen-address=${IP}:8200 -config=/etc/vault.d/vault.hcl &> ${LOG} &
    sleep 3
    cat ${LOG}
  else
    create_service vault "HashiCorp's Sercret Management Service" "/usr/local/bin/vault server  -dev -dev-listen-address=${IP}:8200 -config=/usr/local/bootstrap/conf/vault.d/vault.hcl"
    sudo systemctl start vault
    sudo systemctl status vault
  fi
  echo vault started
  sleep 3 
  
  #copy token to known location
  sudo find / -name '.vault-token' -exec cp {} /usr/local/bootstrap/.vault-token \; -quit
  sudo chmod ugo+r /usr/local/bootstrap/.vault-token

fi

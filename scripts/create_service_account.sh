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

  create_service ${1} ${2} "consul connect proxy -sidecar-for ${1}"
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
    

    create_service ${1} ${2} "consul connect proxy -service ${1} -upstream ${3}:${4}"
    sudo systemctl start ${1}
    sudo systemctl status ${1}
    echo "${1} Proxy Client Service Build Complete"
}








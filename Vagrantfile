Vagrant.configure("2") do |config|

    #override global variables to fit Vagrant setup
    ENV['GO_GUEST_PORT']||="808"
    ENV['GO_HOST_PORT']||="808"
    ENV['LEADER_NAME']||="leader01"
    ENV['LEADER_IP']||="192.168.2.11"
    ENV['SERVER_COUNT']||="1"
    ENV['DD_API_KEY']||="DON'T FORGET TO SET ME FROM CLI PRIOR TO DEPLOYMENT"
    
    #global config
    config.vm.synced_folder ".", "/vagrant"
    config.vm.synced_folder ".", "/usr/local/bootstrap"
    config.vm.box = "allthingscloud/go-counter-demo"
    config.vm.provision "shell", path: "scripts/install_consul.sh", run: "always"
    config.vm.provision "shell", path: "scripts/install_vault.sh", run: "always"
    config.vm.provision "shell", path: "scripts/install_dd_agent.sh", env: {"DD_API_KEY" => ENV['DD_API_KEY']}

    config.vm.provider "virtualbox" do |v|
        v.memory = 1024
        v.cpus = 1
    end

    config.vm.define "leader01" do |leader01|
        leader01.vm.hostname = ENV['LEADER_NAME']
        leader01.vm.provision "shell", path: "scripts/install_nomad.sh", run: "always"
        leader01.vm.provision "shell", path: "scripts/configure_app_role.sh", run: "always"
        leader01.vm.network "private_network", ip: ENV['LEADER_IP']
        leader01.vm.network "forwarded_port", guest: 8500, host: 8500
        leader01.vm.network "forwarded_port", guest: 8200, host: 8200
    end

    (1..1).each do |i|
        config.vm.define "godev0#{i}" do |devsvr|
            devsvr.vm.hostname = "godev0#{i}"
            devsvr.vm.network "private_network", ip: "192.168.2.#{100+i*10}"
            devsvr.vm.provision "shell", path: "scripts/install_nomad.sh", run: "always"
            devsvr.vm.provision "shell", path: "scripts/install_go_app.sh"
            devsvr.vm.network "forwarded_port", guest: 8314, host: 8314
        end
    end


end

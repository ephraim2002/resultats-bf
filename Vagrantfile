# Charger les variables du fichier .env sans dépendance externe.
env_file = File.expand_path(".env", __dir__)

if File.exist?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    next unless line.include?("=")

    key, value = line.split("=", 2)
    key = key.strip
    value = value.strip

    ENV[key] = value unless ENV.key?(key)
  end
end

NB_APP = ENV.fetch("NB_APP", "2").to_i
ENABLE_HA = ENV.fetch("ENABLE_HA", "false") == "true"
ENABLE_OBS = ENV.fetch("ENABLE_OBS", "false") == "true"

if NB_APP < 2 || NB_APP > 4
  raise "NB_APP doit être compris entre 2 et 4."
end

BOX_NAME = "bento/ubuntu-24.04"
BOX_VERSION = "202404.26.0" 

PROVISION_ENV = {
  "NB_APP" => NB_APP.to_s,
  "DB_NAME" => ENV.fetch("DB_NAME", "resultats"),
  "DB_USER" => ENV.fetch("DB_USER", "resultats_app"),
  "DB_PASSWORD" => ENV.fetch("DB_PASSWORD", ""),
  "REPL_USER" => ENV.fetch("REPL_USER", "repli_user"),
  "REPL_PASSWORD" => ENV.fetch("REPL_PASSWORD", ""),
  "DB_PRIMARY_IP" => "192.168.63.31",
  "DB_REPLICA_IP" => "192.168.63.32"
}

Vagrant.configure("2") do |config|
  config.vm.box = BOX_NAME
  config.vm.box_version = BOX_VERSION
  config.vm.boot_timeout = 600

  config.vm.define "bdd1" do |vm|
    vm.vm.hostname = "bdd1"
    vm.vm.network "private_network", ip: "192.168.63.31"

    vm.vm.provider "virtualbox" do |vb|
      vb.name = "resultats-bf-bdd1"
      vb.memory = 768
      vb.cpus = 1
    end

    vm.vm.provision "shell",
      path: "scripts/setup-database.sh",
      env: PROVISION_ENV
  end

  config.vm.define "bdd2" do |vm|
    vm.vm.hostname = "bdd2"
    vm.vm.network "private_network", ip: "192.168.63.32"

    vm.vm.provider "virtualbox" do |vb|
      vb.name = "resultats-bf-bdd2"
      vb.memory = 768
      vb.cpus = 1
    end

    vm.vm.provision "shell",
      path: "scripts/setup-replica.sh",
      env: PROVISION_ENV
  end

  (1..NB_APP).each do |i|
    config.vm.define "app#{i}" do |vm|
      vm.vm.hostname = "app#{i}"
      vm.vm.network "private_network", ip: "192.168.63.#{20 + i}"

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "resultats-bf-app#{i}"
        vb.memory = 512
        vb.cpus = 1
      end

      vm.vm.provision "shell",
        path: "scripts/setup-app.sh",
        env: PROVISION_ENV
    end
  end

  config.vm.define "lb1" do |vm|
    vm.vm.hostname = "lb1"
    vm.vm.network "private_network", ip: "192.168.63.11"

    # Seul le répartiteur expose le port HTTP sur l'hôte.
    vm.vm.network "forwarded_port",
      guest: 80,
      host: 8080,
      host_ip: "127.0.0.1",
      auto_correct: true

    vm.vm.provider "virtualbox" do |vb|
      vb.name = "resultats-bf-lb1"
      vb.memory = 512
      vb.cpus = 1
    end

    vm.vm.provision "shell",
      path: "scripts/setup-lb.sh",
      env: PROVISION_ENV
  end

  if ENABLE_HA
    config.vm.define "lb2" do |vm|
      vm.vm.hostname = "lb2"
      vm.vm.network "private_network", ip: "192.168.63.12"

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "resultats-bf-lb2"
        vb.memory = 512
        vb.cpus = 1
      end
    end
  end

  if ENABLE_OBS
    config.vm.define "obs" do |vm|
      vm.vm.hostname = "obs"
      vm.vm.network "private_network", ip: "192.168.63.41"

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "resultats-bf-obs"
        vb.memory = 768
        vb.cpus = 1
      end
    end
  end
end
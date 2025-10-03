Vagrant.configure("2") do |config|
    #utilizaremos a Imagem bento ubuntu para o projeto
  config.vm.box = "bento/ubuntu-22.04"

    #setando o nome da vm que vai subir
  config.vm.hostname = "ProjCompNuvem2"
    #sincroniza a pasta atual com a pasta em "/vagrant" dentro da vm que será criada
  config.vm.synced_folder ".", "/vagrant"
    #só definindo um ip fixo para facilitar a comunicação
  config.vm.network "private_network", ip: "192.168.56.50"

    #configurações da vm:
  config.vm.provider "virtualbox" do |vb|
    # Suas configurações de hardware e GUI:
    vb.gui = true
    vb.memory = "4096"  #alocando 4 GB de ram e 2 cpus, assim como proposta nas especificações
    vb.cpus = 2
    vb.name = "ProjCompNuvem2"
  end

    #roda o script de inicialização, instalando as dependencias para o projeto
  config.vm.provision "shell", path: "initialscript.sh"
end
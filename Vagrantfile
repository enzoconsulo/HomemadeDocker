Vagrant.configure("2") do |config|
    #using bento ubuntu iso 
  config.vm.box = "bento/ubuntu-22.04"

    #seting a vm name
  config.vm.hostname = "ProjCompNuvem2"
    #syncronize actual folder with "/vagrant" file/directory inside vm
  config.vm.synced_folder ".", "/vagrant"
    #just defining an ip to make the comunication easier
  config.vm.network "private_network", ip: "192.168.56.50"

    #configure the vm 
  config.vm.provider "virtualbox" do |vb|
    vb.gui = true
    vb.memory = "4096"  #alocating 4 GB to RAM and 2 cpus, likely proposed in statement
    vb.cpus = 2
    vb.name = "ProjCompNuvem2"
  end

    #runs the initial script, installing dependences to project
  config.vm.provision "shell", path: "initialscript.sh"
end
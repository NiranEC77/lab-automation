before starting the scriptrun this to install git and clone the repo

echo 'VMware123!VMware123!' | sudo -S sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y && sudo apt install git -y && cd ~/Downloads && git clone https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git && cd vcf9-adv-deploy-lab-setup && chmod +x setup.sh && ./setup.sh && git clone https://github.com/NiranEC77/lab-automation && cd lab-automation && chmod +x setup-lab.sh && ./setup-lab.sh

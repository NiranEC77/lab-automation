before starting the script 

sudo sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources &&
sudo apt update -y &&
sudo apt install git -y &&
cd ~/Downloads &&
git clone https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git &&
cd vcf9-adv-deploy-lab-setup &&
chmod +x setup.sh &&
./setup.sh

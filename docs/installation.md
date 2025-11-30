# installation du lab

## prerequis

- fedora/ubuntu avec kvm installé
- 40gb d'espace disque libre
- 8gb ram minimum
- processeur avec virtualisation activée (vt-x/amd-v)

## etape 1 : installer kvm
```bash
# fedora
sudo dnf install @virtualization

# ubuntu
sudo apt install qemu-kvm libvirt-daemon-system
```

## etape 2 : creer les reseaux
```bash
# copier les fichiers xml
cd configs/network

# creer chaque reseau
for net in *.xml; do
    sudo virsh net-define $net
    name=$(basename $net .xml)
    sudo virsh net-start $name
    sudo virsh net-autostart $name
done
```

## etape 3 : creer les vms
```bash
# telecharger ubuntu server iso
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso

# creer les disques
qemu-img create -f qcow2 bastion.qcow2 8G
qemu-img create -f qcow2 web.qcow2 10G
qemu-img create -f qcow2 app.qcow2 10G
qemu-img create -f qcow2 database.qcow2 12G

# installer bastion
virt-install \
  --name bastion \
  --ram 2048 \
  --vcpus 1 \
  --disk path=bastion.qcow2,format=qcow2 \
  --cdrom ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan99-management \
  --graphics vnc

# (repeter pour les autres vms avec leurs reseaux respectifs)
```

## etape 4 : configuration du bastion

une fois ubuntu installé sur bastion :
```bash
# se connecter
ssh user@ip-temporaire

# ajouter les interfaces
# (voir configs/vms/bastion.xml pour les details)
sudo virsh attach-interface bastion network vlan10-dmz --config
sudo virsh attach-interface bastion network vlan20-backend --config
sudo virsh attach-interface bastion network vlan30-data --config

# redemarrer
sudo virsh reboot bastion
```

configurer les ips statiques dans `/etc/netplan/01-netcfg.yaml` :
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      addresses: [192.168.99.254/24]
      routes:
        - to: default
          via: 192.168.99.1
      nameservers:
        addresses: [8.8.8.8]
    enp7s0:
      addresses: [192.168.10.254/24]
    enp8s0:
      addresses: [192.168.20.254/24]
    enp9s0:
      addresses: [192.168.30.254/24]
```
```bash
sudo netplan apply
```

activer le routage :
```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

appliquer le script firewall :
```bash
sudo cp scripts/configuration/firewall-bastion.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/firewall-bastion.sh
sudo /usr/local/bin/firewall-bastion.sh
```

## etape 5 : configuration des autres vms

pour chaque vm, configurer l'ip statique et la route par defaut vers le bastion.

exemple pour app :
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      addresses: [192.168.20.10/24]
      routes:
        - to: default
          via: 192.168.20.254
      nameservers:
        addresses: [8.8.8.8]
```

## etape 6 : installer les services

### web (nginx)
```bash
ssh admelmoh-web@192.168.10.10

sudo apt install nginx
# configurer le site (voir configs/)
sudo systemctl enable nginx
```

### app (flask)
```bash
ssh admelmoh@192.168.20.10

sudo apt install python3 python3-pip python3-venv
mkdir ~/api && cd ~/api
python3 -m venv venv
source venv/bin/activate
pip install flask psycopg2-binary

# copier app.py
# configurer le service systemd
sudo systemctl enable api-lab
```

### database (postgresql)
```bash
ssh elmoh@192.168.30.10

sudo apt install postgresql
sudo -u postgres psql
# creer la db et l'user (voir docs/)
```

## verification
```bash
# depuis le bastion
ping 192.168.10.10
ping 192.168.20.10
ping 192.168.30.10

curl http://192.168.10.10
curl http://192.168.20.10:3000/health
```

# Guide d'installation

Ce guide détaille toutes les étapes pour reproduire l'infrastructure.

## Prérequis

- Fedora 41+ (ou distribution avec KVM)
- 16 GB RAM minimum
- 100 GB d'espace disque
- Virtualisation activée dans le BIOS (Intel VT-x / AMD-V)

## Étape 1 : Installation de KVM
```bash
# Installation des paquets
sudo dnf install @virtualization

# Démarrage de libvirtd
sudo systemctl enable --now libvirtd

# Vérification
sudo virsh list --all
```

## Étape 2 : Téléchargement de l'ISO Ubuntu
```bash
cd ~/Downloads
wget https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso
```

## Étape 3 : Création des réseaux virtuels (VLANs)

### Configuration des réseaux

Les réseaux sont configurés en mode NAT. Les bridges KVM gèrent le routage entre VLANs.
```bash
cd cybersec-lab/scripts
sudo ./create-vlans.sh
```

Structure XML des réseaux (exemple pour vlan20-backend) :
```xml
<network>
  <name>vlan20-backend</name>
  <forward mode='nat'/>
  <bridge name='virbr-nd' stp='on' delay='0'/>
  <ip address='192.168.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.20.100' end='192.168.20.200'/>
    </dhcp>
  </ip>
</network>
```

Important : le mode NAT est utilisé car le mode route nécessite une configuration plus complexe au niveau du système hôte.

### Vérification
```bash
sudo virsh net-list --all
```

Résultat attendu :
```
 Nom                 État    Démarrage automatique
-------------------------------------------------
 vlan10-dmz          actif   oui
 vlan20-backend      actif   oui
 vlan30-data         actif   oui
 vlan99-management   actif   oui
```

## Étape 4 : Création des VMs

### 4.1 VM Bastion
```bash
sudo virt-install \
  --name bastion \
  --memory 2048 \
  --vcpus 2 \
  --disk size=10 \
  --cdrom ~/Downloads/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan99-management \
  --graphics none \
  --console pty,target_type=serial
```

Configuration manuelle :
- Hostname : bastion
- User : admelmoh / password
- Installation minimale
- OpenSSH server : oui

### 4.2 VM Web
```bash
sudo virt-install \
  --name web \
  --memory 2048 \
  --vcpus 2 \
  --disk size=10 \
  --cdrom ~/Downloads/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan10-dmz \
  --graphics none \
  --console pty,target_type=serial
```

Configuration manuelle :
- Hostname : web
- User : admelmoh-web / password

### 4.3 VM App
```bash
sudo virt-install \
  --name app \
  --memory 2048 \
  --vcpus 2 \
  --disk size=10 \
  --cdrom ~/Downloads/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan20-backend \
  --graphics none \
  --console pty,target_type=serial
```

Configuration manuelle :
- Hostname : app
- User : admelmoh / password

### 4.4 VM Database
```bash
sudo virt-install \
  --name database \
  --memory 2048 \
  --vcpus 2 \
  --disk size=12 \
  --cdrom ~/Downloads/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan30-data \
  --graphics none \
  --console pty,target_type=serial
```

Configuration manuelle :
- Hostname : database
- User : elmoh / password

## Étape 5 : Configuration réseau sur l'hôte Fedora

Cette étape est critique pour que le routage inter-VLAN fonctionne.
```bash
# Activer le forwarding IP
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Désactiver le reverse path filtering sur tous les bridges
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-nd.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-ta.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-mz.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-nt.rp_filter=0

# Rendre permanent
cat << EOF | sudo tee -a /etc/sysctl.conf
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF

# Configurer iptables pour le masquerading
sudo iptables -P FORWARD ACCEPT
sudo iptables -t nat -A POSTROUTING -s 192.168.99.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.30.0/24 -j MASQUERADE

# Sauvegarder les règles iptables
sudo iptables-save | sudo tee /etc/sysconfig/iptables
```

## Étape 6 : Configuration IPs statiques sur les VMs

Les VMs reçoivent des IPs DHCP par défaut. On configure des IPs statiques.

### Script automatisé
```bash
cd cybersec-lab/scripts
./enable-passwordless-sudo.sh
./setup-static-ips.sh
```

### Configuration manuelle (exemple pour App)

SSH dans la VM :
```bash
ssh admelmoh@192.168.20.133  # IP DHCP
```

Éditer netplan :
```bash
sudo nano /etc/netplan/01-netcfg.yaml
```
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: no
      addresses:
        - 192.168.20.10/24
      routes:
        - to: default
          via: 192.168.20.1
        - to: 192.168.99.0/24
          via: 192.168.20.1
        - to: 192.168.10.0/24
          via: 192.168.20.1
        - to: 192.168.30.0/24
          via: 192.168.20.1
      nameservers:
        addresses:
          - 8.8.8.8
```

Appliquer :
```bash
sudo netplan apply
```

Répéter pour toutes les VMs avec leurs IPs respectives :
- Bastion : 192.168.99.10
- Web : 192.168.10.10
- App : 192.168.20.10
- Database : 192.168.30.10

## Étape 7 : Sécurisation du Bastion

### 7.1 Configuration SSH avec clés

Sur l'hôte Fedora :
```bash
cd ~/.ssh
ssh-keygen -t ed25519 -f bastion_key -C "cle pour bastion"
ssh-copy-id -o PubkeyAuthentication=no -i bastion_key.pub admelmoh@192.168.99.10
```

Configuration SSH :
```bash
nano ~/.ssh/config
```
```
Host bastion
    HostName 192.168.99.10
    User admelmoh
    Port 2222
    IdentityFile ~/.ssh/bastion_key
    IdentitiesOnly yes
```

Sur le bastion, éditer sshd_config :
```bash
ssh bastion
sudo nano /etc/ssh/sshd_config
```

Modifier ces lignes :
```
Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
```

Redémarrer SSH :
```bash
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
```

### 7.2 Installation de Fail2ban
```bash
sudo apt update
sudo apt install fail2ban -y
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Configuration SSH dans jail.local :
```ini
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 600
findtime = 300
```

Démarrer fail2ban :
```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 7.3 Firewall iptables

Le bastion filtre les connexions mais ne gère PAS le routage (c'est l'hôte Fedora qui s'en charge).
```bash
sudo nano /usr/local/bin/firewall-bastion.sh
```
```bash
#!/bin/bash
# Firewall bastion - filtrage uniquement

# Vider les règles existantes
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Politique par défaut : bloquer
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Autoriser loopback
iptables -A INPUT -i lo -j ACCEPT

# Autoriser connexions établies
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Autoriser SSH sur port 2222
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT

# Autoriser ping
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Sauvegarder
netfilter-persistent save

echo "Firewall bastion configuré"
```
```bash
sudo chmod +x /usr/local/bin/firewall-bastion.sh
sudo /usr/local/bin/firewall-bastion.sh
```

## Étape 8 : Installation des services

### 8.1 Serveur Web (Nginx)
```bash
ssh admelmoh-web@192.168.10.10
sudo apt update
sudo apt install nginx -y
```

Créer le site :
```bash
sudo mkdir -p /var/www/lab-cybersec
sudo nano /var/www/lab-cybersec/index.html
```

Configuration Nginx :
```bash
sudo nano /etc/nginx/sites-available/lab-cybersec
```
```nginx
server {
    listen 80;
    server_name _;
    root /var/www/lab-cybersec;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    server_tokens off;
}
```
```bash
sudo ln -s /etc/nginx/sites-available/lab-cybersec /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### 8.2 Serveur Application (Flask)
```bash
ssh admelmoh@192.168.20.10
sudo apt update
sudo apt install python3 python3-pip python3-venv -y

mkdir ~/api
cd ~/api
python3 -m venv venv
source venv/bin/activate
pip install flask psycopg2-binary
```

Créer l'API (voir `configs/app/app.py`).

Service systemd :
```bash
sudo nano /etc/systemd/system/api-lab.service
```
```ini
[Unit]
Description=API Lab Cybersec
After=network.target

[Service]
Type=simple
User=admelmoh
WorkingDirectory=/home/admelmoh/api
Environment="PATH=/home/admelmoh/api/venv/bin"
ExecStart=/home/admelmoh/api/venv/bin/python /home/admelmoh/api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable api-lab
sudo systemctl start api-lab
```

### 8.3 Serveur Database (PostgreSQL)
```bash
ssh elmoh@192.168.30.10
sudo apt update
sudo apt install postgresql postgresql-contrib -y
```

Configuration de la base :
```bash
sudo -u postgres psql
```
```sql
CREATE DATABASE labdb;
CREATE USER labuser WITH PASSWORD 'labpassword';
GRANT ALL PRIVILEGES ON DATABASE labdb TO labuser;

\c labdb

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL
);

GRANT ALL PRIVILEGES ON TABLE users TO labuser;
GRANT USAGE, SELECT ON SEQUENCE users_id_seq TO labuser;

INSERT INTO users (username, email) VALUES 
    ('admin', 'admin@lab.local'),
    ('user1', 'user1@lab.local'),
    ('user2', 'user2@lab.local');

\q
```

Configuration réseau :
```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
```

Modifier :
```
listen_addresses = '*'
```
```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Ajouter à la fin :
```
# Autoriser app à se connecter
host    labdb    labuser    192.168.20.0/24    md5
# Autoriser bastion et autres VLANs si nécessaire
host    labdb    labuser    192.168.99.0/24    md5
host    labdb    labuser    192.168.30.0/24    md5
```
```bash
sudo systemctl restart postgresql
```

## Étape 9 : Tests

### Test connectivité inter-VLAN

Depuis App :
```bash
ping -c 3 192.168.30.10  # Database
ping -c 3 192.168.10.10  # Web
```

### Test PostgreSQL
```bash
ssh admelmoh@192.168.20.10
psql -h 192.168.30.10 -U labuser -d labdb -c "SELECT * FROM users;"
```

### Test API
```bash
curl http://localhost:3000/health
curl http://localhost:3000/users
```

### Test Web

Depuis le bastion :
```bash
ssh bastion
curl http://192.168.10.10
```

## Snapshots

Créer des snapshots après chaque étape importante :
```bash
for VM in bastion web app database; do
    sudo virsh snapshot-create-as --domain $VM --name "config-complete" --description "Configuration complète"
done
```

## Dépannage

En cas de problème, voir [docs/problemes/](../problemes/).

Si tout répond, l'installation est complète !

## Problèmes courants

**Les VMs ne se pingent pas** : vérifier que ip_forward=1 et rp_filter=0 sur l'hôte ET sur le bastion.

**Connection refused sur les services** : vérifier le firewall du bastion et les règles FORWARD.

**DHCP ne donne pas d'IP** : vérifier que les réseaux sont bien démarrés avec `sudo virsh net-list`.

**Conflit d'IP** : utiliser .254 pour le bastion et .10 pour les services pour éviter les conflits avec les bridges (.1).


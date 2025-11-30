# Installation du lab

Guide complet pour reproduire l'infrastructure de A à Z.

## Prérequis

- Fedora/Ubuntu avec KVM installé
- 40GB d'espace disque libre
- 8GB RAM minimum (16GB recommandé)
- Processeur avec virtualisation activée (VT-x/AMD-V)

Vérifier que la virtualisation est activée :
```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
# doit retourner un nombre > 0
```

## Etape 1 : Installation de KVM

### Sur Fedora
```bash
sudo dnf install @virtualization
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# ajouter ton user au groupe libvirt
sudo usermod -a -G libvirt $(whoami)
# deconnexion/reconnexion necessaire
```

### Sur Ubuntu
```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system virtinst virt-manager bridge-utils
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# ajouter ton user au groupe
sudo usermod -a -G libvirt $(whoami)
```

Vérifier que KVM fonctionne :
```bash
sudo virsh list --all
# doit afficher une liste vide sans erreur
```

## Etape 2 : Création des réseaux virtuels

### Créer les fichiers XML des réseaux
```bash
mkdir -p ~/lab-infra/configs/network
cd ~/lab-infra/configs/network
```

**vlan99-management.xml** :
```xml
<network>
  <name>vlan99-management</name>
  <forward mode='route'/>
  <bridge name='virbr-nt' stp='on' delay='0'/>
  <ip address='192.168.99.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.99.100' end='192.168.99.200'/>
    </dhcp>
  </ip>
</network>
```

**vlan10-dmz.xml** :
```xml
<network>
  <name>vlan10-dmz</name>
  <forward mode='route'/>
  <bridge name='virbr-mz' stp='on' delay='0'/>
  <ip address='192.168.10.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.10.100' end='192.168.10.200'/>
    </dhcp>
  </ip>
</network>
```

**vlan20-backend.xml** :
```xml
<network>
  <name>vlan20-backend</name>
  <forward mode='route'/>
  <bridge name='virbr-nd' stp='on' delay='0'/>
  <ip address='192.168.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.20.100' end='192.168.20.200'/>
    </dhcp>
  </ip>
</network>
```

**vlan30-data.xml** :
```xml
<network>
  <name>vlan30-data</name>
  <forward mode='route'/>
  <bridge name='virbr-ta' stp='on' delay='0'/>
  <ip address='192.168.30.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.30.100' end='192.168.30.200'/>
    </dhcp>
  </ip>
</network>
```

### Créer les réseaux
```bash
# definir chaque reseau
sudo virsh net-define vlan99-management.xml
sudo virsh net-define vlan10-dmz.xml
sudo virsh net-define vlan20-backend.xml
sudo virsh net-define vlan30-data.xml

# demarrer les reseaux
sudo virsh net-start vlan99-management
sudo virsh net-start vlan10-dmz
sudo virsh net-start vlan20-backend
sudo virsh net-start vlan30-data

# les rendre permanents
sudo virsh net-autostart vlan99-management
sudo virsh net-autostart vlan10-dmz
sudo virsh net-autostart vlan20-backend
sudo virsh net-autostart vlan30-data

# verifier
sudo virsh net-list --all
```

**Note importante** : le mode `route` est essentiel. J'avais d'abord essayé avec `nat` mais ça bloquait le routage inter-VLAN. Avec `route`, libvirt laisse passer le trafic entre les bridges.

## Etape 3 : Téléchargement de l'ISO Ubuntu
```bash
cd ~/lab-infra
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso

# verifier le telechargement
ls -lh ubuntu-24.04.3-live-server-amd64.iso
# doit faire environ 3GB
```

## Etape 4 : Création des VMs

### Créer les disques virtuels
```bash
mkdir -p ~/lab-infra/vms
cd ~/lab-infra/vms

# creer les disques
qemu-img create -f qcow2 bastion.qcow2 8G
qemu-img create -f qcow2 web.qcow2 10G
qemu-img create -f qcow2 app.qcow2 10G
qemu-img create -f qcow2 database.qcow2 12G
```

### Installer la VM bastion
```bash
sudo virt-install \
  --name bastion \
  --ram 2048 \
  --vcpus 1 \
  --disk path=$HOME/lab-infra/vms/bastion.qcow2,format=qcow2 \
  --cdrom $HOME/lab-infra/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan99-management \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole
```

Ouvrir la console pour l'installation :
```bash
sudo virt-viewer bastion
```

**Configuration lors de l'installation Ubuntu** :
- Hostname : `bastion`
- Username : `admelmoh` (ou ton choix)
- Password : ton mot de passe
- Cocher "Install OpenSSH server"
- Ne pas installer de snaps additionnels

Une fois l'installation terminée, tu verras le message "Please remove the installation medium". Appuie sur Enter puis :
```bash
sudo virsh destroy bastion
sudo virsh start bastion
```

**Problème rencontré** : au début le message "remove installation medium" bloquait. Il faut éteindre la VM et la redémarrer pour qu'elle boot sur le disque au lieu du CD.

### Ajouter les interfaces réseau supplémentaires au bastion
```bash
# arreter le bastion
sudo virsh shutdown bastion
sleep 10

# ajouter 3 interfaces (une pour chaque vlan)
sudo virsh attach-interface bastion network vlan10-dmz --model virtio --config
sudo virsh attach-interface bastion network vlan20-backend --model virtio --config
sudo virsh attach-interface bastion network vlan30-data --model virtio --config

# redemarrer
sudo virsh start bastion
sleep 20

# verifier les interfaces
sudo virsh domiflist bastion
```

Tu dois voir 4 interfaces maintenant.

### Installer les autres VMs

Même procédure pour web, app et database mais avec un seul réseau chacune :

**VM web** :
```bash
sudo virt-install \
  --name web \
  --ram 2048 \
  --vcpus 1 \
  --disk path=$HOME/lab-infra/vms/web.qcow2,format=qcow2 \
  --cdrom $HOME/lab-infra/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan10-dmz \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole

sudo virt-viewer web
# installer ubuntu
# hostname: web, user: admelmoh-web
```

**VM app** :
```bash
sudo virt-install \
  --name app \
  --ram 2048 \
  --vcpus 1 \
  --disk path=$HOME/lab-infra/vms/app.qcow2,format=qcow2 \
  --cdrom $HOME/lab-infra/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan20-backend \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole

sudo virt-viewer app
# installer ubuntu
# hostname: app, user: admelmoh
```

**VM database** :
```bash
sudo virt-install \
  --name database \
  --ram 2048 \
  --vcpus 1 \
  --disk path=$HOME/lab-infra/vms/database.qcow2,format=qcow2 \
  --cdrom $HOME/lab-infra/ubuntu-24.04.3-live-server-amd64.iso \
  --os-variant ubuntu24.04 \
  --network network=vlan30-data \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole

sudo virt-viewer database
# installer ubuntu
# hostname: database, user: elmoh
```

**Astuce** : pour éjecter le CD après l'installation sur chaque VM :
```bash
sudo virsh destroy nom-vm
sudo virsh edit nom-vm
# supprimer le bloc <disk device='cdrom'>...</disk>
sudo virsh start nom-vm
```

## Etape 5 : Configuration du routage sur le bastion

Se connecter au bastion :
```bash
# trouver son ip dhcp temporaire
sudo virsh net-dhcp-leases vlan99-management

# se connecter
ssh admelmoh@192.168.99.xxx
```

### Configurer les IPs statiques
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
        - 192.168.99.254/24
      routes:
        - to: default
          via: 192.168.99.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
    enp7s0:
      dhcp4: no
      addresses:
        - 192.168.10.254/24
    enp8s0:
      dhcp4: no
      addresses:
        - 192.168.20.254/24
    enp9s0:
      dhcp4: no
      addresses:
        - 192.168.30.254/24
```

**Important** : utiliser `.254` au lieu de `.1` pour éviter le conflit avec les bridges KVM. C'est le problème que j'ai eu au début : le bastion avait la même IP que le bridge, résultat les paquets allaient au mauvais endroit.
```bash
sudo netplan apply

# verifier
ip addr show
```

### Activer le routage IP
```bash
# activer temporairement
sudo sysctl -w net.ipv4.ip_forward=1

# rendre permanent
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# desactiver reverse path filtering (important!)
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
echo "net.ipv4.conf.all.rp_filter=0" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" | sudo tee -a /etc/sysctl.conf
```

**Pourquoi rp_filter=0** : par défaut Linux refuse de router les paquets si la réponse ne peut pas revenir par la même interface. Avec plusieurs interfaces sur différents réseaux, ça bloque tout. J'ai mis du temps à comprendre ça.

### Configurer le firewall
```bash
sudo nano /usr/local/bin/firewall-bastion.sh
```
```bash
#!/bin/bash
# firewall bastion - config iptables avec routage

# vider toutes les regles existantes
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# politique par defaut : tout bloquer
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# === INPUT : vers le bastion lui-meme ===

# autoriser loopback
iptables -A INPUT -i lo -j ACCEPT

# autoriser connexions etablies
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# autoriser ssh sur port 2222 (on changera le port plus tard)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# autoriser ping
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# === FORWARD : routage entre vlans ===

# autoriser connexions etablies
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# autoriser ping entre vlans
iptables -A FORWARD -p icmp --icmp-type echo-request -j ACCEPT
iptables -A FORWARD -p icmp --icmp-type echo-reply -j ACCEPT

# web peut aller vers app sur port 3000
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -p tcp --dport 3000 -j ACCEPT

# app peut aller vers database sur port 5432
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.30.0/24 -p tcp --dport 5432 -j ACCEPT

# sauvegarder
netfilter-persistent save

echo "firewall bastion configure !"
```
```bash
sudo chmod +x /usr/local/bin/firewall-bastion.sh
sudo /usr/local/bin/firewall-bastion.sh
```

## Etape 6 : Configuration des autres VMs

### VM web (192.168.10.10)
```bash
ssh admelmoh-web@192.168.10.xxx

sudo nano /etc/netplan/01-netcfg.yaml
```
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: no
      addresses:
        - 192.168.10.10/24
      routes:
        - to: default
          via: 192.168.10.254
        - to: 192.168.20.0/24
          via: 192.168.10.254
        - to: 192.168.30.0/24
          via: 192.168.10.254
      nameservers:
        addresses:
          - 8.8.8.8
```
```bash
sudo netplan apply
```

### VM app (192.168.20.10)
```bash
ssh admelmoh@192.168.20.xxx

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
          via: 192.168.20.254
        - to: 192.168.10.0/24
          via: 192.168.20.254
        - to: 192.168.30.0/24
          via: 192.168.20.254
        - to: 192.168.99.0/24
          via: 192.168.20.254
      nameservers:
        addresses:
          - 8.8.8.8
```
```bash
sudo netplan apply
```

### VM database (192.168.30.10)
```bash
ssh elmoh@192.168.30.xxx

sudo nano /etc/netplan/01-netcfg.yaml
```
```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: no
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.254
        - to: 192.168.10.0/24
          via: 192.168.30.254
        - to: 192.168.20.0/24
          via: 192.168.30.254
      nameservers:
        addresses:
          - 8.8.8.8
```
```bash
sudo netplan apply
```

**Pourquoi ajouter des routes vers chaque VLAN** : sans ça, les VMs ne savent pas où envoyer les paquets pour les autres réseaux. Elles doivent savoir que pour joindre un autre VLAN, il faut passer par le bastion (.254).

## Etape 7 : Activer le routage sur l'hôte Fedora

Sur ton PC Fedora (pas dans les VMs) :
```bash
# activer ip forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# desactiver rp_filter sur les bridges
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-nd.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-ta.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-mz.rp_filter=0
sudo sysctl -w net.ipv4.conf.virbr-nt.rp_filter=0

# politique forward accept
sudo iptables -P FORWARD ACCEPT

# masquerading pour le nat
sudo iptables -t nat -A POSTROUTING -s 192.168.99.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.20.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 192.168.30.0/24 -j MASQUERADE
```

**Pourquoi sur l'hôte aussi** : l'hôte gère les bridges virtuels et doit aussi autoriser le forwarding entre eux. C'est une couche supplémentaire que j'avais oubliée au début.

## Etape 8 : Test de connectivité
```bash
# depuis le bastion
ssh admelmoh@192.168.99.254

# tester ping vers toutes les vms
ping -c 3 192.168.10.10
ping -c 3 192.168.20.10
ping -c 3 192.168.30.10
```

Si les pings passent, le routage fonctionne !

## Etape 9 : Installation des services

### Nginx sur web
```bash
ssh admelmoh-web@192.168.10.10

sudo apt update
sudo apt install nginx -y

sudo mkdir -p /var/www/lab-cybersec
sudo nano /var/www/lab-cybersec/index.html
```
```html
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Lab Cybersec</title>
</head>
<body>
    <h1>Lab Cybersécurité - Serveur Web</h1>
    <div class="info">
        <h2>Infrastructure sécurisée</h2>
        <p>Segmentation réseau (VLANs)</p>
        <p>Bastion avec firewall</p>
        <p>Serveur web isolé en DMZ</p>
    </div>
</body>
</html>
```
```bash
sudo nano /etc/nginx/sites-available/lab-cybersec
```
```nginx
server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    
    root /var/www/lab-cybersec;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # desactiver server tokens (securite)
    server_tokens off;
}
```
```bash
sudo ln -s /etc/nginx/sites-available/lab-cybersec /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

### API Flask sur app
```bash
ssh admelmoh@192.168.20.10

sudo apt update
sudo apt install python3 python3-pip python3-venv -y

mkdir ~/api && cd ~/api
python3 -m venv venv
source venv/bin/activate
pip install flask psycopg2-binary
```
```bash
nano app.py
```
```python
from flask import Flask, jsonify, request
import psycopg2
from psycopg2 import Error

app = Flask(__name__)

# config db
DB_CONFIG = {
    'host': '192.168.30.10',
    'database': 'labdb',
    'user': 'labuser',
    'password': 'labpassword'
}

def get_db_connection():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        return conn
    except Error as e:
        print(f"erreur connexion db: {e}")
        return None

@app.route('/')
def home():
    return jsonify({
        'message': 'api lab cybersec',
        'status': 'running',
        'endpoints': ['/health', '/users', '/stats']
    })

@app.route('/health')
def health():
    # test connexion db
    conn = get_db_connection()
    if conn:
        conn.close()
        db_status = 'ok'
    else:
        db_status = 'error'
    
    return jsonify({
        'api': 'ok',
        'database': db_status
    })

@app.route('/users', methods=['GET'])
def get_users():
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'db connection failed'}), 500
    
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT id, username, email FROM users')
        users = cursor.fetchall()
        cursor.close()
        conn.close()
        
        result = []
        for user in users:
            result.append({
                'id': user[0],
                'username': user[1],
                'email': user[2]
            })
        
        return jsonify(result)
    except Error as e:
        return jsonify({'error': str(e)}), 500

@app.route('/stats')
def stats():
    return jsonify({
        'total_requests': 'xxx',
        'uptime': 'xxx',
        'version': '1.0'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
```

Créer le service systemd :
```bash
deactivate

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
sudo systemctl status api-lab
```

### PostgreSQL sur database
```bash
ssh elmoh@192.168.30.10

sudo apt update
sudo apt install postgresql postgresql-contrib -y

# creer la db et l'user
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
SELECT * FROM users;
\q
```

Configurer l'écoute réseau :
```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
```

Chercher `listen_addresses` et changer en :
```
listen_addresses = '*'
```

Autoriser les connexions :
```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf
```

Ajouter à la fin :
```
# autoriser app a se connecter
host    labdb    labuser    192.168.20.0/24    md5
# autoriser bastion (pour les tests)
host    labdb    labuser    192.168.99.0/24    md5
host    labdb    labuser    192.168.30.0/24    md5
```
```bash
sudo systemctl restart postgresql
```

## Etape 10 : Sécurisation SSH du bastion

### Générer les clés SSH

Sur ton PC Fedora :
```bash
cd ~/.ssh
ssh-keygen -t ed25519 -f bastion_key -C "cle pour bastion"
# ne pas mettre de passphrase pour simplifier
```

Copier la clé sur le bastion :
```bash
ssh-copy-id -i ~/.ssh/bastion_key.pub admelmoh@192.168.99.254
```

Tester :
```bash
ssh -i ~/.ssh/bastion_key admelmoh@192.168.99.254
# doit se connecter sans password
exit
```

### Configurer SSH

Sur le bastion :
```bash
ssh admelmoh@192.168.99.254

sudo nano /etc/ssh/sshd_config
```

Modifier ces lignes :
```
Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
```
```bash
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh
```

### Installer fail2ban
```bash
sudo apt install fail2ban -y

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Chercher `[sshd]` et modifier :
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
```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo systemctl status fail2ban
```

### Mettre à jour le firewall
```bash
sudo nano /usr/local/bin/firewall-bastion.sh
```

Changer le port SSH de 22 à 2222 :
```bash
# autoriser ssh sur port 2222
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
```
```bash
sudo /usr/local/bin/firewall-bastion.sh
```

### Tester

Depuis ton PC, avec le nouveau port et les clés :
```bash
nano ~/.ssh/config
```

Ajouter :
```
Host bastion
    HostName 192.168.99.254
    User admelmoh
    Port 2222
    IdentityFile ~/.ssh/bastion_key
    IdentitiesOnly yes
```
```bash
ssh bastion
# doit se connecter sans password
```

## Etape 11 : Tests finaux
```bash
# depuis le bastion
ssh bastion

# ping toutes les vms
ping -c 3 192.168.10.10
ping -c 3 192.168.20.10
ping -c 3 192.168.30.10

# test web
curl http://192.168.10.10

# test api
curl http://192.168.20.10:3000/health
curl http://192.168.20.10:3000/users
```

Si tout répond, l'installation est complète !

## Notes importantes

### Snapshots recommandés

Faire des snapshots après chaque étape importante :
```bash
sudo virsh snapshot-create-as bastion "config-reseau" "apres config reseau"
sudo virsh snapshot-create-as bastion "config-securite" "apres config ssh et firewall"
```

### Problèmes courants

**Les VMs ne se pingent pas** : vérifier que ip_forward=1 et rp_filter=0 sur l'hôte ET sur le bastion.

**Connection refused sur les services** : vérifier le firewall du bastion et les règles FORWARD.

**DHCP ne donne pas d'IP** : vérifier que les réseaux sont bien démarrés avec `sudo virsh net-list`.

**Conflit d'IP** : utiliser .254 pour le bastion et .10 pour les services pour éviter les conflits avec les bridges (.1).


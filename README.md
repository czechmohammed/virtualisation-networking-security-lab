# Infrastructure virtualisée sécurisée

Projet d'infrastructure réseau avec segmentation VLAN et architecture multi-tier.

## Contexte

J'ai monté ce lab pour apprendre les bases du routage inter-VLAN, la segmentation réseau et la sécurisation d'infrastructure. Au départ c'était juste pour comprendre comment isoler des services entre eux mais c'est devenu un projet plus complet.

## Architecture

![Schema réseau](images/architecture.png)

### Composants

- **bastion** (192.168.99.254) : routeur central + firewall
- **web** (192.168.10.10) : serveur nginx en DMZ
- **app** (192.168.20.10) : API Flask
- **database** (192.168.30.10) : PostgreSQL

Chaque VM est sur son propre VLAN pour l'isolation. Le bastion a une interface sur chaque VLAN et fait le routage entre eux.

## Installation

Guide complet d'installation : [docs/installation.md](docs/installation.md)

Résumé des étapes :

1. Installer KVM/libvirt sur l'hôte
2. Créer les 4 réseaux virtuels (voir `configs/network/`)
3. Créer les 4 VMs avec Ubuntu Server
4. Configurer le bastion avec 4 interfaces réseau
5. Activer le routage IP et configurer le firewall
6. Installer les services (nginx, flask, postgresql)
7. Configurer les IPs statiques sur chaque VM

**Prérequis** :
- 40GB d'espace disque
- 8GB de RAM minimum
- Processeur avec virtualisation activée

## Tests

Tous les tests de validation sont documentés dans [docs/tests.md](docs/tests.md).

Résumé des tests effectués :

- **Connectivité réseau** : ping, traceroute, vérification du routage
- **Services** : nginx, API Flask, PostgreSQL
- **Sécurité** : SSH, fail2ban, firewall iptables
- **Résilience** : redémarrage des services

Tous les tests sont passés avec succès.

## Ce que j'ai appris

### VLANs et segmentation

Au début j'ai essayé de laisser KVM gérer le routage automatiquement mais ça marchait pas. Les bridges virtuels (virbr-*) ne routaient pas entre eux même avec ip_forward activé.

La solution : donner plusieurs interfaces au bastion et configurer le routage manuellement. Ça m'a fait comprendre comment un routeur fonctionne vraiment.

### Problèmes rencontrés

**Conflit d'adresses MAC** : le plus gros problème que j'ai eu. Le bridge KVM (virbr-nd) avait la même IP que l'interface du bastion (192.168.20.1). Résultat : app envoyait les paquets au bridge au lieu du bastion.

Solution trouvée :
```bash
# verifier les mac
ip link show virbr-nd
sudo virsh domiflist bastion

# forcer la bonne mac dans arp
sudo arp -s 192.168.20.1 52:54:00:97:cc:1e
```

Sauf que ça a bloqué le terminal et cassé le réseau. J'ai dû :
1. accéder via console virt-manager
2. supprimer l'entrée ARP (`sudo arp -d 192.168.20.1`)
3. redémarrer SSH
4. reconfigurer le réseau virtuel

Documentation complète : [docs/problemes/routage-intervlan.md](docs/problemes/routage-intervlan.md)

**Routage qui marchait pas** : pendant longtemps app pouvait pas ping database. Les paquets arrivaient au bastion mais repartaient pas.

Ce qui manquait :
```bash
# activer le forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# desactiver reverse path filtering
sysctl -w net.ipv4.conf.all.rp_filter=0
```

**Mode NAT vs route dans libvirt** : au final j'ai dû passer les réseaux virtuels de mode "nat" à mode "route" pour que libvirt arrête de bloquer le trafic inter-VLAN.
```bash
sudo virsh net-edit vlan20-backend
# changer <forward mode='nat'/> en <forward mode='route'/>
```

## Sécurité

### SSH

Port 22 fermé, seulement 2222 avec clés :
```bash
# generation des cles
ssh-keygen -t ed25519 -f ~/.ssh/bastion_key

# copie sur le serveur
ssh-copy-id -i ~/.ssh/bastion_key.pub admelmoh@192.168.99.254

# config dans /etc/ssh/sshd_config
Port 2222
PasswordAuthentication no
PermitRootLogin no
```

### Fail2ban

Configuré pour bloquer après 3 tentatives ratées :
```ini
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 600
findtime = 300
```

J'ai testé en faisant exprès des mauvais mots de passe et effectivement après 3 essais l'IP est bannie (connection refused).

### Firewall

Règles iptables sur le bastion :
```bash
# politique par defaut : bloquer
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# autoriser ssh sur 2222
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT

# routage entre vlans
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -s 192.168.10.0/24 -d 192.168.20.0/24 -p tcp --dport 3000 -j ACCEPT
iptables -A FORWARD -s 192.168.20.0/24 -d 192.168.30.0/24 -p tcp --dport 5432 -j ACCEPT
```

## Liens utiles

- [Libvirt networking](https://wiki.libvirt.org/page/VirtualNetworking)
- [KVM networking modes](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-virtual_networking-network_configuration_with_virsh)
- [Iptables routing](https://www.karlrupp.net/en/computer/nat_tutorial)
- [Fail2ban config](https://www.fail2ban.org/wiki/index.php/Configuration)
- [PostgreSQL authentication](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)

## Reproductibilité

Pour recréer ce lab, suivre le guide d'installation complet : [docs/installation.md](docs/installation.md)

## Notes

- Les VMs utilisent ~40GB d'espace disque
- 8GB de RAM minimum (2GB par VM)
- Testé sur Fedora 42 avec KVM

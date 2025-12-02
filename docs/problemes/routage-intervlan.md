# Problème : Routage inter-VLAN

## Contexte

Lors de la mise en place de la segmentation réseau avec 4 VLANs, les VMs n'arrivaient pas à communiquer entre elles. Par exemple, la VM App (vlan20) ne pouvait pas joindre la VM Database (vlan30).

## Symptômes
```bash
# Depuis App
ping 192.168.30.10
# Résultat : Destination Host Unreachable
# ou parfois : Destination Port Unreachable

# Test PostgreSQL
psql -h 192.168.30.10 -U labuser -d labdb
# Résultat : Connection refused
```

Les paquets n'arrivaient jamais à destination.

## Diagnostic

### Étape 1 : Vérification des routes sur les VMs
```bash
# Sur App
ip route show
# Résultat : pas de route vers 192.168.30.0/24
```

Les VMs ne savaient pas comment joindre les autres VLANs car elles n'avaient que la route par défaut vers leur propre gateway.

### Étape 2 : Vérification du forwarding sur l'hôte
```bash
# Sur Fedora
sysctl net.ipv4.ip_forward
# Résultat : 0 (désactivé)
```

L'hôte Fedora ne forwardait pas les paquets entre bridges.

### Étape 3 : Test avec tcpdump
```bash
# Sur Database
sudo tcpdump -i enp1s0 port 5432
# Lancer connexion depuis App
# Résultat : aucun paquet reçu
```

Les paquets n'arrivaient même pas à la VM de destination.

## Tentatives de solution

### Tentative 1 : Mode route des réseaux libvirt (échec)

J'ai d'abord essayé de passer les réseaux virtuels en mode "route" au lieu de "nat" :
```xml
<network>
  <name>vlan20-backend</name>
  <forward mode='route'/>
  ...
</network>
```

Résultat : ça n'a pas résolu le problème. Les paquets étaient toujours bloqués.

### Tentative 2 : Bastion multi-interface comme routeur (échec)

J'ai ensuite essayé de configurer le bastion avec 4 interfaces (une dans chaque VLAN) pour qu'il agisse comme routeur :
```bash
# Ajouter 3 interfaces au bastion
sudo virsh attach-interface bastion network vlan10-dmz --model virtio --config
sudo virsh attach-interface bastion network vlan20-backend --model virtio --config
sudo virsh attach-interface bastion network vlan30-data --model virtio --config
```

Configuration sur le bastion :
- enp1s0 : 192.168.99.10 (management)
- enp7s0 : 192.168.10.1 (dmz)
- enp8s0 : 192.168.20.1 (backend)
- enp9s0 : 192.168.30.1 (data)

Activation du forwarding et configuration iptables sur le bastion.

Résultat : ça n'a pas marché non plus. Problème découvert : conflit d'adresses IP et MAC entre le bastion et les bridges KVM qui avaient aussi les IPs .1 de chaque VLAN. Les VMs voyaient deux entités répondre à la même adresse.

## Solution finale

Garder l'architecture simple : les bridges KVM gèrent le routage, pas le bastion.

### Architecture finale
```
App (192.168.20.10)
    ↓
Bridge virbr-nd (192.168.20.1) 
    ↓
[Routage sur hôte Fedora via iptables]
    ↓
Bridge virbr-ta (192.168.30.1)
    ↓
Database (192.168.30.10)
```

Le bastion garde UNE SEULE interface (vlan99-management) et ne fait que le filtrage firewall.

### Configuration appliquée

#### 1. Sur l'hôte Fedora
```bash
# Activer le forwarding IP
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Désactiver reverse path filtering (important)
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

# Sauvegarder
sudo iptables-save | sudo tee /etc/sysconfig/iptables
```

#### 2. Ajouter les routes sur chaque VM

Chaque VM doit savoir comment joindre les autres VLANs via sa gateway locale.

Exemple pour App (vlan20) :
```bash
# Routes vers les autres VLANs
sudo ip route add 192.168.99.0/24 via 192.168.20.1
sudo ip route add 192.168.10.0/24 via 192.168.20.1
sudo ip route add 192.168.30.0/24 via 192.168.20.1
```

Pour rendre permanent, ajouter dans netplan :
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

Répéter pour toutes les VMs avec leurs propres IPs et gateways.

#### 3. Simplifier le bastion

Enlever les interfaces supplémentaires du bastion :
```bash
# Arrêter le bastion
sudo virsh shutdown bastion

# Détacher les 3 interfaces supplémentaires
sudo virsh detach-interface bastion network --config --mac 52:54:00:85:61:4f
sudo virsh detach-interface bastion network --config --mac 52:54:00:97:cc:1e
sudo virsh detach-interface bastion network --config --mac 52:54:00:d6:12:5d

# Redémarrer
sudo virsh start bastion

# Vérifier : doit avoir qu'une seule interface
sudo virsh domiflist bastion
```

## Vérification
```bash
# Depuis App
ping -c 3 192.168.30.10
# OK

# Test PostgreSQL
psql -h 192.168.30.10 -U labuser -d labdb -c "SELECT * FROM users;"
# OK

# Depuis Web
ping -c 3 192.168.20.10
# OK
```

## Pourquoi ça marche maintenant ?

1. **Pas de conflit d'adresses** : seuls les bridges KVM ont les IPs .1, pas le bastion
2. **Forwarding activé** : l'hôte Fedora forward les paquets entre bridges
3. **rp_filter désactivé** : permet les réponses qui ne reviennent pas par la même interface
4. **NAT masquerading** : les paquets sont "traduits" pour que les réponses reviennent correctement
5. **Routes sur les VMs** : chaque VM sait comment joindre les autres VLANs

## Leçons apprises

- Ne pas essayer de dupliquer les fonctionnalités natives de l'hyperviseur
- Utiliser les bridges KVM pour le routage, le bastion pour le filtrage
- Toujours vérifier les conflits d'adresses IP/MAC
- Le reverse path filtering peut bloquer silencieusement le routage asymétrique
- Documenter tous les tests et échecs pour comprendre ce qui marche vraiment


## ressources

- https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt
- https://access.redhat.com/solutions/53031

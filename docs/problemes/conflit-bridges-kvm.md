# Problème : Conflit d'adresses entre bridges KVM et bastion

## Contexte

Après avoir configuré le bastion avec 4 interfaces pour qu'il agisse comme routeur entre VLANs, les VMs n'arrivaient toujours pas à communiquer. Le diagnostic montrait que les paquets partaient bien des VMs mais n'arrivaient jamais à destination.

## Symptômes
```bash
# Sur App
ping 192.168.30.10
# Résultat : Destination Port Unreachable from 192.168.20.1

# Test avec tcpdump sur App
sudo tcpdump -i enp1s0 icmp
# On voit les paquets PARTIR de App
# On voit une réponse "unreachable" venant du gateway

# Test avec tcpdump sur Database
sudo tcpdump -i enp1s0 icmp
# Aucun paquet reçu (les paquets n'arrivent jamais)
```

Les paquets partaient mais n'arrivaient pas. Le gateway (192.168.20.1) répondait "unreachable" immédiatement.

## Diagnostic

### Étape 1 : Vérifier qui répond au gateway
```bash
# Sur App
arp -n
# Résultat :
# 192.168.20.1    ether   52:54:00:5b:5f:78   C    enp1s0
```

La MAC address du gateway était 52:54:00:5b:5f:78.

### Étape 2 : Vérifier les interfaces du bastion
```bash
# Sur Fedora
sudo virsh domiflist bastion
# Résultat :
# Interface   Source           MAC
# vnet11      vlan99-management  52:54:00:eb:8f:35
# vnet12      vlan10-dmz         52:54:00:85:61:4f
# vnet13      vlan20-backend     52:54:00:97:cc:1e  <- Interface backend du bastion
# vnet14      vlan30-data        52:54:00:d6:12:5d
```

L'interface enp8s0 du bastion (vlan20-backend) avait la MAC 52:54:00:97:cc:1e.

### Étape 3 : Vérifier les bridges KVM
```bash
# Sur Fedora
ip link show virbr-nd
# Résultat :
# virbr-nd: ... link/ether 52:54:00:5b:5f:78 ...

ip addr show virbr-nd
# Résultat :
# inet 192.168.20.1/24 ...
```

Découverte du problème : le bridge KVM virbr-nd avait aussi l'IP 192.168.20.1 et la MAC 52:54:00:5b:5f:78.

## Le problème

Il y avait DEUX entités avec l'adresse 192.168.20.1 :

1. **Bridge KVM virbr-nd** : MAC 52:54:00:5b:5f:78
2. **Bastion enp8s0** : MAC 52:54:00:97:cc:1e

Quand App envoyait un paquet vers 192.168.30.10, voici ce qui se passait :
```
App envoie ARP request : "Qui a 192.168.20.1 ?"
→ Bridge virbr-nd répond : "C'est moi, MAC 52:54:00:5b:5f:78"
→ App met cette MAC dans son cache ARP
→ App envoie les paquets IP à cette MAC
→ Le bridge KVM reçoit les paquets mais ne sait pas quoi en faire
→ Il répond "Destination unreachable"
→ Les paquets n'arrivent jamais au bastion ni à Database
```

## Vérification du conflit

### Test 1 : Forcer la bonne MAC dans le cache ARP
```bash
# Sur App
sudo arp -s 192.168.20.1 52:54:00:97:cc:1e  # MAC du bastion
```

Cette commande a bloqué le terminal car elle créait une entrée ARP statique incorrecte qui cassait complètement la connectivité.

### Test 2 : Supprimer l'IP du bridge
```bash
# Sur Fedora
sudo ip addr flush dev virbr-nd
```

Après cette commande, la connectivité SSH vers App a été coupée car le bridge n'avait plus d'IP pour gérer le réseau.

### Test 3 : Supprimer les interfaces du bastion
```bash
# Enlever les 3 interfaces supplémentaires du bastion
sudo virsh shutdown bastion
sudo virsh detach-interface bastion network --config --mac 52:54:00:85:61:4f
sudo virsh detach-interface bastion network --config --mac 52:54:00:97:cc:1e
sudo virsh detach-interface bastion network --config --mac 52:54:00:d6:12:5d
sudo virsh start bastion
```

Après cette modification, le conflit a disparu. Le bridge virbr-nd était le seul à avoir l'IP 192.168.20.1.

## Solution finale

Laisser les bridges KVM gérer les adresses .1 de chaque VLAN et ne PAS donner ces adresses au bastion.

Architecture finale :
- Bridges KVM : 192.168.X.1 (gateways)
- Bastion : 192.168.99.10 uniquement (une seule interface)
- Routage géré par l'hôte Fedora via iptables

## Pourquoi cette architecture fonctionne

1. **Pas de conflit d'adresses** : une seule entité par IP
2. **Les bridges KVM gèrent naturellement leur réseau** : c'est leur rôle
3. **Le bastion se concentre sur le filtrage** : pas besoin qu'il route
4. **L'hôte Fedora connecte les bridges** : via iptables MASQUERADE

## Comment éviter ce problème

1. **Ne jamais dupliquer les IPs** : si les bridges KVM ont les .1, ne pas les donner aussi aux VMs
2. **Vérifier avec arp -n** : toujours vérifier quelle MAC répond pour une IP donnée
3. **Utiliser tcpdump** : capturer sur les deux extrémités pour voir où les paquets sont perdus
4. **Garder l'architecture simple** : utiliser les fonctionnalités natives de l'hyperviseur plutôt que de tout recréer manuellement
5. **Documenter les tentatives échouées** : pour comprendre pourquoi certaines approches ne marchent pas

## Commandes utiles pour le diagnostic
```bash
# Voir qui répond à une IP
arp -n

# Vider le cache ARP
sudo ip neigh flush dev enp1s0

# Voir les MACs des interfaces
ip link show

# Voir les IPs des bridges
ip addr show | grep virbr

# Capturer le trafic réseau
sudo tcpdump -i any -n "host 192.168.20.10 and host 192.168.30.10"

# Voir les interfaces d'une VM
sudo virsh domiflist <vm-name>

# Vérifier les réseaux virtuels
sudo virsh net-list --all
sudo virsh net-info <network-name>
```

## Leçons apprises

- Les bridges KVM sont déjà configurés pour gérer le routage basique
- Ajouter une couche de routage supplémentaire (bastion multi-interface) crée plus de problèmes qu'elle n'en résout
- Les conflits d'adresses MAC/IP sont difficiles à diagnostiquer car les symptômes sont trompeurs
- Le cache ARP peut masquer des problèmes de configuration réseau
- Toujours vérifier TOUS les composants qui peuvent répondre à une adresse IP donnée

## Références

- [Linux ARP](https://linux.die.net/man/8/arp)
- [tcpdump man page](https://www.tcpdump.org/manpages/tcpdump.1.html)
- [KVM networking](https://wiki.libvirt.org/page/Networking)
- [Understanding Linux Bridge](https://developers.redhat.com/articles/2022/04/06/introduction-linux-bridging-commands-and-features)

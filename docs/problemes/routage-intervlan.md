# probleme : routage inter-vlan ne fonctionnait pas

## symptomes
```bash
admelmoh@app:~$ ping 192.168.30.10
From 192.168.20.1 icmp_seq=1 Destination Port Unreachable
```

les paquets arrivaient au bastion mais n'etaient pas routés vers le vlan de destination.

## cause

plusieurs trucs manquaient :

1. **ip forwarding pas activé**
```bash
   cat /proc/sys/net/ipv4/ip_forward
   # retournait 0
```

2. **reverse path filtering bloquait les paquets**
```bash
   sysctl net.ipv4.conf.all.rp_filter
   # retournait 1 ou 2
```

3. **mode nat au lieu de route dans libvirt**
```xml
   <forward mode='nat'/>
   <!-- au lieu de -->
   <forward mode='route'/>
```

## solution
```bash
# 1. activer ip forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# 2. desactiver rp_filter
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0

# 3. passer les reseaux en mode route
sudo virsh net-edit vlan20-backend
# modifier <forward mode='route'/>
sudo virsh net-destroy vlan20-backend
sudo virsh net-start vlan20-backend
```

## verification
```bash
# test ping
ping 192.168.30.10

# verifier le routage
ip route get 192.168.30.10
# doit montrer via 192.168.20.254

# traceroute
traceroute 192.168.30.10
# doit passer par 192.168.20.254 puis 192.168.30.254
```

## ressources

- https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt
- https://access.redhat.com/solutions/53031

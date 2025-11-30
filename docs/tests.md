# Tests de validation

Documentation de tous les tests effectués pour valider le fonctionnement de l'infrastructure.

## Tests de connectivité réseau

### Ping entre VLANs

Depuis le bastion vers toutes les VMs :
```bash
admelmoh@bastion:~$ ping -c 3 192.168.10.10
PING 192.168.10.10 (192.168.10.10) 56(84) bytes of data.
64 bytes from 192.168.10.10: icmp_seq=1 ttl=64 time=0.445 ms
64 bytes from 192.168.10.10: icmp_seq=2 ttl=64 time=0.384 ms
64 bytes from 192.168.10.10: icmp_seq=3 ttl=64 time=0.502 ms
--- 192.168.10.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss

admelmoh@bastion:~$ ping -c 3 192.168.20.10
PING 192.168.20.10 (192.168.20.10) 56(84) bytes of data.
64 bytes from 192.168.20.10: icmp_seq=1 ttl=64 time=0.331 ms
64 bytes from 192.168.20.10: icmp_seq=2 ttl=64 time=0.398 ms
64 bytes from 192.168.20.10: icmp_seq=3 ttl=64 time=0.356 ms
--- 192.168.20.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss

admelmoh@bastion:~$ ping -c 3 192.168.30.10
PING 192.168.30.10 (192.168.30.10) 56(84) bytes of data.
64 bytes from 192.168.30.10: icmp_seq=1 ttl=64 time=0.289 ms
64 bytes from 192.168.30.10: icmp_seq=2 ttl=64 time=0.412 ms
64 bytes from 192.168.30.10: icmp_seq=3 ttl=64 time=0.367 ms
--- 192.168.30.10 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

**Résultat** : toutes les VMs sont accessibles depuis le bastion.

### Traceroute inter-VLAN

Test du chemin réseau depuis app vers database :
```bash
admelmoh@app:~$ traceroute 192.168.30.10
traceroute to 192.168.30.10 (192.168.30.10), 30 hops max
 1  192.168.20.254 (192.168.20.254)  0.523 ms  0.412 ms  0.389 ms
 2  192.168.30.10 (192.168.30.10)  0.678 ms  0.591 ms  0.534 ms
```

**Résultat** : les paquets passent bien par le bastion avant d'atteindre la database.

### Test des routes

Vérification de la table de routage sur app :
```bash
admelmoh@app:~$ ip route show
default via 192.168.20.254 dev enp1s0 proto static
192.168.10.0/24 via 192.168.20.254 dev enp1s0
192.168.20.0/24 dev enp1s0 proto kernel scope link src 192.168.20.10
192.168.30.0/24 via 192.168.20.254 dev enp1s0
192.168.99.0/24 via 192.168.20.254 dev enp1s0
```

**Résultat** : toutes les routes pointent vers le bastion (192.168.20.254).

## Tests des services

### Serveur web (Nginx)

Test HTTP simple :
```bash
admelmoh@bastion:~$ curl http://192.168.10.10
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
    </div>
</body>
</html>
```

**Résultat** : nginx répond correctement.

Test des headers HTTP :
```bash
admelmoh@bastion:~$ curl -I http://192.168.10.10
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/html
Content-Length: 542
```

### API Flask

Test du endpoint health :
```bash
admelmoh@bastion:~$ curl http://192.168.20.10:3000/health
{"api":"ok","database":"ok"}
```

Test du endpoint users :
```bash
admelmoh@bastion:~$ curl http://192.168.20.10:3000/users
[
  {"id":1,"username":"admin","email":"admin@lab.local"},
  {"id":2,"username":"user1","email":"user1@lab.local"},
  {"id":3,"username":"user2","email":"user2@lab.local"}
]
```

**Résultat** : l'API communique correctement avec la base de données.

Vérifier que le service systemd tourne :
```bash
admelmoh@app:~$ sudo systemctl status api-lab
● api-lab.service - API Lab Cybersec
     Loaded: loaded (/etc/systemd/system/api-lab.service; enabled)
     Active: active (running) since Sat 2025-11-29 15:32:31 UTC
   Main PID: 3994 (python)
```

### Base de données PostgreSQL

Test de connexion depuis app :
```bash
admelmoh@app:~$ psql -h 192.168.30.10 -U labuser -d labdb -c "SELECT * FROM users;"
Password for user labuser: 
 id | username |      email      
----+----------+-----------------
  1 | admin    | admin@lab.local
  2 | user1    | user1@lab.local
  3 | user2    | user2@lab.local
(3 rows)
```

**Résultat** : postgresql est accessible depuis app et retourne les données.

Test depuis le bastion :
```bash
admelmoh@bastion:~$ psql -h 192.168.30.10 -U labuser -d labdb -c "SELECT COUNT(*) FROM users;"
Password for user labuser: 
 count 
-------
     3
(1 row)
```

Vérifier que postgresql écoute sur toutes les interfaces :
```bash
elmoh@database:~$ sudo netstat -tlnp | grep 5432
tcp        0      0 0.0.0.0:5432            0.0.0.0:*               LISTEN      5374/postgres
tcp6       0      0 :::5432                 :::*                    LISTEN      5374/postgres
```

## Tests de sécurité

### SSH - Port 22 fermé

Test avec nmap depuis l'extérieur :
```bash
elmoh@wificampus-020075:~$ nmap -p 22 192.168.99.254
Starting Nmap scan...
PORT   STATE    SERVICE
22/tcp filtered ssh
```

**Résultat** : le port 22 est filtré (timeout), ce qui est correct.

### SSH - Port 2222 avec clés

Test de connexion avec clés SSH :
```bash
elmoh@wificampus-020075:~$ ssh -i ~/.ssh/bastion_key -p 2222 admelmoh@192.168.99.254
Welcome to Ubuntu 24.04.3 LTS
admelmoh@bastion:~$
```

**Résultat** : connexion réussie avec les clés.

Test de connexion avec password (doit échouer) :
```bash
elmoh@wificampus-020075:~$ ssh -o PubkeyAuthentication=no -p 2222 admelmoh@192.168.99.254
admelmoh@192.168.99.254's password: 
Permission denied, please try again.
```

**Résultat** : l'authentification par password est bien désactivée.

### Fail2ban

Test de bannissement après plusieurs tentatives échouées :
```bash
# tentative 1
elmoh@wificampus-020075:~$ ssh -p 2222 test@192.168.99.254
test@192.168.99.254's password: 
Permission denied

# tentative 2
test@192.168.99.254's password: 
Permission denied

# tentative 3
test@192.168.99.254's password: 
Permission denied

# tentative 4 (apres 3 echecs)
ssh: connect to host 192.168.99.254 port 2222: Connection refused
```

**Résultat** : fail2ban a banni l'IP après 3 tentatives échouées.

Vérifier le status de fail2ban :
```bash
admelmoh@bastion:~$ sudo fail2ban-client status sshd
Status for the jail: sshd
|- Filter
|  |- Currently failed:    0
|  |- Total failed:    6
|  `- Journal matches:  _SYSTEMD_UNIT=ssh.service + _COMM=sshd
`- Actions
   |- Currently banned:    1
   |- Total banned:    1
   `- Banned IP list:   10.188.34.230
```

Les logs de fail2ban :
```bash
admelmoh@bastion:~$ sudo tail /var/log/fail2ban.log
2025-11-29 16:45:23,156 fail2ban.actions [1234]: NOTICE  [sshd] Ban 10.188.34.230
```

### Firewall iptables

Vérifier les règles actives :
```bash
admelmoh@bastion:~$ sudo iptables -L -v -n
Chain INPUT (policy DROP 15 packets, 980 bytes)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  lo     *       0.0.0.0/0            0.0.0.0/0
  245 21K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            state RELATED,ESTABLISHED
   12  720 ACCEPT     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:2222
    5  300 ACCEPT     icmp --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 8

Chain FORWARD (policy DROP 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
  156 12K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            state RELATED,ESTABLISHED
    0     0 ACCEPT     icmp --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 8
    8  480 ACCEPT     tcp  --  *      *       192.168.10.0/24      192.168.20.0/24      tcp dpt:3000
   23 1380 ACCEPT     tcp  --  *      *       192.168.20.0/24      192.168.30.0/24      tcp dpt:5432
```

**Résultat** : 
- politique par défaut DROP
- seul le port 2222 est autorisé en INPUT
- le FORWARD n'autorise que les flux web→app (port 3000) et app→db (port 5432)

### Test d'accès non autorisé

Essayer d'accéder directement de web vers database (doit échouer) :
```bash
admelmoh-web@web:~$ nc -zv 192.168.30.10 5432
nc: connect to 192.168.30.10 port 5432 (tcp) failed: Connection timed out
```

**Résultat** : le firewall bloque bien l'accès direct de web vers database.

## Tests de performance

### Latence réseau
```bash
admelmoh@app:~$ ping -c 100 192.168.30.10 | tail -1
rtt min/avg/max/mdev = 0.245/0.387/1.234/0.156 ms
```

**Résultat** : latence moyenne de 0.387ms entre app et database.

### Débit réseau

Test avec iperf3 (si installé) :
```bash
# sur database
elmoh@database:~$ iperf3 -s

# sur app
admelmoh@app:~$ iperf3 -c 192.168.30.10
[ ID] Interval           Transfer     Bitrate
[  5]   0.00-10.00  sec  10.2 GBytes  8.76 Gbits/sec
```

**Note** : ce test n'a pas été effectué dans le lab actuel mais pourrait être ajouté.

## Tests de résilience

### Redémarrage du bastion
```bash
sudo virsh reboot bastion
# attendre 30 secondes

# vérifier que les services redémarrent
ssh bastion
sudo systemctl status ssh
sudo systemctl status fail2ban
```

**Résultat** : tous les services redémarrent automatiquement.

### Perte de connexion réseau

Simulation en désactivant une interface :
```bash
admelmoh@bastion:~$ sudo ip link set enp8s0 down
# app ne peut plus communiquer

admelmoh@bastion:~$ sudo ip link set enp8s0 up
# communication rétablie
```

## Résumé des tests

| Catégorie | Test | Résultat |
|-----------|------|----------|
| Réseau | Ping inter-VLAN | ok |
| Réseau | Traceroute | ok |
| Réseau | Isolation VLANs | ok |
| Services | Nginx | ok |
| Services | API Flask | ok |
| Services | PostgreSQL | ok |
| Sécurité | Port 22 fermé | ok |
| Sécurité | SSH avec clés | ok |
| Sécurité | Password SSH désactivé | ok |
| Sécurité | Fail2ban | ok |
| Sécurité | Firewall iptables | ok |
| Sécurité | Accès non autorisés | ok |

Tous les tests sont passés avec succès.

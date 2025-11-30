#!/bin/bash

# liste des vms et leurs configs
declare -A VMS=(
    ["bastion"]="192.168.99.148:192.168.99.10:192.168.99.1:admelmoh"
    ["web"]="192.168.10.134:192.168.10.10:192.168.10.1:admelmoh-web"
    ["app"]="192.168.20.133:192.168.20.10:192.168.20.1:admelmoh"
    ["database"]="192.168.30.110:192.168.30.10:192.168.30.1:elmoh"
)

for VM in "${!VMS[@]}"; do
    IFS=':' read -r CURRENT_IP STATIC_IP GATEWAY USER <<< "${VMS[$VM]}"
    
    echo "--- config $VM ---"
    echo "ip actuelle: $CURRENT_IP -> nouvelle ip: $STATIC_IP"
    
    # creer le fichier netplan
    NETPLAN_CONFIG="network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: no
      addresses:
        - ${STATIC_IP}/24
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4"
    
    # se connecter et configurer
    ssh -o PubkeyAuthentication=no -o StrictHostKeyChecking=no ${USER}@${CURRENT_IP} << SSHEOF
echo '${NETPLAN_CONFIG}' | sudo tee /etc/netplan/01-netcfg.yaml > /dev/null
sudo chmod 600 /etc/netplan/01-netcfg.yaml
sudo netplan apply
echo "ip configuree sur $VM"
SSHEOF
    
    echo "ok $VM est a $STATIC_IP"
    echo ""
    sleep 3
done

echo "attends 10 sec que tout se stabilise..."
sleep 10

echo ""
echo "=== test de connectivite ==="
ssh -o PubkeyAuthentication=no admelmoh@192.168.99.10 "hostname && ip addr show enp1s0 | grep 'inet '"
ssh -o PubkeyAuthentication=no admelmoh-web@192.168.10.10 "hostname && ip addr show enp1s0 | grep 'inet '"
ssh -o PubkeyAuthentication=no admelmoh@192.168.20.10 "hostname && ip addr show enp1s0 | grep 'inet '"
ssh -o PubkeyAuthentication=no elmoh@192.168.30.10 "hostname && ip addr show enp1s0 | grep 'inet '"

echo ""
echo "toutes les ips sont configurees !"

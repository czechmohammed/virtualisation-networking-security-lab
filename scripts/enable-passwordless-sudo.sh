#!/bin/bash

# connexions actuelles
declare -A VMS=(
    ["app"]="192.168.20.133:admelmoh"
    ["web"]="192.168.10.134:admelmoh-web"
    ["database"]="192.168.30.110:elmoh"
    ["bastion"]="192.168.99.148:admelmoh"
)

for VM in "${!VMS[@]}"; do
    IFS=':' read -r IP USER <<< "${VMS[$VM]}"
    
    echo "--- activation sudo sans password sur $VM ---"
    
    ssh -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -t ${USER}@${IP} \
        "echo '${USER} ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/${USER} > /dev/null && sudo chmod 440 /etc/sudoers.d/${USER} && echo 'ok pour $VM'"
    
    echo ""
done

echo "c'est bon, tu peux relancer setup-static-ips.sh maintenant"

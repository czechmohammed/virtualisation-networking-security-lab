#!/bin/bash

# Définir les VLANs
declare -A VLANS=(
    ["vlan99-management"]="192.168.99"
    ["vlan10-dmz"]="192.168.10"
    ["vlan20-backend"]="192.168.20"
    ["vlan30-data"]="192.168.30"
)

for VLAN_NAME in "${!VLANS[@]}"; do
    NETWORK="${VLANS[$VLAN_NAME]}"
    
    echo "=== Création de $VLAN_NAME ($NETWORK.0/24) ==="
    
    # Créer le fichier XML
    cat > /tmp/${VLAN_NAME}.xml << XMLEOF
<network>
  <name>${VLAN_NAME}</name>
  <forward mode='nat'/>
  <bridge name='virbr-${VLAN_NAME: -2}' stp='on' delay='0'/>
  <ip address='${NETWORK}.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='${NETWORK}.100' end='${NETWORK}.200'/>
    </dhcp>
  </ip>
</network>
XMLEOF
    
    # Définir, démarrer et rendre persistant
    sudo virsh net-define /tmp/${VLAN_NAME}.xml
    sudo virsh net-start ${VLAN_NAME}
    sudo virsh net-autostart ${VLAN_NAME}
    
    echo "✓ $VLAN_NAME créé"
    echo ""
done

echo "=== Tous les VLANs sont créés ! ==="
sudo virsh net-list --all

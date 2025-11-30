#!/bin/bash

# Définir les assignations VM -> VLAN
declare -A VM_VLANS=(
    ["bastion"]="vlan99-management"
    ["web"]="vlan10-dmz"
    ["app"]="vlan20-backend"
    ["database"]="vlan30-data"
)

for VM in "${!VM_VLANS[@]}"; do
    VLAN="${VM_VLANS[$VM]}"
    
    echo "=== Configuration de $VM vers $VLAN ==="
    
    # Arrêter la VM
    sudo virsh shutdown $VM
    sleep 5
    
    # Modifier l'interface réseau
    sudo virt-xml $VM --edit --network network=$VLAN
    
    # Redémarrer la VM
    sudo virsh start $VM
    
    echo "✓ $VM assignée à $VLAN"
    echo ""
done

echo "=== Toutes les VMs sont assignées ! ==="
echo "Attendre 30 secondes pour que les VMs démarrent..."
sleep 30

echo ""
echo "=== Nouvelles IPs des VMs (DHCP temporaire) ==="
for VLAN in vlan99-management vlan10-dmz vlan20-backend vlan30-data; do
    echo "--- $VLAN ---"
    sudo virsh net-dhcp-leases $VLAN
done

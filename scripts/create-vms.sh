#!/bin/bash

# Définir les VMs à créer
declare -A VMS=(
    ["vm2-web"]="10"
    ["vm3-app"]="10"
    ["vm4-database"]="12"
)

BASE_PATH="/run/media/elmoh/fedora/home/elmoh/cybersec-lab/vms"
ISO_PATH="/run/media/elmoh/fedora/home/elmoh/cybersec-lab/iso/ubuntu-24.04.3-live-server-amd64.iso"

for VM_NAME in "${!VMS[@]}"; do
    DISK_SIZE="${VMS[$VM_NAME]}"
    PRETTY_NAME="${VM_NAME#vm?-}"  # web, app, database
    
    echo "=== Création de $PRETTY_NAME (${DISK_SIZE}GB) ==="
    
    # Créer le disque
    qemu-img create -f qcow2 "${BASE_PATH}/${VM_NAME}/${PRETTY_NAME}.qcow2" ${DISK_SIZE}G
    
    # Permissions
    sudo chown elmoh:qemu "${BASE_PATH}/${VM_NAME}/${PRETTY_NAME}.qcow2"
    sudo chmod 775 "${BASE_PATH}/${VM_NAME}/${PRETTY_NAME}.qcow2"
    
    # Créer la VM
    sudo virt-install \
        --name "${PRETTY_NAME}" \
        --ram 2048 \
        --vcpus 1 \
        --disk path="${BASE_PATH}/${VM_NAME}/${PRETTY_NAME}.qcow2",format=qcow2 \
        --cdrom "${ISO_PATH}" \
        --os-variant ubuntu24.04 \
        --network network=default \
        --graphics vnc,listen=0.0.0.0 \
        --noautoconsole
    
    echo "✓ $PRETTY_NAME créée"
    echo ""
done

echo "=== Toutes les VMs sont créées ! ==="
echo "Liste des VMs :"
sudo virsh list --all

#!/bin/bash

VMS=("bastion" "web" "app" "database")

for VM in "${VMS[@]}"; do
    echo "=== Traitement de $VM ==="
    
    # Arrêter la VM
    sudo virsh destroy "$VM" 2>/dev/null
    
    # Éditer et supprimer le CDROM
    sudo virsh dumpxml "$VM" > /tmp/${VM}.xml
    
    # Supprimer les lignes du CDROM
    sed -i '/<disk type=.file. device=.cdrom.>/,/<\/disk>/d' /tmp/${VM}.xml
    
    # Réimporter la config
    sudo virsh define /tmp/${VM}.xml
    
    # Redémarrer la VM
    sudo virsh start "$VM"
    
    echo "✓ $VM: CDROM éjecté et VM redémarrée"
    echo ""
done

echo "=== Toutes les VMs sont prêtes ! ==="
sudo virsh list --all

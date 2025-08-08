Scripts to provision an Azure VM and to install and configure WireGuard.

Based on https://github.com/vijayshinva/AzureWireGuard and https://github.com/FuzzySecurity/AzureWireGuard

Usage:
- Create a private and public keypair for access to the VM using `ssh-keygen -t rsa -b 2048`
- Log into your Azure subscription
- Create a [Template Spec](https://portal.azure.com/#view/Microsoft_Azure_TemplateSpecs/TemplatesListBlade) using the [wireguard-arm-template.json](src/wireguard-arm-template.json) file
- Deploy the VM to the preferred resource group and region
- Enter your IP address from which to restrict SSH and WireGuard access to the VM
- Enter your public key generated to allow SSH access to the VM
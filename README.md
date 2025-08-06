Scripts to provision an Azure VM and to install and configure WireGuard.

Based on https://github.com/vijayshinva/AzureWireGuard and https://github.com/FuzzySecurity/AzureWireGuard

Usage:
- Create a private and public keypair for access to the VM using `ssh-keygen -t rsa -b 2048`
- Log into your Azure subscription
- Create a template using the [wireguard-arm-template.json](src/wireguard-arm-template.json) file and deploy the VM to the preferred regions
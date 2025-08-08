#!/bin/bash

apt-get update -y

# Configure unattended updates for security patches, etc
unattended-upgrades --verbose

# Install any pending updates
apt-get upgrade -y

## IP Forwarding
# Forward IPv4
sed -i -e 's/#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
# Forward IPv6
sed -i -e 's/#net.ipv6.conf.all.forwarding.*/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
# Reload Configuration
sysctl -p

# Install WireGuard
apt-get install wireguard -y

# Generate WireGuard Service Private and Public Keys
wg genkey | tee /home/wg/serverPrivateKey | wg pubkey > /home/wg/serverPublicKey

WG_CLIENT_PUBLIC_KEY=$(wg genkey | tee /home/wg/clientPrivateKey | wg pubkey)
WG_CLIENT_PRIVATE_KEY=$(</home/wg/clientPrivateKey)
WG_CLIENT_PRE_SHARED_KEY=$(wg genpsk)

WG_SERVER_PRIVATE_KEY=$(</home/wg/serverPrivateKey)
WG_SERVER_PUBLIC_KEY=$(</home/wg/serverPublicKey)
WG_SERVER_IP=$(curl ipinfo.io/ip)

# Put key material somewhere safe
mkdir /etc/wireguard/serverKeyMat
chmod -R 755 /etc/wireguard/serverKeyMat
chown -R root.root /etc/wireguard/serverKeyMat
mv /home/wg/serverPrivateKey /etc/wireguard/serverKeyMat/
mv /home/wg/serverPublicKey /etc/wireguard/serverKeyMat/
mv /home/wg/clientPrivateKey /etc/wireguard/serverKeyMat/

cat > /home/wg/wg0.conf << EOF
[Interface]
PrivateKey = ${WG_SERVER_PRIVATE_KEY}
Address = 10.9.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE
SaveConfig = true

[Peer]
PublicKey =  ${WG_CLIENT_PUBLIC_KEY}
PresharedKey = ${WG_CLIENT_PRE_SHARED_KEY}
AllowedIPs = 10.9.0.2/32
PersistentKeepalive = 15

EOF

mv /home/wg/wg0.conf /etc/wireguard/

## Firewall
ufw allow 51820/udp
ufw allow OpenSSH
ufw disable
ufw enable

## WireGuard Service
wg-quick up wg0
systemctl enable wg-quick@wg0

# Create client configuration
cat > /home/wg/client.conf << EOF
[Interface]
PrivateKey = ${WG_CLIENT_PRIVATE_KEY}
ListenPort = 51820
Address = 10.9.0.2/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = ${WG_SERVER_PUBLIC_KEY}
PresharedKey = ${WG_CLIENT_PRE_SHARED_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:51820
PersistentKeepalive = 15

EOF

## Display QR Code
apt-get install qrencode -y
qrencode -t ansiutf8 < /home/wg/client.conf

# Clean up apt packages, etc
apt-get autoremove -y
apt-get clean
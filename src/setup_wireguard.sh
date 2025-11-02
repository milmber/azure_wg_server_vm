#!/bin/bash
set -e

# Install WireGuard
apt-get install wireguard -y

# Ensure working user and dirs
mkdir -p /home/wg
chown -R wg:wg /home/wg || true

# Generate WireGuard Service Private and Public Keys
wg genkey | tee /home/wg/serverPrivateKey | wg pubkey > /home/wg/serverPublicKey

WG_SERVER_PRIVATE_KEY=$(</home/wg/serverPrivateKey)
WG_SERVER_PUBLIC_KEY=$(</home/wg/serverPublicKey)
WG_SERVER_IP=$(curl -s ipinfo.io/ip)

# Prepare key storage
mkdir -p /etc/wireguard/serverKeyMat
chmod -R 755 /etc/wireguard/serverKeyMat
chown -R root:root /etc/wireguard/serverKeyMat

# Define clients (name:address)
clients=("mobile:10.9.0.2" "tablet:10.9.0.3" "computer:10.9.0.4")

# Generate keys and preshared keys for each client, store metadata
for entry in "${clients[@]}"; do
  name="${entry%%:*}"
  addr="${entry##*:}"

  # Private, public, and psk paths in /home/wg first
  priv="/home/wg/client_${name}_private"
  pub="/home/wg/client_${name}_public"
  psk="/home/wg/client_${name}_psk"

  wg genkey | tee "${priv}" | wg pubkey > "${pub}"
  wg genpsk > "${psk}"

  # move private and public keys (keep psk too)
  mv "${priv}" /etc/wireguard/serverKeyMat/client_${name}_private
  mv "${pub}" /etc/wireguard/serverKeyMat/client_${name}_public
  mv "${psk}" /etc/wireguard/serverKeyMat/client_${name}_psk

  chmod 600 /etc/wireguard/serverKeyMat/client_${name}_private
  chmod 600 /etc/wireguard/serverKeyMat/client_${name}_psk
done

# Build server config with multiple peers
cat > /home/wg/wg0.conf << 'EOF'
[Interface]
PrivateKey = __SERVER_PRIV__
Address = 10.9.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE
SaveConfig = true

EOF

# Inject server private key into config
sed -i "s|__SERVER_PRIV__|${WG_SERVER_PRIVATE_KEY}|" /home/wg/wg0.conf

# Append peers for each client
for entry in "${clients[@]}"; do
  name="${entry%%:*}"
  addr="${entry##*:}"

  client_pub="/etc/wireguard/serverKeyMat/client_${name}_public"
  client_psk="/etc/wireguard/serverKeyMat/client_${name}_psk"

  cat >> /home/wg/wg0.conf << EOF
[Peer]
PublicKey = $(cat "${client_pub}")
PresharedKey = $(cat "${client_psk}")
AllowedIPs = ${addr}/32
PersistentKeepalive = 15

EOF
done

# Move final server config into place
mv /home/wg/wg0.conf /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf
chown root:root /etc/wireguard/wg0.conf

## Firewall
ufw allow 51820/udp
ufw allow OpenSSH
ufw disable || true
ufw --force enable

## WireGuard Service
wg-quick up wg0 || true
systemctl enable wg-quick@wg0

# Create client configuration files
for entry in "${clients[@]}"; do
  name="${entry%%:*}"
  addr="${entry##*:}"

  client_priv="/etc/wireguard/serverKeyMat/client_${name}_private"
  client_pub="/etc/wireguard/serverKeyMat/client_${name}_public"
  client_psk="/etc/wireguard/serverKeyMat/client_${name}_psk"

  cat > /home/wg/client_${name}.conf << EOF
[Interface]
PrivateKey = $(cat "${client_priv}")
ListenPort = 51820
Address = ${addr}/32
DNS = 1.1.1.1
MTU = 1420

[Peer]
PublicKey = ${WG_SERVER_PUBLIC_KEY}
PresharedKey = $(cat "${client_psk}")
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:51820
PersistentKeepalive = 15

EOF

  chmod 600 /home/wg/client_${name}.conf
  chown wg:wg /home/wg/client_${name}.conf || true
done

# Optionally print paths of generated client configs
echo "Generated client configs:"
for entry in "${clients[@]}"; do
  name="${entry%%:*}"
  echo "/home/wg/client_${name}.conf"
done

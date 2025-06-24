#!/bin/bash
# Скрипт: установка VPN-сервера (WireGuard + V2Ray) с split-tunneling

# 1. Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
  echo "Ошибка: скрипт должен быть запущен от root (sudo)." >&2
  exit 1
fi

# 2. Переменные настройки (ЗАДАЙТЕ ниже свой адрес сервера!)
SERVER_HOST=""   # <- Замените на публичный IP или домен сервера
WG_PORT=51820                      # Порт WireGuard (UDP)
VPN_SUBNET="10.10.10.0/24"         # Подсеть VPN (IPv4)
SERVER_WG_IP="10.10.10.1/24"       # Адрес VPN-интерфейса сервера
CLIENT1_WG_IP="10.10.10.2/24"      # Адрес первого клиента (iPhone)
CLIENT2_WG_IP="10.10.10.3/24"      # Адрес второго клиента (OpenWRT)
CLIENT1_NAME="iPhone"
CLIENT2_NAME="OpenWRT"
SS_PORT=2345                       # Порт V2Ray (Shadowsocks)
SS_METHOD="chacha20-ietf-poly1305" # Метод шифрования Shadowsocks
SS_PASSWORD="$(openssl rand -hex 16)"  # Случайный пароль Shadowsocks (32_hex)

# 3. Установка необходимых пакетов
echo ">>> Обновление пакетов и установка WireGuard, Netdata, etc..."
apt-get update -y
apt-get install -y wireguard wireguard-tools curl wget gnupg2 net-tools iproute2 whois qrencode netdata

# 4. Установка V2Ray с помощью официального скрипта
echo ">>> Установка V2Ray (v2fly) через официальный скрипт..."
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)  #:contentReference[oaicite:0]{index=0}

# 5. Генерация ключей WireGuard (сервер и два клиента)
echo ">>> Генерация ключей WireGuard..."
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
CLIENT1_PRIV_KEY=$(wg genkey)
CLIENT1_PUB_KEY=$(echo "$CLIENT1_PRIV_KEY" | wg pubkey)
CLIENT2_PRIV_KEY=$(wg genkey)
CLIENT2_PUB_KEY=$(echo "$CLIENT2_PRIV_KEY" | wg pubkey)

# 6. Получение диапазонов IP для сервисов (Google, Instagram, YouTube, OpenAI)
echo ">>> Получение списков IP-адресов для целевых сервисов через whois (RADb)..."
AS_GOOGLE="AS15169"    # Google (включая YouTube)
AS_INSTAGRAM="AS32934" # Instagram (ASN Facebook/Meta)
AS_CLOUDFLARE="AS13335" # OpenAI (через Cloudflare CDN)
GOOGLE_NETS=$(whois -h whois.radb.net -- "-i origin $AS_GOOGLE"    | grep -w "route:" | awk '{print $2}')    #:contentReference[oaicite:1]{index=1}
INSTAGRAM_NETS=$(whois -h whois.radb.net -- "-i origin $AS_INSTAGRAM" | grep -w "route:" | awk '{print $2}')
CLOUDFLARE_NETS=$(whois -h whois.radb.net -- "-i origin $AS_CLOUDFLARE" | grep -w "route:" | awk '{print $2}')
# Объединяем все подсети в один список (через запятую) для AllowedIPs
ALL_NETS=$(printf "%s\n%s\n%s\n" "$GOOGLE_NETS" "$INSTAGRAM_NETS" "$CLOUDFLARE_NETS" | sort -u | tr '\n' ',' | sed 's/,$//')

# 7. Настройка Netdata для удалённого мониторинга (открытие доступа)
echo ">>> Настройка Netdata (разрешаем удалённый доступ)..."
sed -i 's/^\s*bind socket to IP = 127.0.0.1/bind socket to IP = 0.0.0.0/' /etc/netdata/netdata.conf  # Разрешаем слушать на всех интерфейсах:contentReference[oaicite:2]{index=2}
systemctl restart netdata

# 8. Создание конфигурации WireGuard сервера (файл /etc/wireguard/wg0.conf)
echo ">>> Создание конфигурационного файла WireGuard сервера..."
WG_CONF="/etc/wireguard/wg0.conf"
cat > "$WG_CONF" <<EOF
[Interface]
Address = $SERVER_WG_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV_KEY

# Включаем форвардинг IPv4
PostUp = sysctl -w net.ipv4.ip_forward=1
# Настраиваем NAT (MASQUERADE) для выхода трафика VPN-клиентов в интернет
PostUp = iptables -t nat -A POSTROUTING -o \$(ip -o -4 route show to default | awk '{print \$5}') -s $VPN_SUBNET -j MASQUERADE
# Разрешаем пересылку трафика через интерфейс WireGuard
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
# Удаляем правила при отключении интерфейса
PostDown = iptables -t nat -D POSTROUTING -o \$(ip -o -4 route show to default | awk '{print \$5}') -s $VPN_SUBNET -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

# Клиент 1: $CLIENT1_NAME
[Peer]
PublicKey = $CLIENT1_PUB_KEY
AllowedIPs = ${CLIENT1_WG_IP%/*}/32

# Клиент 2: $CLIENT2_NAME
[Peer]
PublicKey = $CLIENT2_PUB_KEY
AllowedIPs = ${CLIENT2_WG_IP%/*}/32
EOF

chmod 600 "$WG_CONF"  # защита файла конфигурации

# 9. Запуск WireGuard и добавление в автозагрузку
echo ">>> Активируем и запускаем сервис WireGuard (wg0)..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 10. Создание конфигурации V2Ray (Shadowsocks-inbound для proxy)
echo ">>> Настройка V2Ray (режим Shadowsocks, порт $SS_PORT)..."
V2RAY_CONF="/usr/local/etc/v2ray/config.json"
cat > "$V2RAY_CONF" <<EOF
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
      },
      "tag": "ss-inbound"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    }
  ]
}
EOF

# 11. Запуск V2Ray и добавление в автозагрузку
echo ">>> Включаем и перезапускаем сервис V2Ray..."
systemctl enable v2ray
systemctl restart v2ray

# 12. Открываем необходимые порты в фаерволе (UFW), если активен
if systemctl is-active --quiet ufw; then
  echo ">>> Настройка брандмауэра UFW: разрешаем порты $WG_PORT/UDP, $SS_PORT/TCP/UDP, 19999/TCP..."
  ufw allow "$WG_PORT"/udp
  ufw allow "$SS_PORT"/tcp
  ufw allow "$SS_PORT"/udp
  ufw allow 19999/tcp
fi

# 13. Создание конфигурационных файлов для клиентов (iPhone и OpenWRT)
echo ">>> Генерация клиентских конфигураций WireGuard..."
CLIENT1_CONF="./wg-client-${CLIENT1_NAME}.conf"
CLIENT2_CONF="./wg-client-${CLIENT2_NAME}.conf"
cat > "$CLIENT1_CONF" <<EOF
[Interface]
Address = $CLIENT1_WG_IP
PrivateKey = $CLIENT1_PRIV_KEY
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_HOST:$WG_PORT
AllowedIPs = $ALL_NETS
EOF

cat > "$CLIENT2_CONF" <<EOF
[Interface]
Address = $CLIENT2_WG_IP
PrivateKey = $CLIENT2_PRIV_KEY
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_HOST:$WG_PORT
AllowedIPs = $ALL_NETS
EOF

# 14. Вывод QR-кода для конфигурации iPhone (удобно отсканировать камерой)
echo ">>> QR-код для конфигурации iPhone (сканируйте через приложение WireGuard):"
qrencode -t ansiutf8 < "$CLIENT1_CONF"

# 15. Вывод итоговой информации для пользователя
echo "======================================================================"
echo "Настройка завершена! Важные сведения:"
echo "- Конфигурация сервера WireGuard: $WG_CONF"
echo "- Клиентские конфиги: $CLIENT1_CONF (iPhone), $CLIENT2_CONF (OpenWRT)"
echo "- WireGuard-сервер запущен и готов. Подставьте $SERVER_HOST в клиентские .conf."
echo "- Для подключения Shadowsocks (через V2Ray):"
echo "    Сервер: $SERVER_HOST,  порт: $SS_PORT,  шифрование: $SS_METHOD,"
echo "    пароль: $SS_PASSWORD"
echo "- Мониторинг: Netdata запущен (http://$SERVER_HOST:19999)."
echo ""
echo "Команды управления VPN:"
echo "    systemctl status wg-quick@wg0    # статус WireGuard"
echo "    systemctl restart wg-quick@wg0   # перезапуск WireGuard"
echo "    wg show wg0                      # просмотр пиров WireGuard"
echo "    journalctl -u v2ray --follow     # просмотр логов V2Ray"
echo "    systemctl restart v2ray          # перезапуск V2Ray"
echo "======================================================================"

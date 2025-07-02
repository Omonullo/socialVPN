Для того чтобы соединиться к хосту введите 

> ssh omonako@95.182.117.114

Пароль будет представлен отдельно (спросите у администратора)


Как только получите доступ к серверу, идите в раздел

> ~/work/socialVPN/


Оно хранит исходники и файлы-ключи конфигурации 


---

````markdown
# VPN Server Setup: WireGuard + V2Ray + Split-Tunneling

Этот сервер предоставляет безопасное VPN-подключение, направляя трафик только к нужным сервисам через туннель. Остальной интернет работает напрямую, без нагрузки на VPN.

## 📌 Общая информация

- **VPN тип**: WireGuard (UDP) + V2Ray (Shadowsocks)
- **Мониторинг**: Netdata (Web UI)
- **Split-Tunneling**: Трафик к Google, YouTube, Instagram, OpenAI направляется через VPN
- **Остальной трафик**: Работает напрямую
- **Сервер IP**: `95.182.117.114`

## 🔧 Установка (на Ubuntu сервере)

1. Скопируйте скрипт `setup_vpn.sh` на сервер.
2. Сделайте его исполняемым:

```bash
chmod +x setup_vpn.sh
````

3. Запустите от имени root:

```bash
sudo ./setup_vpn.sh
```

## 📱 Клиенты WireGuard

### iPhone

* Установите приложение [WireGuard](https://apps.apple.com/us/app/wireguard/id1441195209)
* Отсканируйте QR-код, который появится в консоли

ИЛИ

* Импортируйте вручную конфигурацию из файла `wg-client-iPhone.conf`

### OpenWRT

* Установите пакеты:

```bash
opkg update
opkg install wireguard luci-proto-wireguard vpn-policy-routing
```

* Импортируйте содержимое файла `wg-client-OpenWRT.conf`

## 🧭 Split Tunneling

Только трафик к следующим сервисам идёт через VPN:

* Google (включая YouTube)
* Instagram
* OpenAI
* Cloudflare CDN

Остальной трафик идёт напрямую.

## 🌐 Shadowsocks (через V2Ray)

* **Server**: `95.182.117.114`
* **Port**: `2345`
* **Method**: `chacha20-ietf-poly1305`
* **Password**: будет выведен в консоли после установки

## 📊 Мониторинг

Netdata доступен по ссылке:

[http://95.182.117.114:19999](http://95.182.117.114:19999)

## 🔄 Команды управления VPN

```bash
# WireGuard
sudo systemctl status wg-quick@wg0
sudo systemctl restart wg-quick@wg0
sudo wg show wg0

# V2Ray (Shadowsocks)
sudo systemctl status v2ray
sudo systemctl restart v2ray
sudo journalctl -u v2ray --follow

# Netdata
sudo systemctl status netdata
```

## 📁 Файлы

| Файл                             | Описание                         |
| -------------------------------- | -------------------------------- |
| /etc/wireguard/wg0.conf          | Конфигурация сервера WireGuard   |
| wg-client-iPhone.conf            | Конфигурация клиента iPhone      |
| wg-client-OpenWRT.conf           | Конфигурация клиента OpenWRT     |
| /usr/local/etc/v2ray/config.json | Конфигурация Shadowsocks (V2Ray) |

## 🔐 Безопасность

* Ключи генерируются автоматически и не передаются третьим лицам
* Используются IP-диапазоны сервисов для split-tunnel
* Netdata открыт только для просмотра (без доступа к системе)


## Как добавлять новые адреса (на примере twitter)

Узнем ASN для twitter. Google скажет ASN 13414 </br>

Теперь создаём айпи файл 
>> whois -h whois.radb.net -- '-i origin ASN13414' | grep ^route | awk '{print $2}' > twitter.txt


открывем и редайтируем файл /home/omonako/work/addaddress.sh

Указываем путь нашего twitter.txt в конце вместо существующего адруса другого файла

должно получится вот так

>> while read ip; do   ip rule add to "$ip" table vpn; done < twitter.txt


сохраянем и запускаем файл

sudo /home/omonako/work/addaddress.sh


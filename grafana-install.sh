#!/bin/bash
set -e

echo "=== Установка системы мониторинга (cAdvisor + Node Exporter + VictoriaMetrics Agent) ==="

# Принудительно читаем ввод с клавиатуры через /dev/tty
read -p "Введите имя instance [Hetzner-GE]: " INSTANCE_NAME </dev/tty
INSTANCE_NAME="${INSTANCE_NAME:-Hetzner-GE}"

read -p "Введите IP или домен сервера VictoriaMetrics [0.0.0.0]: " VM_HOST </dev/tty
VM_HOST="${VM_HOST:-0.0.0.0}"

# Если ввели только IP/домен, формируем полный URL, иначе оставляем как есть
if [[ "$VM_HOST" =~ ^http ]]; then
    REMOTE_WRITE_URL="$VM_HOST"
else
    REMOTE_WRITE_URL="http://${VM_HOST}:8428/api/v1/write"
fi

echo ""
echo "Параметры установки:"
echo "  - Instance: $INSTANCE_NAME"
echo "  - Remote Write URL: $REMOTE_WRITE_URL"
echo ""

echo "[1/4] Остановка старых сервисов (если запущены) и скачивание компонентов..."
systemctl stop cadvisor nodeexporter vmagent 2>/dev/null || true

mkdir -p /opt/monitoring/{cadvisor,nodeexporter,vmagent/conf.d}
mkdir -p /var/lib/node_exporter/textfile_collector

# cAdvisor
cd /opt/monitoring/cadvisor
rm -f cadvisor
wget -q --show-progress -O cadvisor https://github.com/google/cadvisor/releases/download/v0.55.1/cadvisor-v0.55.1-linux-amd64
chmod +x cadvisor

# Node Exporter
cd /opt/monitoring/nodeexporter
rm -f node_exporter
wget -q --show-progress https://github.com/prometheus/node_exporter/releases/download/v1.12.1/node_exporter-1.12.1.linux-amd64.tar.gz
tar -xf node_exporter-1.12.1.linux-amd64.tar.gz
mv node_exporter-1.12.1.linux-amd64/node_exporter ./node_exporter
rm -rf node_exporter-1.12.1.linux-amd64*
chmod +x node_exporter

# VictoriaMetrics Agent
cd /opt/monitoring/vmagent
rm -f vmagent
wget -q --show-progress https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.153.0/vmutils-linux-amd64-v1.153.0.tar.gz
tar -xf vmutils-linux-amd64-v1.153.0.tar.gz
mv vmagent-prod vmagent
find . ! -name 'vmagent' ! -name 'conf.d' -type f -delete
rm -f *.tar.gz
chmod +x vmagent

echo "[2/4] Создание конфигурационных файлов..."
cat << 'EOF' > /opt/monitoring/vmagent/scrape.yml
scrape_config_files:
  - "/opt/monitoring/vmagent/conf.d/*.yml"

global:
  scrape_interval: 15s
EOF

cat << EOF > /opt/monitoring/vmagent/conf.d/cadvisor.yml
- job_name: integrations/cAdvisor
  scrape_interval: 15s
  static_configs:
    - targets: ['localhost:9101']
      labels:
        instance: "$INSTANCE_NAME"
EOF

cat << EOF > /opt/monitoring/vmagent/conf.d/nodeexporter.yml
- job_name: integrations/node_exporter
  scrape_interval: 15s
  static_configs:
    - targets: ['localhost:9100']
      labels:
        instance: "$INSTANCE_NAME"
EOF

echo "[3/4] Создание systemd сервисов..."
cat << 'EOF' > /etc/systemd/system/cadvisor.service
[Unit]
Description=cAdvisor
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
Type=simple
ExecStart=/opt/monitoring/cadvisor/cadvisor -listen_ip=127.0.0.1 -logtostderr -port=9101 -docker_only=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /etc/systemd/system/nodeexporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
Type=simple
ExecStart=/opt/monitoring/nodeexporter/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector --web.listen-address=127.0.0.1:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/vmagent.service
[Unit]
Description=VictoriaMetrics Agent
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
Type=simple
ExecStart=/opt/monitoring/vmagent/vmagent -httpListenAddr=127.0.0.1:8429 -promscrape.config=/opt/monitoring/vmagent/scrape.yml -promscrape.configCheckInterval=60s -remoteWrite.url=$REMOTE_WRITE_URL
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[4/4] Перезагрузка systemd, включение и запуск сервисов..."
systemctl daemon-reload
systemctl enable cadvisor nodeexporter vmagent
systemctl restart cadvisor nodeexporter vmagent

echo ""
echo "Установка успешно завершена! Статус сервисов:"
systemctl --no-pager status cadvisor nodeexporter vmagent | grep -E "Loaded:|Active:"

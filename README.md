# vmagent-node_exporter-vmetrik
Для установки мониторинга через Grafana и Victoria Metrics

Состав мониторинга: Grafana для дашбордов, Victoria Metrics для хранения метрик, Node Exporter и cAdvisor для сбора метрик серверов и контейнеров
## Установка одной командой

Запустите следующую команду под пользователем **root**:

```bash
curl -sSL https://raw.githubusercontent.com/VaZeR-nhk/vmagent-node_exporter-vmetrik/main/grafana-install.sh | bash

# ESP32-PoolMaster

Gestion automatique de piscine sur ESP32 : mesure du pH, de l'ORP et de la
pression, régulation par pompes doseuses ou électrolyseur au sel, filtration
programmée, robot, sécurités, écran tactile Nextion et intégration Home
Assistant.

Le firmware est une **configuration [ESPHome](https://esphome.io)** : voir
[`esphome/`](esphome/) et son [README](esphome/README.md) pour l'installation,
le découpage en paquets et la liste des entités.

```bash
cd esphome
cp secrets.yaml.example secrets.yaml   # puis renseigner WiFi, clé API, OTA
esphome run poolmaster.yaml            # premier flash par USB, ensuite OTA
```

## Contenu du dépôt

| Dossier / fichier | Rôle |
|---|---|
| `esphome/` | Le firmware : configuration ESPHome découpée en paquets |
| `Nextion/` | Interface de l'écran tactile : source `.HMI` + ressources graphiques |
| `Nextion/tft/` | Firmwares d'écran compilés, à copier sur carte SD pour flasher le Nextion |
| `BOM*`, `PickAndPlace*` | Nomenclature et fichiers de placement des cartes |
| `Gerber*.zip` | Fichiers de fabrication des PCB |
| `CAD_files*.zip` | Modèles mécaniques (boîtier, supports) |
| `PoolMaster*.PDF` | Schémas électroniques |

## Matériel

Carte PoolMaster à base d'ESP32 DevKit v1 :

| Élément | Broche / adresse |
|---|---|
| Pompe filtration | GPIO32 |
| Pompe robot | GPIO33 |
| Pompe pH (acide) | GPIO25 |
| Pompe Chlore | GPIO26 |
| Relais R0 (projecteur) | GPIO27 |
| Relais R1 | GPIO4 |
| Électrolyseur (SWG) | GPIO13 |
| Pompe remplissage | GPIO23 |
| Buzzer | GPIO2 |
| Contacts de niveau (Chlore / pH / piscine) | GPIO39 / GPIO36 / GPIO34 |
| OneWire air / eau (DS18B20) | GPIO18 / GPIO19 |
| Écran Nextion (UART) | TX GPIO17 / RX GPIO16 |
| ADS1115 (ORP=A0, pH=A1, PSI=A2) | I2C 0x48 (SDA 21 / SCL 22) |
| PCF8574 (8 LEDs de statut) | I2C 0x20 |

## Historique

Ce dépôt hébergeait auparavant un firmware PlatformIO/Arduino, remplacé par la
configuration ESPHome. Le code d'origine reste consultable dans l'historique
git — le dernier commit à le contenir est référencé dans le message de commit
de sa suppression.

Le portage conserve la logique métier (régulation PID fenêtrée, calcul
quotidien de la durée de filtration, sécurités, écran Nextion) et remplace
l'API MQTT JSON `Home/Pool/` par les entités natives ESPHome ; la
correspondance est détaillée dans [`esphome/README.md`](esphome/README.md).

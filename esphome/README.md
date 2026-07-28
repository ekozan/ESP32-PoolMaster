# PoolMaster — Version ESPHome

Réécriture du firmware ESP32-PoolMaster (PlatformIO/Arduino) sous forme d'une
configuration [ESPHome](https://esphome.io). Elle cible **le même matériel**
(carte PoolMaster avec ESP32 DevKit v1) et reprend la logique métier du
firmware d'origine.

## Installation

```bash
# 1. Installer ESPHome (>= 2024.6)
pip install esphome

# 2. Créer le fichier de secrets
cd esphome
cp secrets.yaml.example secrets.yaml
# ... éditer secrets.yaml avec vos identifiants WiFi, clé API, etc.

# 3. Compiler et flasher (première fois par USB)
esphome run poolmaster.yaml

# Les mises à jour suivantes se font en OTA automatiquement.
```

Dans Home Assistant, l'appareil est détecté automatiquement via l'API native
ESPHome (intégration « ESPHome »). Toutes les entités (mesures, pompes, modes,
réglages) apparaissent sans configuration supplémentaire.

## Matériel pris en charge

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
| Contact bac Chlore | GPIO39 (ouvert = niveau bas) |
| Contact bac pH | GPIO36 (ouvert = niveau bas) |
| Contact niveau piscine | GPIO34 (ouvert = niveau bas) |
| OneWire air (DS18B20) | GPIO18 |
| OneWire eau (DS18B20) | GPIO19 |
| ADS1115 (ORP=A0, pH=A1, PSI=A2) | I2C 0x48 (SDA 21 / SCL 22) |
| PCF8574 (8 LEDs de statut) | I2C 0x20 |

> La variante « Loulou74 » à deux ADS1115 en différentiel (0x48 + 0x49) n'est
> pas configurée par défaut ; il faut adapter les capteurs `ads1115` (deuxième
> hub à 0x49, multiplexeurs `A0_A1`/`A2_A3`).

## Logique portée

- **Mesures** : pH, ORP et pression avec calibration linéaire
  `valeur = tension(V) × C0 + C1` — les coefficients C0/C1 sont des entités
  `number` réglables depuis Home Assistant (mêmes valeurs par défaut que le
  firmware d'origine). Filtrage médian sur 11 échantillons comme l'origine.
- **Régulation pH/ORP** : PID fenêtré identique au principe d'origine
  (« PWM lent ») : à chaque fenêtre (60 min pH / 30 min ORP par défaut), la
  sortie PID donne une durée de dosage en ms exécutée en début de fenêtre.
  pH en sens REVERSE, ORP en sens DIRECT, dose minimale 30 s, sortie bornée à
  la fenêtre. Kp/Ki/Kd dans les **mêmes unités** que l'origine (Kp par défaut :
  2 700 000 pour le pH, 2 500 pour l'ORP ; Ki = Kd = 0 → boucle P pure).
- **Filtration automatique** : durée calculée chaque jour à 15h05 selon la
  température de l'eau (2 h / T°⁄3 / T°⁄2), fenêtre centrée sur 15 h et bornée
  par les heures min/max configurables.
- **Mode hiver / antigel** : marche forcée de la filtration si T° air < −2 °C,
  arrêt automatique interdit tant que T° air ≤ +2 °C ; régulations coupées en
  mode hiver ou si l'eau est sous le seuil bas.
- **Électrolyseur (mode régulé)** : marche si filtration active depuis plus du
  délai configuré, eau au-dessus de la température de sécurité et ORP sous la
  consigne. Jamais sans circulation d'eau.
- **Robot** : en mode auto, démarre N minutes après la filtration, tourne M
  minutes, une fois par jour.
- **Sécurités** :
  - surpression (arrêt général + erreur au-delà du seuil, mesuré après 2 min
    d'amorçage) ;
  - temps de marche quotidien maximal des pompes doseuses ;
  - verrouillage des doseuses et du SWG sur la filtration ;
  - arrêt du dosage si bac vide (contact de niveau).
  Les erreurs se réarment avec le bouton **« Acquitter les erreurs »**
  (équivalent de la commande `{"Clear":1}`).
- **Bacs** : estimation du niveau (%) à partir du débit de pompe et du temps de
  marche ; boutons « Bac rempli » pour remettre à 100 %.
- **LEDs de statut** (PCF8574, actives à l'état bas) : WiFi, filtration, mode
  auto, PID pH, PID ORP, bac bas, erreur, mode hiver. **Buzzer** en cas de
  défaut (désactivable).

## Correspondance avec l'API MQTT d'origine

L'API JSON `Home/Pool/` est remplacée par des entités natives :

| Commande d'origine | Entité ESPHome |
|---|---|
| `{"Mode":x}` | switch **Mode automatique** |
| `{"Winter":x}` | switch **Mode hiver** |
| `{"FiltPump":x}` | switch **Pompe filtration** |
| `{"PhPump":x}` / `{"ChlPump":x}` | switchs **Pompe pH / Chlore** |
| `{"pHAutoMode":x}` / `{"OrpAutoMode":x}` | switchs **Régulation pH/ORP auto** |
| `{"PhPID":x}` / `{"OrpPID":x}` | switchs **PID pH / PID ORP** |
| `{"ElectrolyseMode":x}` / `{"Electrolyse":x}` | switch **Mode électrolyseur** / **Électrolyseur** |
| `{"PhSetPoint":x}` / `{"OrpSetPoint":x}` | numbers **Consigne pH / ORP** |
| `{"WSetPoint":x}` / `{"WTempLow":x}` | numbers **Consigne / seuil température eau** |
| `{"PSIHigh":x}` | number **Seuil surpression** |
| `{"PhPIDParams":…}` / `{"OrpPIDParams":…}` | numbers **Kp/Ki/Kd** |
| `{"PhPIDWSize":x}` / `{"OrpPIDWSize":x}` | numbers **Fenêtre PID** (en minutes) |
| `{"FiltT0":x}` / `{"FiltT1":x}` | numbers **Filtration heure min/max** |
| `{"DelayPID":x}` | number **Délai démarrage PID** |
| `{"PumpsMaxUp":x}` | number **Marche max quotidienne** (en minutes) |
| `{"pHTank":…}` / `{"ChlTank":…}` | numbers **Volume bac** + boutons **Bac rempli** |
| `{"pHPumpFR":x}` / `{"ChlPumpFR":x}` | numbers **Débit pompe** |
| `{"pHCalib":…}` / `{"OrpCalib":…}` / `{"RstpHCal":…}` | numbers **Calibration C0/C1** (saisir directement les coefficients de la régression) |
| `{"ElectroConfig":…}` | numbers **Électrolyseur température mini / délai** |
| `{"Clear":1}` | bouton **Acquitter les erreurs** |
| `{"Reboot":1}` | bouton **Redémarrer** |
| `{"Relay":[n,x]}` | switchs **Relais R0 / R1** |

Un bloc `mqtt:` optionnel (commenté dans le YAML) permet de publier en plus
vers un broker MQTT, avec les topics standard ESPHome.

## Non porté (volontairement)

- **Écran Nextion** : l'interface locale n'est pas portée (le HMI d'origine
  compte des dizaines de pages). ESPHome possède un composant
  [`nextion`](https://esphome.io/components/display/nextion.html) si vous
  souhaitez recréer une interface locale ; sinon l'interface de référence est
  Home Assistant (+ le serveur web embarqué sur le port 80).
- **API MQTT JSON historique** (`Home/Pool/Meas1`, `Set1`… et bitmaps `IO`) :
  remplacée par les entités natives ci-dessus. Les dashboards
  HomeAssistant/NodeRed existants basés sur ces topics doivent être adaptés.
- **Notifications SMTP** : à réaliser côté Home Assistant (automatisations sur
  les entités `binary_sensor` d'erreur).
- **Calibration multi-points embarquée** : la régression linéaire se calcule
  hors ligne (tableur) et les coefficients C0/C1 se saisissent directement.
- **Historique 12 h embarqué** : l'historisation est assurée par Home
  Assistant/InfluxDB.

## Notes de sécurité

- Toutes les pompes doseuses redémarrent **arrêtées** après un reboot
  (`restore_mode: ALWAYS_OFF`).
- La régulation ne fonctionne que si la pompe de filtration tourne, comme dans
  le firmware d'origine.
- Vérifiez le sens de vos contacts de niveau : la configuration suppose
  « contact ouvert = niveau bas » avec pull-up externe (broches 34/36/39 sans
  pull-up interne, conformément au PCB PoolMaster).

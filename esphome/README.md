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

## Organisation des fichiers

La configuration est découpée en **paquets** ESPHome. `poolmaster.yaml` ne
contient que ce qui dépend de votre installation (nom de l'appareil et
brochage) puis assemble les paquets ; chaque paquet regroupe **une fonction de
la piscine avec ses entités *et* sa logique**, plutôt que de séparer par type
d'entité.

```
poolmaster.yaml            substitutions (brochage) + liste des paquets
exemple-webui-wifi-ota.yaml  variante : WiFi/OTA/serveur web détaillés
exemple-import-distant.yaml  variante : paquets importés depuis GitHub
secrets.yaml               vos identifiants (non versionné)
packages/
  device.yaml              carte ESP32, framework, logger, diagnostics
  network.yaml             WiFi, API Home Assistant, OTA, serveur web
  buses.yaml               I2C (ADS1115, PCF8574) et les deux bus OneWire
  state.yaml               variables globales partagées
  scheduler.yaml           horloge SNTP + ordre d'exécution des traitements
  measures.yaml            pH / ORP / pression / températures + coefficients C0-C1
  calibration.yaml         calibration multi-points embarquée (régression)
  modes.yaml               mode automatique, mode hiver
  filtration.yaml          pompe, plage horaire quotidienne, antigel
  regulation.yaml          cadre commun pH/ORP (modes auto, seuils, activation)
  regulation_ph.yaml       pompe pH + PID fenêtré REVERSE
  regulation_orp.yaml      pompe Chlore + PID fenêtré DIRECT
  electrolyse.yaml         électrolyseur au sel
  robot.yaml               robot de nettoyage
  levels.yaml              bacs, niveau piscine, pompe de remplissage
  safety.yaml              surpression, temps de marche max, acquittement
  auxiliary.yaml           relais libres R0 / R1
  status_leds.yaml         LEDs PCF8574 + buzzer
  nextion.yaml             écran Nextion (composant officiel + MAJ .tft WiFi)
  nextion-uart-brut.yaml   variante : protocole d'origine, HMI non modifié
```

Les paquets sont fusionnés par ESPHome : les identifiants (`id:`) sont visibles
depuis n'importe quel paquet, et les substitutions de `poolmaster.yaml`
s'appliquent partout. Pour retirer une fonction, il suffit de commenter la
ligne correspondante dans `packages:`.

### Où se décide l'ordre des traitements

Toute la logique périodique passe par des `script:` appelés depuis
`scheduler.yaml`, qui est le **seul** endroit où l'ordre est décidé :

| Cadence | Enchaînement |
|---|---|
| 1 s | `safety_tick` → `ph_dosing_tick` → `orp_dosing_tick` → `swg_tick` → `robot_tick` |
| 1 min | `filtration_tick` → `regulation_tick` |
| 15h05 | `compute_filtration_schedule` |
| 00h00 | `daily_reset` |
| 3 s | rafraîchissement des LEDs et du buzzer (`status_leds.yaml`, indépendant) |

`safety_tick` passe en premier parce qu'il arme les drapeaux d'erreur et peut
couper la filtration : les traitements suivants doivent en tenir compte dans le
même tick.

### Remplacer la configuration réseau

`exemple-webui-wifi-ota.yaml` est un second fichier d'entrée : il importe les
mêmes paquets fonctionnels mais **omet `network.yaml`** et définit à la place
son propre WiFi (IP fixe, puissance d'émission réduite), l'OTA avec mode sans
échec, et le serveur web avec authentification. C'est le point de départ
conseillé pour une installation réelle.

Attention en surchargeant un paquet : la fusion ESPHome traite les
dictionnaires clé par clé (le fichier principal gagne) mais **concatène les
listes**. Redéfinir `wifi:` ou `web_server:` fonctionne ; redéfinir `ota:` en
changeant le port produit deux entrées et l'erreur *« Only a single port is
supported »*. D'où la séparation `device.yaml` / `network.yaml`.

### Import distant (sans cloner le dépôt)

`exemple-import-distant.yaml` récupère les paquets directement depuis GitHub :
un dossier contenant ce seul fichier et un `secrets.yaml` suffit à compiler.

```yaml
packages:
  poolmaster:
    url: https://github.com/ekozan/ESP32-PoolMaster
    ref: v1.0.0        # tag ou SHA — voir ci-dessous
    refresh: 1d
    files:
      - esphome/packages/device.yaml
      - esphome/packages/buses.yaml
      # … un fichier par paquet, sauf network.yaml
```

**Épinglez un tag ou un SHA.** Sur une branche mouvante, un `esphome run`
lancé pour changer un mot de passe WiFi embarquerait au passage toute logique
de régulation poussée entre-temps, sans relecture. Sur un équipement qui dose
de l'acide et du chlore, la mise à jour doit rester un geste délibéré : on
change `ref:`. Avec un tag ou un SHA, `refresh:` n'a d'ailleurs plus d'effet,
le contenu ne bougeant pas.

On importe tous les paquets **sauf `network.yaml`**, remplacé par la
configuration WiFi/OTA/serveur web locale du fichier — c'est la seule partie
qui dépend de votre réseau.

### Réglages depuis Home Assistant

Tout se règle depuis Home Assistant, sans YAML côté HA : les entités
remontent automatiquement par l'API native. Aucune recompilation n'est
nécessaire pour changer une consigne.

| Type | Nombre | Exemples |
|---|---|---|
| `number` | 34 | consignes pH/ORP, Kp/Ki/Kd, fenêtres PID, heures de filtration, seuil de surpression, volumes et débits des bacs, coefficients C0/C1, valeurs des étalons de calibration |
| `switch` | 16 | mode auto, mode hiver, pompes, PID pH/ORP, mode électrolyseur, relais R0/R1, buzzer |
| `button` | 14 | acquitter les erreurs, bac rempli (×2), recalculer la filtration, redémarrer, et 9 boutons de calibration (enregistrer / calculer / effacer × 3 sondes) |

Les 34 `number` sont tous en `optimistic: true` (modifiables depuis HA) **et**
`restore_value: true` : la valeur est écrite dans la partition `nvs` et
survit aux coupures de courant comme aux mises à jour OTA. Les valeurs
`initial_value` du YAML ne servent qu'au tout premier démarrage.

Les compteurs internes persistants (temps de marche du jour, volume consommé
dans les bacs, plage de filtration calculée) sont dans le même cas — voir
`packages/state.yaml`.

Sont en revanche volontairement **non** persistants : les drapeaux d'erreur
(`psi_error`, `ph_uptime_error`…), qui repartent à zéro au démarrage plutôt
que de laisser un défaut ancien bloquer la régulation après un reboot.

### Calibration multi-points embarquée

Les coefficients `C0`/`C1` (`valeur = tension × C0 + C1`) peuvent être calculés
à bord au lieu d'être saisis à la main. Pour chaque sonde (pH, ORP, pression) :

1. plonger la sonde dans une solution étalon et attendre la stabilisation ;
2. saisir la valeur de l'étalon dans « … référence » ;
3. bouton « … enregistrer le point » ;
4. recommencer avec un autre étalon (jusqu'à 8 points) ;
5. bouton « … calculer la calibration ».

| Points enregistrés | Traitement |
|---|---|
| 1 | seul l'offset est corrigé, la pente est conservée — recalage rapide sur tampon pH 7 |
| 2 et plus | régression linéaire par moindres carrés sur l'ensemble des points |

Les points sont stockés en NVS : ils survivent aux coupures et aux OTA, une
calibration peut donc s'étaler sur plusieurs jours. Le résultat est écrit via
`make_call()` et non `publish_state()`, seul chemin qui déclenche la sauvegarde
persistante des `number`. Un capteur de diagnostic indique le nombre de points
enregistrés par sonde.

### Écran Nextion

Le paquet `packages/nextion.yaml` utilise le **composant `nextion` officiel**
d'ESPHome, sur l'UART TX GPIO17 / RX GPIO16 (les broches de `Serial2` du
firmware d'origine — aucun recâblage).

#### Ce qui marche sans rien changer

**Tout l'affichage.** Le composant envoie exactement les mêmes commandes que
le firmware d'origine (`globals.vapH.txt="7.20"`, `pageHome.vaPercArrowPH.val=73`,
le bitmap `globals.vaSwitches.val`, l'horloge `rtc0..rtc5`). Vos 21 pages
s'affichent comme avant.

#### Ce qu'il faut modifier dans le HMI

Le problème est dans le sens écran → ESP32. Le composant officiel réserve
l'octet `0x23` — celui que le protocole EasyNextion utilise comme début de
trame — pour le code d'erreur Nextion « nom de variable trop long » :

```cpp
case 0x23:  // too long variable name
  ESP_LOGW(TAG, "Variable name too long");
```

Vos `printh 23 02 53 XX` sont donc avalés comme des erreurs, et il n'existe
aucun point d'entrée pour les récupérer. Trois modifications à faire dans
Nextion Editor :

**1. Débit série fixé à 115200**

Dans l'onglet *Program.s* du HMI :

```
bauds=115200
```

`bauds` (avec un s) est persistant, contrairement à `baud`. Le composant
officiel ne sait pas resynchroniser le débit après un `rest` comme le faisait
le firmware d'origine ; l'écran doit donc démarrer directement au bon débit.

**2. Annonce de page : `sendme` au lieu de `printh`**

Dans le *Preinitialize Event* de chaque page, remplacer :

```
printh 23 02 50 02        ← à supprimer
sendme                    ← à mettre à la place
```

`sendme` fait émettre à l'écran une trame `0x66` standard, que le composant
remonte via `on_page`.

**3. Boutons : protocole « custom sensor »**

Dans le *Touch Release Event* de chaque bouton, remplacer le `printh 23 02 53 XX`
par une trame nommée. Exemple pour la pompe de filtration en bascule :

```
printh 91
prints "filt_pump",0
printh 00
printh 03 00 00 00
printh FF FF FF
```

Structure : `91`, puis le nom en clair terminé par `,0`, puis un octet nul,
puis la valeur sur **4 octets petit-boutiste**, puis le terminateur.

Valeurs conventionnelles :

| Valeur | Octets | Effet |
|---|---|---|
| 0 | `00 00 00 00` | Arrêt |
| 1 | `01 00 00 00` | Marche |
| 2 | `02 00 00 00` | Auto (boutons de menu à trois états) |
| 3 | `03 00 00 00` | Bascule |

Noms attendus par `packages/nextion.yaml`, à reprendre tels quels :

| Nom | Action | Remplace |
|---|---|---|
| `auto_mode` | Mode automatique | `ENMC_FILT_MODE` (0) |
| `ph_auto` | Régulation pH auto | `ENMC_PH_AUTOMODE` (1) |
| `orp_auto` | Régulation ORP auto | `ENMC_ORP_AUTOMODE` (2) |
| `filt_pump` | Pompe de filtration | `ENMC_FILT_PUMP` (4) |
| `ph_pump` | Pompe pH | `ENMC_PH_PUMP` (5) |
| `chl_pump` | Pompe Chlore | `ENMC_CHL_PUMP` (6) |
| `winter_mode` | Mode hiver | `ENMC_WINTER_MODE` (8) |
| `ph_pump_menu` | Bouton menu pH (3 états) | `ENMC_PH_PUMP_MENU` (11) |
| `chl_pump_menu` | Bouton menu Chlore (3 états) | `ENMC_CHL_PUMP_MENU` (12) |
| `filt_pump_menu` | Bouton menu Filtration (3 états) | `ENMC_FILT_PUMP_MENU` (13) |
| `swg_mode` | Mode électrolyseur | `ENMC_SWG_MODE_MENU` (15) |
| `swg` | Électrolyseur | — |
| `robot` | Robot | `ENMC_ROBOT` (17) |
| `lights` | Projecteur (relais R0) | `ENMC_LIGHTS` (18) |
| `spare` | Relais R1 | `ENMC_SPARE` (19) |
| `clear_alarms` | Acquitter les erreurs | `ENMC_CLEAR_ALARMS` (20) |
| `fill_pump` | Pompe de remplissage | `ENMC_FILLING_PUMP` (21) |

Un nom inconnu est journalisé (`action inconnue '…'`) sans effet — pratique
pour vérifier au fur et à mesure dans les logs ESPHome.

**Pourquoi des noms et pas les évènements tactiles standard ?** Le composant
sait aussi remonter les touches via `on_touch`, en cochant « Send Component ID »
dans Nextion Editor. Mais il faudrait alors relever le couple (page, id de
composant) pour chaque bouton, et toute réorganisation du HMI décalerait ces
identifiants. Le protocole nommé est plus verbeux à écrire une fois, et
insensible aux remaniements ensuite.

#### Ce que ça apporte

- **Mise à jour du `.tft` par WiFi**, au lieu de la carte SD — voir ci-dessous.
- Les plateformes `sensor`/`binary_sensor`/`switch`/`text_sensor` `nextion`,
  qui lient une entité à un composant de l'écran sans écrire de lambda.
- Les déclencheurs `on_sleep`, `on_wake`, `on_buffer_overflow`, et la gestion
  de la veille (`touch_sleep_timeout`, `auto_wake_on_touch`).

#### Mettre à jour le `.tft` par WiFi

**1. Héberger le fichier.** Déposez le `.tft` dans le dossier `config/www/` de
Home Assistant : il devient accessible sur
`http://<ha>:8123/local/<fichier>.tft`. Le fichier du dépôt est
`Nextion/tft/PoolMaster_Nextion_v6.tft` (~2,4 Mo). Préférez une adresse IP à un
nom `.local` — la résolution mDNS depuis l'ESP32 est moins fiable que depuis un
PC.

**2. Activer l'option.** Dans `packages/nextion.yaml`, décommentez le bloc
`tft_url:` **et** le bloc `button:` en fin de fichier. Les deux vont ensemble :
il n'existe pas d'action YAML `upload_tft`, c'est un appel C++ compilé
seulement si `tft_url` est défini (`#ifdef USE_NEXTION_TFT_UPLOAD`). Un bouton
sans `tft_url` ne compilerait pas.

```yaml
    tft_url: "http://192.168.1.10:8123/local/poolmaster.tft"
    tft_upload_http_timeout: 15s
    tft_upload_http_retries: 5
    tft_upload_watchdog_timeout: 60s
```

**3. Recompiler, flasher, puis appuyer** sur le bouton « Mettre à jour l'écran
Nextion » depuis Home Assistant ou l'interface web.

Trois choses à savoir avant de l'activer :

- **Le transfert bloque la boucle principale** plusieurs minutes : la
  régulation est suspendue pendant ce temps. À lancer filtration à l'arrêt,
  hors des plages de dosage.
- **Le firmware grossit.** ESPHome réintègre le client HTTP de l'ESP-IDF
  (`esp_http_client`), exclu du build par défaut pour gagner du temps de
  compilation. Compilation plus longue également.
- **En HTTPS, le certificat n'est pas vérifié** : ESPHome active
  `CONFIG_ESP_TLS_INSECURE` et `CONFIG_ESP_TLS_SKIP_SERVER_CERT_VERIFY` pour
  éviter d'embarquer une autorité de certification. Sans conséquence sur un
  réseau local, mais ne pointez pas cette URL vers Internet. Du simple HTTP sur
  le LAN reste le plus sain.

Si le transfert échoue en cours de route, l'écran peut rester en mode
réception. Il se récupère en rechargeant le `.tft` **par carte SD** : gardez
cette porte de sortie ouverte, surtout pour le premier essai.

> Pourquoi ces options sont dans `nextion.yaml` et pas dans un paquet séparé
> qu'on ajouterait au besoin : la fusion ESPHome **concatène** les listes sans
> les fusionner par `id:`. Un second paquet déclarant `display: - id: nx` ne
> compléterait donc pas le composant existant, il créerait une deuxième entrée
> incomplète et la validation échouerait sur *« 'display' requires a 'platform'
> key »*.

#### Si vous ne voulez pas toucher au HMI

`packages/nextion-uart-brut.yaml` reproduit le protocole d'origine sur un UART
brut et fonctionne avec l'écran **tel quel**. Remplacez la ligne du bloc
`packages:` :

```yaml
  nextion:  !include packages/nextion-uart-brut.yaml
```

Vous perdez les avantages ci-dessus, mais aucune modification du HMI n'est
nécessaire.

#### Non porté dans les deux cas

Les pages de configuration profondes — scan et configuration WiFi, MQTT, SMTP,
clavier numérique, graphiques d'historique, calibration à l'écran, choix de la
langue. La calibration reste accessible depuis Home Assistant et l'interface
web.

### Place disponible en flash

L'ESP32 DevKit v1 a **4 Mo** de flash. La table de partitions générée par
ESPHome (`partitions.csv`, ESP-IDF) la découpe ainsi :

| Partition | Taille | Rôle |
|---|---|---|
| `otadata` | 8 Ko | quelle image démarrer |
| `phy_init` | 4 Ko | calibration radio |
| `app0` | **1,75 Mo** | image applicative active |
| `app1` | **1,75 Mo** | image de réception OTA |
| `nvs` | 448 Ko | réglages persistants (`restore_value: true`) |

Deux points en découlent :

- **L'OTA est déjà provisionné.** Les deux emplacements `app0`/`app1` sont
  réservés d'office : une mise à jour est écrite dans l'emplacement inactif
  puis le démarrage bascule dessus. L'OTA ne « prend » donc pas de place en
  plus — c'est le coût d'entrée de cette table de partitions, actif que l'on
  s'en serve ou non. Le budget réel du firmware est **1,75 Mo**, pas 4 Mo.
- **Le serveur web et le WiFi tiennent largement.** Le WiFi et l'API sont de
  toute façon obligatoires ici (c'est par eux que passe Home Assistant). Le
  serveur web charge par défaut son JS depuis le CDN `oi.esphome.io` et ne
  coûte donc que le serveur HTTP embarqué.

  L'option `local: true` embarque ces ressources dans le firmware, pour une
  installation sans accès Internet. Coût mesuré dans les sources d'ESPHome
  2026.6.5 (tableaux d'octets de `server_index_*.h`) :

  | `version:` | Assets embarqués avec `local: true` | Part des 1,75 Mo |
  |---|---|---|
  | 2 | ~24 Ko | ~1,4 % |
  | 3 | ~142 Ko | ~8 % |

  L'interface v3 est donc nettement plus lourde à embarquer que la v2, mais
  reste très supportable sur cette carte.

Les réglages persistants (consignes, calibrations, compteurs) vivent dans la
partition `nvs` de 448 Ko et ne consomment rien sur le budget applicatif.

## Compilation : « Killed signal terminated program cc1plus »

Ce message n'est **pas** une erreur de code : le compilateur a été tué par le
noyau, faute de mémoire. Il apparaît typiquement sur `api_server.cpp` ou
`web_server`, très tôt dans la compilation.

Par défaut ESPHome lance autant de compilateurs que de cœurs. Sur l'add-on
Home Assistant, plusieurs `cc1plus` en parallèle sur ces grosses unités
épuisent la RAM. `packages/device.yaml` fixe donc :

```yaml
esphome:
  compile_process_limit: 1
```

Sur une machine avec beaucoup de mémoire, montez cette valeur (bornée au
nombre de cœurs) pour accélérer nettement la compilation. ccache étant actif,
seules les premières compilations sont longues.

Si le problème persiste malgré `1`, c'est que la machine est vraiment juste :
ajoutez du swap, ou compilez depuis un PC avec `esphome run` puis flashez en
OTA.

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

- **API MQTT JSON historique** (`Home/Pool/Meas1`, `Set1`… et bitmaps `IO`) :
  remplacée par les entités natives ci-dessus. Les dashboards
  HomeAssistant/NodeRed existants basés sur ces topics doivent être adaptés.
- **Notifications SMTP** : à réaliser côté Home Assistant (automatisations sur
  les entités `binary_sensor` d'erreur).
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

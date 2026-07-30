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
homeassistant/dashboard.yaml  tableau de bord HA (courbes incluses)
homeassistant/themes/poolmaster.yaml  thème HA (palette piscine, clair + sombre)
web-ui.css                 habillage optionnel de l'interface embarquée
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
  safety.yaml              surpression, désamorçage, temps de marche max, acquittement
  auxiliary.yaml           relais libres R0 / R1
  status_leds.yaml         LEDs PCF8574 + buzzer
  web-ui-groups.yaml       sections de l'interface web embarquée
  nextion-uart-brut.yaml   écran Nextion — protocole d'origine (PAR DÉFAUT)
  nextion.yaml             variante : composant officiel + MAJ .tft WiFi
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

#### « … does not exist in repository » : le cache est périmé

ESPHome clone le dépôt une fois puis ne le re-vérifie que tous les `refresh:`
(1 jour si vous ne précisez rien). Si un fichier de paquet a été **renommé ou
ajouté** depuis
votre dernier clone, la liste `files:` référence un nom que le clone en cache
ne contient pas, et la validation échoue sur :

```
esphome/packages/<fichier>.yaml does not exist in repository.
```

Le fichier existe bien sur la branche : c'est le cache local qui est en retard.
Trois façons de le forcer, de la plus simple à la plus radicale :

1. **Raccourcir `refresh:`** le temps d'une compilation. `0s` ou `1s`
   re-vérifient le dépôt à chaque exécution — c'est le réglage que porte
   actuellement `exemple-import-distant.yaml`. Pratique tant que la branche
   bouge, mais à remonter (`1d`) une fois la configuration stabilisée : chaque
   build interroge GitHub, et sur une branche mouvante vous récupérez alors
   tout changement poussé entre-temps sans l'avoir relu.
2. **Changer `ref:`** — le dossier de cache est nommé d'après un hachage de
   l'URL *et* de la référence, donc pointer un tag ou un SHA crée un cache neuf.
   C'est l'occasion d'épingler pour de bon, comme conseillé plus haut.
3. **Supprimer le cache.** Il est dans `<dossier de config>/.esphome/packages/`,
   sauf **sur l'add-on Home Assistant où le dossier de données est `/data`** :
   le cache est alors dans `/data/packages/`, accessible seulement par le
   terminal de l'add-on, pas par l'éditeur de fichiers.

C'est l'inconvénient de l'import distant : un renommage de fichier côté dépôt
casse les consommateurs jusqu'au rafraîchissement. Épingler un tag l'évite —
vous ne changez de version que quand vous le décidez, et le changement de `ref:`
recrée le cache au passage.

### Réglages depuis Home Assistant

Tout se règle depuis Home Assistant, sans YAML côté HA : les entités
remontent automatiquement par l'API native. Aucune recompilation n'est
nécessaire pour changer une consigne.

| Type | Nombre | Exemples |
|---|---|---|
| `number` | 36 | consignes pH/ORP, Kp/Ki/Kd, fenêtres PID, heures de filtration, seuil de surpression, référence filtre propre et seuil d'encrassement, volumes et débits des bacs, tampons et solutions étalons des assistants |
| `switch` | 17 | arrêt d'urgence, mode auto, mode hiver, pompes, PID pH/ORP, mode électrolyseur, relais R0/R1, buzzer |
| `button` | 12 | acquitter les erreurs, bac rempli (×2), recalculer la filtration, enregistrer la référence filtre propre, redémarrer, et les 6 boutons des trois assistants d'étalonnage (avancer / annuler) |

Onze entités de plus existent mais sont **masquées** par défaut : les six
coefficients `C0`/`C1` et le mode de calibration manuel point par point. Voir
[Mode manuel et coefficients C0/C1](#mode-manuel-et-coefficients-c0c1--masqués-par-défaut).

Les 36 `number` sont tous en `optimistic: true` (modifiables depuis HA) **et**
`restore_value: true` : la valeur est écrite dans la partition `nvs` et
survit aux coupures de courant comme aux mises à jour OTA. Les valeurs
`initial_value` du YAML ne servent qu'au tout premier démarrage.

Les compteurs internes persistants (temps de marche du jour, volume consommé
dans les bacs, plage de filtration calculée) sont dans le même cas — voir
`packages/state.yaml`.

Sont en revanche volontairement **non** persistants : les drapeaux d'erreur
(`psi_error`, `ph_uptime_error`…), qui repartent à zéro au démarrage plutôt
que de laisser un défaut ancien bloquer la régulation après un reboot.

### Interfaces : web embarquée et Home Assistant

**Interface web embarquée** (port 80). Les 96 entités s'affichaient en une
liste plate, ce qui rendait la page illisible. Elles sont maintenant réparties
en huit sections via les groupes de tri de `web_server` version 3 :

| Section | Contenu |
|---|---|
| Mesures | pH, ORP, pression, températures |
| État de la piscine | plage de filtration, niveaux des bacs, contacts, antigel |
| Commandes | les huit pompes et relais |
| Modes et régulation | modes auto/hiver, PID, consignes pH et ORP |
| Sécurité | arrêt d'urgence, erreurs, seuils, acquittement |
| Calibration | étalons, boutons, coefficients C0/C1 |
| Réglages avancés | Kp/Ki/Kd, fenêtres, horaires, débits, volumes |
| Diagnostic | uptime, RSSI, temps de marche, redémarrage |

Les groupes sont déclarés dans `packages/web-ui-groups.yaml` et chaque entité
indique son appartenance dans son propre paquet :

```yaml
    web_server:
      sorting_group_id: grp_mesures
      sorting_weight: 10        # ordonne à l'intérieur du groupe
```

Ce paquet est séparé de `network.yaml` à dessein : les fichiers d'entrée qui
définissent leur propre `web_server:` n'importent pas `network.yaml`, et comme
la fusion ESPHome combine les dictionnaires clé par clé, ce paquet leur ajoute
les groupes sans écraser leur port ni leur authentification. **Tout fichier
d'entrée qui inclut les paquets d'entités doit l'importer**, sinon la
validation échoue sur *« Couldn't find ID 'grp_…' »*.

### Pression : deux capteurs, un seul est à tracer

La pression n'existe que si la **pompe de recirculation** tourne. À l'arrêt le
manomètre retombe à zéro, et ce zéro ne dit rien de l'état du filtre.

| Entité | Publie | À quoi elle sert |
|---|---|---|
| `Pression filtration` | en continu, toutes les 2 s | sécurité surpression, assistant d'étalonnage, lecture instantanée |
| `Pression en filtration` | toutes les 2 s, mais seulement pompe en marche depuis > 2 min | **tendance d'encrassement**, décision de contre-lavage |

Le second ne publie rien hors de sa fenêtre — la dernière valeur valable est
donc conservée. C'est lui qu'il faut tracer sur le long terme : la courbe du
capteur brut est un peigne de zéros entre les cycles de filtration, dans lequel
la lente montée due à l'encrassement est illisible.

Le délai de 2 minutes est le même que celui de la sécurité surpression : le
temps que le régime hydraulique s'établisse après le démarrage.

### Encrassement du filtre et contre-lavage

La règle est simple : **le filtre est à contre-laver quand la pression en
fonctionnement dépasse la pression filtre propre de 200 mbar.** Le seuil est
réglable, la référence aussi.

| Entité | Rôle | Défaut |
|---|---|---|
| `Filtre propre — pression de référence` | pression relevée filtre propre | 0,50 bar |
| `Seuil d'encrassement` | écart déclenchant l'alerte | 200 mbar |
| `Encrassement du filtre` | écart mesuré, en mbar | — |
| `Contre-lavage nécessaire` | alerte `device_class: problem` | — |
| `Filtre propre — enregistrer la référence` | bouton de capture | — |

**Le geste à faire.** Juste après un contre-lavage, relancez la filtration,
attendez 2 minutes, puis pressez `Filtre propre — enregistrer la référence`.
Le bouton relève la pression courante et la stocke en NVS. Sans ce geste la
référence reste à sa valeur d'usine (0,50 bar) et l'indicateur ne veut rien
dire sur votre installation — chaque filtre, chaque hydraulique a la sienne.

Le bouton refuse de relever une référence pompe à l'arrêt ou dans les 2
premières minutes de marche ; il l'écrit dans le journal plutôt que
d'enregistrer une valeur fausse.

`Encrassement du filtre` se lit directement contre le seuil : à +200 mbar il
est temps. La valeur peut être négative si la référence avait été prise sur un
filtre déjà un peu chargé — c'est sans gravité, reprenez la référence.

`Contre-lavage nécessaire` exige **10 minutes** au-dessus du seuil avant de
passer à l'état actif (et autant pour retomber) : l'encrassement est un
phénomène de plusieurs semaines, les pointes au démarrage de la pompe ou lors
d'une manœuvre de vanne ne doivent pas déclencher d'alerte.

⚠ **À ne pas confondre avec `Seuil surpression`** (`safety.yaml`). Celui-là est
une sécurité absolue : au-dessus, la filtration est coupée et une erreur est
levée. L'encrassement, lui, est un indicateur d'entretien — il ne coupe rien,
il vous dit d'aller manœuvrer la vanne.

Tout est calculé sur `Pression en filtration`, jamais sur le capteur brut : le
brut retombe à zéro entre les cycles, ce qui ferait clignoter l'alerte à chaque
arrêt de pompe.

### Détection de désamorçage

L'autre côté de la même référence. Une pompe désamorcée brasse de l'air : elle
ne monte pas en pression et **tourne à sec**, ce qui détruit sa garniture
mécanique en quelques minutes.

La règle : si la pression reste sous **la référence filtre propre moins
100 mbar** pendant **30 secondes**, la filtration est coupée et l'erreur
`Erreur désamorçage pompe` est levée. Les deux valeurs sont réglables
(`Seuil de désamorçage`, `Délai de désamorçage`).

| | Compté depuis la référence | Effet |
|---|---|---|
| `Seuil de désamorçage` | **vers le bas** (−100 mbar) | coupe la filtration |
| `Seuil d'encrassement` | **vers le haut** (+200 mbar) | signale, ne coupe rien |

Les deux encadrent la pression normale de l'installation.

**Le compteur démarre avec la pompe** — le délai *est* la temporisation de
démarrage. Une pompe amorcée monte en pression en quelques secondes, très en
deçà de 30 s ; une pompe qui brasse de l'air n'y arrivera jamais. C'est aussi
pourquoi ce contrôle n'attend pas les 2 minutes de la sécurité surpression :
ce sont justement ces 2 minutes qu'il ne faut pas passer à tourner à vide.

⚠ **La protection ne s'arme qu'une fois la référence relevée** sur votre
installation, par le bouton `Filtre propre — enregistrer la référence`. Avec
la valeur d'usine, le plancher serait arbitraire et couperait une pompe
parfaitement saine. Tant que le geste n'a pas été fait, le journal le signale
à chaque démarrage :

```
[W] Desamorcage: protection INACTIVE, reference filtre propre jamais enregistree
```

Une fois l'erreur levée, **plus aucun redémarrage automatique n'est possible**,
antigel compris. C'est délibéré : une pompe désamorcée ne fait circuler aucune
eau, elle ne protège donc de rien du gel — elle ne ferait que se détruire.
Réamorcez, puis `Acquitter les erreurs` (bouton, ou action Clear de l'écran
Nextion). L'erreur allume aussi la LED d'alarme du bandeau PCF8574.

L'écran Nextion n'a pas d'indicateur dédié : les 32 bits de statut du protocole
d'origine sont tous attribués et en ajouter un imposerait de modifier le HMI.
L'acquittement depuis l'écran efface bien cette erreur comme les autres.

### Couleurs et style

Deux surfaces, avec des marges de manœuvre très inégales — autant le dire tout
de suite.

**Home Assistant : c'est là que le style se fait.** `homeassistant/themes/poolmaster.yaml`
est un thème natif, **sans HACS**, en palette « eau de piscine » : bleus et
turquoise pour le normal, ambre et rouge réservés aux alertes pour qu'elles
ressortent. Les deux variantes claire et sombre sont fournies, Home Assistant
bascule seul. Copiez-le dans `<config>/themes/`, assurez-vous d'avoir
`frontend: themes: !include_dir_merge_named themes` dans `configuration.yaml`,
et redémarrez. Le tableau de bord porte déjà `theme: PoolMaster`, donc le
thème ne s'applique qu'à lui et le reste de votre installation ne bouge pas.

Le tableau de bord tire parti du thème : badges d'alerte en haut de la vue
d'ensemble, `state_color: true` sur les cartes d'entités — une pompe en marche
passe en turquoise, une alarme active en rouge —, jauges pH, ORP, température
et pression avec seuils colorés, et une palette de courbes cohérente.

**Interface web embarquée : marge limitée, autant le savoir.** `web_server`
accepte `css_include:`, qui embarque un CSS dans le firmware et ajoute
`<link rel=stylesheet href=/0.css>` à la page. Mais l'UI v3 est bâtie en *web
components* : le CSS ordinaire ne traverse pas le shadow DOM.

| Ce qui passe | Ce qui ne passe pas |
|---|---|
| fond de page, police, marges, largeur | cibler `.card`, `table`, `button`… |
| variables CSS (`--nom`), par héritage | tout sélecteur d'élément interne |

`web-ui.css` fait ce qui est faisable : dégradé de fond clair/sombre, police
système, largeur de lecture limitée. Il déclare aussi des variables CSS, mais
**leurs noms ne sont pas vérifiés** — le bundle v3 est servi depuis un CDN qui
n'a pas pu être inspecté ici. Pour trouver les vrais noms : F12, sélectionnez
`<esp-app>`, onglet « Computed », filtrez sur `--`. Les variables inutiles sont
ignorées sans rien casser.

L'option est commentée dans `packages/network.yaml` ; le chemin se résout
depuis le dossier de configuration, pas depuis le paquet.

### Courbes

L'interface embarquée n'a pas d'historique : les courbes viennent de **Home
Assistant**, qui enregistre automatiquement tout capteur déclarant un
`state_class`. C'est le cas de **16 des 19 capteurs** (les 3 restants sont des
compteurs de diagnostic).

`homeassistant/dashboard.yaml` est un tableau de bord prêt à coller, sans
aucune dépendance HACS, avec trois vues :

- **Vue d'ensemble** — jauges pH et ORP, températures, commandes, état du
  filtre, alarmes ;
- **Courbes** — pH et ORP superposés à leur consigne (on voit l'effet de
  chaque dosage), températures sur 7 jours, **tendance d'encrassement du
  filtre sur 60 jours** et l'écart à la référence tracé contre son seuil,
  consommation des bacs, et des graphes `statistics-graph` moyenne/min/max
  par jour ;
- **Réglages** — consignes, filtration, contre-lavage, calibration, sécurité.

Les identifiants d'entités y dérivent du nom de l'appareil : avec
`name: poolmaster`, « Température eau » devient
`sensor.poolmaster_temperature_eau`. Si vous renommez l'appareil, remplacez le
préfixe.

### Arrêt d'urgence (hors filtration)

Le switch **« Arrêt d'urgence (hors filtration) »** coupe tout ce qui injecte
ou consomme, mais **laisse l'eau circuler** :

| Coupé | Conservé |
|---|---|
| pompe pH, pompe Chlore | **pompe de filtration** (recirculation) |
| électrolyseur | relais libres R0 / R1 |
| robot | buzzer et LEDs de statut |
| pompe de remplissage | |
| boucles PID pH et ORP | |

La filtration n'est délibérément pas touchée : elle continue de suivre son
programme, protection antigel comprise. Garder la recirculation homogénéise ce
qui a déjà été dosé et maintient des mesures pH/ORP représentatives pendant
l'incident — une sonde dans de l'eau stagnante ne mesure plus le bassin.

Deux points de conception :

- **Ce n'est pas une action ponctuelle.** Le switch coupe immédiatement à
  l'armement, mais surtout la condition `sw_safe_stop` est ajoutée à *tous* les
  verrous existants — dosage pH, dosage ORP, électrolyseur, robot, remplissage,
  et activation automatique des PID. Sans cela, le tick suivant relancerait une
  pompe une seconde plus tard.
- **L'état survit au redémarrage** (`RESTORE_DEFAULT_OFF`). Si vous l'armez à
  cause d'une fuite, un reboot ne doit pas relancer le dosage tout seul. En
  contrepartie, pensez à le désarmer explicitement — tant qu'il est armé, plus
  aucune régulation n'a lieu.

Il est pilotable depuis Home Assistant, l'interface web, et depuis l'écran
Nextion via la clé `safe_stop` (voir le tableau des noms plus haut) si vous
ajoutez un bouton au HMI.

### Calibration multi-points embarquée

#### Assistant pH guidé (le plus simple)

Pour le pH, un assistant remplace la saisie manuelle : **un texte de statut dit
quoi faire, un seul bouton fait avancer**.

| Ce que le statut affiche | Ce que vous faites |
|---|---|
| « Prêt. Appuyez sur… » | appuyer sur **Point suivant** |
| « 1/3 — Rincez la sonde, plongez-la dans le tampon pH 4.01, attendez la stabilisation (2.0431 V) » | tremper, attendre, appuyer |
| « 2/3 — … tampon pH 7.01 … » | idem |
| « 3/3 — … tampon pH 9.18 … » | idem — le calcul se lance seul |
| « Terminé sur 3 points. C0=… C1=… — pente à 97 % du nominal (sonde OK) » | rien, c'est fini |

La **tension mesurée est affichée en direct** dans le statut : on voit la sonde
se stabiliser et on sait quand appuyer, au lieu de deviner.

Les trois tampons sont **paramétrables** (`Étalonnage pH — tampon 1/2/3`), avec
4.01 / 7.01 / 9.18 par défaut. Un bouton **Annuler** abandonne la séquence sans
toucher à la calibration en vigueur — celle-ci n'est remplacée qu'une fois les
trois points relevés.

À la fin, le statut compare la pente obtenue à la valeur nominale et rend un
verdict : *sonde OK*, *sonde fatiguée* ou *résultat douteux*. Un écart
important trahit une sonde en fin de vie ou un tampon périmé.

L'assistant n'est qu'un pilote : il remplit les mêmes tableaux et appelle la
même régression que le mode manuel ci-dessous — un seul moteur de calibration,
deux façons de s'en servir. L'état de l'assistant n'est volontairement **pas**
persistant : un étalonnage interrompu par une coupure repart de zéro plutôt que
de reprendre au milieu avec une sonde dont on ne sait plus où elle est.

#### Assistant ORP guidé

Même principe, **mais pas les mêmes réglages** — et c'est volontaire.

Une sonde ORP ne se calibre pas comme une sonde pH. La pente
(`C0 = 431 mV/V`) vient du **gain de l'amplificateur de la carte**, pas de la
sonde : c'est une constante matérielle. Une sonde ORP se recale donc en
**décalage seul**, sur une unique solution étalon — ce que la plupart des
utilisateurs possèdent, d'ailleurs.

D'où `Étalonnage ORP — nombre de solutions`, réglé à **1 par défaut** :

| Réglage | Effet |
|---|---|
| 1 solution *(défaut)* | corrige le décalage `C1`, conserve la pente matérielle |
| 2 solutions | régression complète — à réserver au cas où vous possédez vraiment deux solutions ORP distinctes |

Forcer une régression sur deux points trop rapprochés dégraderait la pente au
lieu de l'améliorer : ne passez à 2 que si vos deux solutions sont réellement
éloignées (par exemple 240 mV et 470 mV, les valeurs par défaut).

Le verdict de fin est adapté au mode : en 1 point il commente le **décalage**
obtenu (*normal*, *décalage important — nettoyez la sonde*, *décalage anormal —
sonde probablement HS*) plutôt qu'une pente qui n'a pas bougé.

#### Assistant pression guidé

Une pression n'a pas de solution étalon : la seule référence disponible est le
**manomètre du filtre**. L'assistant s'appuie donc sur les deux points que
l'installation fournit d'elle-même, et **pilote la filtration** pour les
obtenir.

| Étape | Ce qui se passe | Ce que vous faites |
|---|---|---|
| Démarrage | l'assistant **arrête la filtration** | appuyer sur **Valider** |
| 1/2 — zéro | la pression retombe à l'atmosphère, soit 0 bar relatif | attendre le retour à zéro, **Valider** |
| — | l'assistant **redémarre la pompe** tout seul | — |
| 2/2 — point haut | la pression monte | lire le manomètre, saisir la valeur, **Valider** |
| Fin | régression 2 points, `C0`/`C1` écrits | rien |

Le zéro ne demande aucune saisie : pompe à l'arrêt, la pression relative *est*
nulle. C'est le point de référence le plus fiable dont on dispose.

**La filtration est remise dans l'état où l'assistant l'a trouvée**, à la fin
comme à l'annulation — il ne laisse pas l'installation dans un état que vous
n'avez pas choisi.

Deux points de vigilance, assumés plutôt que masqués :

- **La sécurité surpression reste active.** Elle s'appuie justement sur le
  capteur en cours d'étalonnage, donc un déclenchement intempestif est
  possible si la calibration de départ est très fausse. Le statut le signale
  alors explicitement, au lieu de désarmer une protection le temps de la
  manipulation.
- **Si la pompe s'arrête d'elle-même** pendant l'étape 2 — mode automatique
  sortant de sa plage horaire, par exemple — le statut vous le dit et refuse
  de valider un point faux.

#### Mode manuel et coefficients C0/C1 — masqués par défaut

Les trois assistants couvrent les trois sondes et **écrivent eux-mêmes** les
coefficients. Le mode manuel point par point et les `C0`/`C1` n'apparaissent
donc **ni dans Home Assistant ni dans l'interface web** : onze entités qui
encombraient l'écran pour un usage rare, et une invitation à retoucher des
coefficients à la main — ce qui ne peut que dégrader une calibration correcte.

Ce qui disparaît :

| Entités masquées | |
|---|---|
| `… — enregistrer le point`, `… — calculer la calibration`, `… — effacer les points` | × 3 sondes |
| `pH référence (solution étalon)`, `ORP référence (solution étalon)` | consignes du mode manuel seul |
| `pH/ORP/PSI calibration C0` et `C1` | 6 coefficients |

Ce qui **reste affiché** : les trois assistants, les tampons et solutions
paramétrables, les compteurs de points, et `Pression référence (manomètre)` —
cette dernière n'est pas une consigne de mode manuel, c'est la saisie que
l'assistant pression réclame à l'étape 2/2.

**Rien n'est supprimé.** Les entités sont `internal: true`, pas retirées : les
coefficients restent des `number` persistés en NVS, écrits par les assistants
et lus par les lambdas de mesure à l'identique. Seul l'affichage change.

Pour tout ressortir — report d'un certificat d'étalonnage, étalons non
standard, calibration à plus de 3 points — une substitution suffit dans le
fichier d'entrée :

```yaml
substitutions:
  masquer_calibration_experte: "false"
```

puis `esphome run`. Le défaut `"true"` est déclaré dans `measures.yaml` et
`calibration.yaml`, si bien qu'un fichier d'entrée qui ne connaît pas ce
drapeau compile sans rien changer.

Le mode manuel, une fois réaffiché, fonctionne ainsi : plonger la sonde dans
un étalon, attendre la stabilisation, saisir la valeur dans « … référence »,
« … enregistrer le point », recommencer (jusqu'à 8 points), puis « … calculer
la calibration ».

| Points enregistrés | Traitement |
|---|---|
| 1 | seul l'offset est corrigé, la pente est conservée — recalage rapide sur tampon pH 7 |
| 2 et plus | régression linéaire par moindres carrés sur l'ensemble des points |

Les points sont stockés en NVS : ils survivent aux coupures et aux OTA, une
calibration peut donc s'étaler sur plusieurs jours. Le résultat est écrit via
`make_call()` et non `publish_state()`, seul chemin qui déclenche la sauvegarde
persistante des `number`. Un capteur de diagnostic indique le nombre de points
enregistrés par sonde — il reste affiché, les assistants l'alimentent aussi.

### Écran Nextion

Deux paquets au choix, sur l'UART TX GPIO17 / RX GPIO16 (les broches de
`Serial2` du firmware d'origine — aucun recâblage dans les deux cas) :

| Paquet | HMI à modifier | État |
|---|---|---|
| `nextion-uart-brut.yaml` | **non** | **paquet par défaut** |
| `nextion.yaml` | oui, 3 modifications | à activer quand le HMI est prêt |

**Pourquoi l'UART brut est le défaut.** Le firmware d'origine élevait le débit
avec `baud=115200`, la commande *volatile* : l'écran repart à 9600 à chaque
mise sous tension, et le firmware renégociait à chaque démarrage. Le paquet
UART brut rejoue cette séquence, le composant officiel ne sait pas le faire —
d'où un écran figé tant que le HMI n'a pas été passé en `bauds=115200`
persistant.

Basculer sur le composant officiel une fois le HMI modifié se fait en une
ligne du bloc `packages:` :

```yaml
  nextion:  !include packages/nextion.yaml
```

Ce qui suit décrit ce composant officiel et les modifications qu'il réclame.

#### Ce qui marche sans rien changer

**Tout l'affichage.** Le composant envoie exactement les mêmes commandes que
le firmware d'origine (`globals.vapH.txt="7.20"`, `pageHome.vaPercArrowPH.val=73`,
le bitmap `globals.vaSwitches.val`, l'horloge `rtc0..rtc5`). Vos 21 pages
s'affichent comme avant.

#### Écran figé, aucune valeur affichée

Cause la plus probable : **le débit série**. Le firmware d'origine utilisait
`baud=115200`, la commande **volatile** — l'écran repart donc à **9600 à chaque
mise sous tension**, et l'ancien firmware le remontait à chaque démarrage :

```cpp
myNex.writeStr(F("rest"));   // Nextion revient à 9600
delay(800);
myNex.begin(9600);
Serial2.print("baud=115200"); // volatile : perdu à la coupure suivante
myNex.begin(115200);
```

Le composant officiel ne sait pas faire cette renégociation : il ouvre l'UART
à 115200 et parle. Si l'écran est à 9600, il n'entend rien et reste figé sur
sa dernière image.

Trois issues, de la plus rapide à la plus propre :

1. **Revenir à la variante UART brut** (aucune modification du HMI). Elle
   rejoue la séquence d'origine et refait fonctionner l'écran *et* les boutons
   immédiatement :

   ```yaml
     nextion:  !include packages/nextion-uart-brut.yaml
   ```

2. **Test rapide** : passer l'UART de `packages/nextion.yaml` à
   `baud_rate: 9600`. L'affichage revient (plus lent), les boutons restent
   inertes tant que le HMI n'émet pas les trames `printh 91`.

3. **La solution durable** : dans *Program.s* du HMI, écrire `bauds=115200`
   — avec un **s**, la variante persistante — puis recharger le `.tft`.
   L'écran démarrera alors directement au bon débit et le composant officiel
   dialoguera sans négociation.

Pour confirmer le diagnostic, passez le journal en debug et cherchez les
lignes `nextion` :

```yaml
logger:
  level: DEBUG
```

Silence complet côté Nextion = problème de débit. Des trames reçues mais des
boutons sans effet = le HMI émet encore l'ancien protocole `printh 23`.

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
| `safe_stop` | Arrêt d'urgence (hors filtration) | — (nouveau) |
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

## Cible matérielle et version d'ESPHome

`packages/device.yaml` déclare **la carte et la variante de puce** :

```yaml
esp32:
  board: esp32doit-devkit-v1
  variant: esp32
```

Les deux ensemble ne sont pas redondants : ESPHome vérifie leur cohérence et
refuse la configuration si elles divergent, avec *« Option 'variant' does not
match selected board »*. C'est le garde-fou contre un binaire compilé pour une
autre puce — si le flash échoue sur *« détecté ESP32-D0WDQ6 mais l'appareil
attend esp32c6 »*, c'est que le binaire proposé ne vient pas de cette
configuration.

Côté version :

```yaml
esphome:
  min_version: 2026.4.0
  name_add_mac_suffix: false
```

`min_version` est une valeur **vérifiée** : la configuration complète valide
sous ESPHome 2026.4.0. Sans cette ligne, ESPHome inscrit par défaut la version
qui a généré le build, ce qui n'interdit jamais rien.

`name_add_mac_suffix: false` garde l'appareil joignable en `poolmaster.local`
quelle que soit la carte. À passer à `true` uniquement si vous flashez
plusieurs PoolMaster sur le même réseau.

## Le buzzer est sur une broche de strapping (GPIO2)

GPIO2 fait partie des broches de *strapping* de l'ESP32 (avec 0, 5, 12 et 15) :
leur état est lu au démarrage pour choisir le mode de boot. Le brochage vient
de la carte PoolMaster — le firmware d'origine utilisait déjà GPIO2 pour le
buzzer — ce n'est donc pas un choix du portage.

`packages/status_leds.yaml` pose `ignore_strapping_warning: true` sur cette
broche, avec la justification en commentaire : l'avertissement est attendu, et
le laisser défiler à chaque compilation finirait par masquer de vrais
avertissements.

Deux conséquences pratiques :

- **GPIO2 doit être bas (ou flottant) pour entrer en mode téléversement USB.**
  Si un jour l'ESP32 refuse de passer en mode flash par USB, débrancher le
  buzzer est la première chose à essayer.
- Entre le reset et l'initialisation d'ESPHome, l'état de la broche n'est pas
  maîtrisé : **un bref bip au démarrage est normal**.

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
seules les premières compilations sont longues : une fois le cache chaud, une
modification de YAML ne recompile que `main.cpp`, et la parallélisation compte
beaucoup moins.

Vous pouvez la régler **depuis votre fichier d'entrée** sans toucher au
paquet — `esphome:` est un dictionnaire, donc le fichier principal l'emporte :

```yaml
esphome:
  compile_process_limit: 3
```

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
  - arrêt du dosage si bac vide (contact de niveau) ;
  - **arrêt d'urgence** manuel (voir ci-dessous).
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
- La protection contre le désamorçage reste **inactive** tant que la référence
  « filtre propre » n'a pas été relevée sur votre installation. Faites-le dès
  la mise en service, c'est un appui sur un bouton.

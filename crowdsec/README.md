# CrowdSec — config versionnée

Ce dossier versionne la configuration **custom** de l'instance CrowdSec.
L'arborescence reflète `/etc/crowdsec` : chaque sous-dossier se déploie tel
quel au même endroit sur le serveur.

```
crowdsec/
├── acquis.d/          # sources d'acquisition (dont le listener AppSec)
├── appsec-configs/    # configs AppSec/WAF custom (whitelists, hooks)
├── appsec-rules/      # règles AppSec custom (vpatch maison, etc.)
├── parsers/
│   ├── s01-parse/     # parsers custom
│   └── s02-enrich/    # enrichissement + whitelists d'IPs de confiance
├── scenarios/         # scénarios custom
├── postoverflows/
│   └── s01-whitelist/ # whitelists évaluées juste avant le ban
└── deploy.sh          # copie le tout vers /etc/crowdsec + restart
```

> ⚠️ **Ne jamais versionner ici** : `config.yaml`, `local_api_credentials.yaml`,
> `online_api_credentials.yaml`, clés de bouncers ni aucun secret. Uniquement
> des règles/whitelists. Ce qui vient du hub (`cscli install ...`) n'a pas
> besoin d'être versionné non plus : seul le custom vit ici.

## Déploiement

```bash
# depuis le serveur, à la racine du repo :
sudo ./crowdsec/deploy.sh --dry-run   # voir ce qui serait copié
sudo ./crowdsec/deploy.sh             # copier + restart crowdsec
```

En Docker : monter directement les sous-dossiers dans le conteneur
(ex. `./crowdsec/appsec-configs:/etc/crowdsec/appsec-configs`) puis
`docker restart crowdsec`.

## Pour rapatrier les règles déjà présentes sur le serveur

Les règles custom existantes sur le serveur ne sont pas encore ici. Pour les
récupérer dans le repo :

```bash
# depuis le serveur — ne copie que les fichiers custom (pas ceux du hub) :
cscli parsers list -o json | jq -r '.parsers[] | select(.status=="enabled,local") | .local_path'
cscli scenarios list -o json | jq -r '.scenarios[] | select(.status=="enabled,local") | .local_path'
# puis copier ces fichiers dans le sous-dossier correspondant du repo
```

## Règles actuellement versionnées

### `appsec-configs/ente-s3-whitelist.yaml` — fix ban Ente / S3

```
AppSec / WAF — Cible : s3.ffd.link
Règle : native_rule:901340 — Zone : REQBODY_PROCESSOR ("Enabling body inspection")
```

Les clients Ente utilisent des URLs S3 pré-signées (`X-Amz-Signature=...`) ;
la règle CRS **901340** — une règle d'*initialisation* (`phase:1`, action
`pass`), pas de détection — est comptée à tort comme un match bloquant par le
moteur AppSec → ban. La config la retire du moteur in-band via un hook
`on_load` (`RemoveInBandRuleByID(901340)`), sans toucher aux autres règles
CRS. Un bloc `on_match` optionnel (commenté) permet de whitelister tout le
host `s3.ffd.link` si d'autres faux positifs apparaissent.

Après déploiement, lever le ban en place :

```bash
cscli decisions list
cscli decisions delete --ip <IP_BANNIE>
```

### `parsers/s02-enrich/mywhitelists.yaml` — IPs de confiance

Whitelist au niveau parsing (LAN/VPN pré-remplis, IP fixe à décommenter) :
les événements de ces sources sont ignorés avant les scénarios.

### `postoverflows/s01-whitelist/mywhitelists.yaml` — dernière chance

Whitelist évaluée après déclenchement d'un scénario, juste avant le ban.
Fournie vide avec des exemples commentés (par scénario, par IP).

## Vérification après déploiement

```bash
sudo journalctl -u crowdsec -n 50 | grep -iE 'appsec|whitelist|error'
cscli parsers list | grep custom
cscli alerts list
```

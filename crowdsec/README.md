# CrowdSec — fix du ban AppSec sur Ente (s3.ffd.link)

## Symptôme

```
AppSec / WAF
Cible : s3.ffd.link
Règle : native_rule:901340
Zone  : REQBODY_PROCESSOR — "Enabling body inspection"
GET /ente-io-1/...?X-Amz-Algorithm=AWS4-HMAC-SHA256&...
```

Les clients Ente utilisent des URLs S3 pré-signées ; la règle CRS **901340**
(qui est une règle d'*initialisation*, pas de détection) est comptée à tort
comme un match par le moteur AppSec de CrowdSec → alerte → ban de l'IP.

## Installation

1. Copier la config de whitelist sur la machine qui fait tourner CrowdSec :

   ```bash
   sudo cp appsec-configs/ente-s3-whitelist.yaml /etc/crowdsec/appsec-configs/
   ```

   (En Docker : monter le fichier dans `/etc/crowdsec/appsec-configs/`.)

2. Charger cette config **en plus** de la config AppSec existante, dans le
   fichier d'acquisition AppSec (ex. `/etc/crowdsec/acquis.d/appsec.yaml`) —
   remplacer la clé `appsec_config` (singulier) par `appsec_configs` (pluriel) :

   ```yaml
   listen_addr: 0.0.0.0:7422
   source: appsec
   appsec_configs:
     - crowdsecurity/appsec-default   # ← garder votre config actuelle
     - custom/ente-s3-whitelist
   labels:
     type: appsec
   ```

3. Redémarrer CrowdSec :

   ```bash
   sudo systemctl restart crowdsec
   # ou : docker restart crowdsec
   ```

4. Lever le ban déjà en place :

   ```bash
   cscli decisions list
   cscli decisions delete --ip <IP_BANNIE>
   ```

## Vérification

```bash
# Le moteur doit démarrer sans erreur et charger la config custom
sudo journalctl -u crowdsec -n 50 | grep -i appsec

# Refaire une synchro/un upload Ente, puis vérifier qu'aucune
# nouvelle alerte 901340 n'apparaît :
cscli alerts list
```

## Notes

- `RemoveInBandRuleByID(901340)` ne désactive que cette règle
  d'initialisation ; toutes les autres règles CRS restent actives.
- Ce faux positif a été corrigé dans des versions récentes du hub — un
  `cscli hub update && cscli hub upgrade` peut aussi aider, la whitelist
  reste utile en attendant.
- Si d'autres faux positifs apparaissent sur `s3.ffd.link` (les blobs Ente
  sont du chiffré, donc du binaire aléatoire qui peut matcher des règles
  CRS), décommenter le bloc `on_match` dans
  `appsec-configs/ente-s3-whitelist.yaml` pour whitelister ce host.

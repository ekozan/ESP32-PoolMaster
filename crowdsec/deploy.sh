#!/usr/bin/env bash
# Déploie la config CrowdSec de ce dossier vers /etc/crowdsec.
# Usage : sudo ./deploy.sh [--dry-run]
#
# Ne copie QUE les sous-dossiers versionnés ici (fusion, pas de suppression) :
# la config générée par le hub / cscli et les credentials ne sont pas touchés.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${CROWDSEC_ETC:-/etc/crowdsec}"
RSYNC_OPTS=(-av)
[[ "${1:-}" == "--dry-run" ]] && RSYNC_OPTS+=(--dry-run)

DIRS=(acquis.d appsec-configs appsec-rules parsers scenarios postoverflows)

for d in "${DIRS[@]}"; do
  # ignorer les dossiers vides (seulement .gitkeep)
  if find "$SRC/$d" -type f ! -name .gitkeep | grep -q .; then
    echo "==> $d"
    rsync "${RSYNC_OPTS[@]}" --exclude=.gitkeep "$SRC/$d/" "$DEST/$d/"
  fi
done

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "Dry-run terminé, rien n'a été copié."
  exit 0
fi

echo "==> Redémarrage de CrowdSec"
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet crowdsec; then
  systemctl restart crowdsec
  systemctl status crowdsec --no-pager -l | head -n 5
else
  echo "systemd non détecté : redémarrez le conteneur (ex. docker restart crowdsec)"
fi

#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Construction des images et démarrage du laboratoire
#
#  À exécuter dans un terminal du Codespace (terminal C, « hôte ») :
#        bash scripts/setup.sh
#
#  Le script peut être relancé autant de fois que nécessaire : il démarre
#  chaque serveur dès que les clés et certificats qu'il exige ont été créés
#  par l'élève. IL NE CRÉE AUCUNE CLÉ NI AUCUN CERTIFICAT.
#
#   Toujours démarrés : client, ftp-plain, ssh-weak, ssh-secure, ssh-impostor
#                       (les serveurs SSH créent eux-mêmes leurs clés d'hôte)
#   Si la PKI existe  : ftps-secure, ftps-implicit  (.lab/pki/ca.crt, ftps.crt, ftps.key)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

info()  { printf '\e[36m[INFO]\e[0m %s\n' "$1"; }
ok()    { printf '\e[32m[OK]\e[0m   %s\n' "$1"; }
att()   { printf '\e[33m[EN ATTENTE]\e[0m %s\n' "$1"; }
err()   { printf '\e[31m[ERREUR]\e[0m %s\n' "$1" >&2; }

if ! docker info >/dev/null 2>&1; then
  err "Docker ne répond pas. Lancez d'abord : bash scripts/check_environment.sh"
  exit 1
fi

# 1. Répertoires de travail (vides) : l'élève y créera ses clés.
info "Préparation des répertoires de travail"
mkdir -p .lab/pki .lab/ssh/deploy captures telechargements
chmod 700 .lab/pki 2>/dev/null || true

# 2. Construction des images.
info "Construction des images Docker (3 à 5 minutes la première fois)"
docker compose build

# 3. Services sans prérequis cryptographique.
SERVICES=(client ftp-plain ssh-weak ssh-secure ssh-impostor)

# 4. Services FTPS : ils exigent la CA, le certificat et la clé du serveur
#    créés par l'élève.
if [[ -s .lab/pki/ca.crt && -s .lab/pki/ftps.crt && -s .lab/pki/ftps.key ]]; then
  SERVICES+=(ftps-secure ftps-implicit)
  ok "PKI présente : ftps-secure et ftps-implicit seront démarrés"
else
  att "ftps-secure / ftps-implicit : créez d'abord .lab/pki/ca.crt, ftps.key et ftps.crt (procédure, partie 2)"
fi

# 5. Clé publique de l'élève à autoriser sur ssh-secure (bloc SSH).
if [[ ! -s .lab/ssh/deploy/stagiaire.pub ]]; then
  att "Aucune clé publique utilisateur dans .lab/ssh/deploy/stagiaire.pub (normal avant le bloc SSH)"
fi

# 6. Démarrage (ou mise à jour) des conteneurs.
info "Démarrage : ${SERVICES[*]}"
docker compose up -d "${SERVICES[@]}"

sleep 3
info "État des conteneurs :"
docker compose ps --all --format 'table {{.Service}}\t{{.State}}\t{{.Status}}'

# 7. Conteneurs arrêtés anormalement : afficher la fin de leur journal.
for srv in $(docker compose ps --all --status exited --services 2>/dev/null); do
  err "Le service $srv s'est arrêté. Dernières lignes de son journal :"
  docker compose logs --tail 15 "$srv" >&2 || true
done

cat <<'EOF'

Étapes suivantes :
  - Terminal A (manipulations) : docker compose exec client bash
  - Terminal B (captures)      : docker compose exec client bash
  - Terminal C (ce terminal)   : journaux, ex. docker compose logs -f ftp-plain
  - Contrôle complet           : bash scripts/verifier_lab.sh
EOF

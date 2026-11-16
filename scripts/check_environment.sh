#!/usr/bin/env bash
# =============================================================================
#  check_environment.sh — Contrôle de l'environnement AVANT le TP
#
#  À exécuter dans un terminal du Codespace (terminal « hôte », PAS dans le
#  conteneur client) :      bash scripts/check_environment.sh
#
#  Ce script ne modifie rien : il vérifie seulement que tout est en place.
#  Code de retour : 0 si aucun problème bloquant, 1 sinon.
# =============================================================================
set -u

cd "$(dirname "$0")/.." || exit 1
RACINE=$(pwd)

ERREURS=0
AVERTISSEMENTS=0
ok()    { printf '  \e[32m[OK]\e[0m      %s\n' "$1"; }
avert() { printf '  \e[33m[ATTENTION]\e[0m %s\n' "$1"; AVERTISSEMENTS=$((AVERTISSEMENTS+1)); }
echec() { printf '  \e[31m[ÉCHEC]\e[0m   %s\n' "$1"; [ -n "${2:-}" ] && printf '            → %s\n' "$2"; ERREURS=$((ERREURS+1)); }
titre() { printf '\n\e[1m== %s\e[0m\n' "$1"; }

titre "1. Contexte d'exécution"
if [ -f /.dockerenv ] && [ "$(hostname)" = "client" ]; then
  echec "Ce script est lancé dans le conteneur « client »." \
        "Ouvrez un terminal du Codespace (sans « docker compose exec ») et relancez-le."
fi
if [ "${CODESPACES:-}" = "true" ]; then
  ok "GitHub Codespaces détecté (Codespace : ${CODESPACE_NAME:-inconnu})"
else
  avert "Variable CODESPACES absente : environnement non Codespaces (le TP reste utilisable si Docker fonctionne)."
fi
ok "Répertoire du dépôt : $RACINE"
ok "Utilisateur : $(id -un) (UID $(id -u))"

titre "2. Outils nécessaires"
for outil in bash git docker; do
  if command -v "$outil" >/dev/null 2>&1; then
    ok "$outil présent : $(command -v "$outil")"
  else
    echec "$outil introuvable" "Recréez le Codespace : la configuration .devcontainer installe Docker."
  fi
done
if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose v2 : $(docker compose version --short 2>/dev/null)"
else
  echec "La commande « docker compose » ne fonctionne pas" \
        "Vérifiez la fonctionnalité docker-in-docker dans .devcontainer/devcontainer.json puis reconstruisez le conteneur (Rebuild Container)."
fi

titre "3. Moteur Docker"
if docker info >/dev/null 2>&1; then
  ok "Le démon Docker répond (version serveur $(docker info --format '{{.ServerVersion}}' 2>/dev/null))"
else
  echec "Le démon Docker ne répond pas" \
        "Attendez la fin du démarrage du Codespace (1 à 2 minutes) ou exécutez : sudo service docker start"
fi

titre "4. Espace disque"
LIBRE_KO=$(df -Pk "$RACINE" | awk 'NR==2 {print $4}')
LIBRE_GO=$((LIBRE_KO / 1024 / 1024))
if [ "$LIBRE_GO" -ge 3 ]; then
  ok "Espace libre : ${LIBRE_GO} Go"
else
  avert "Espace libre faible : ${LIBRE_GO} Go (3 Go recommandés). Nettoyage possible : docker system prune"
fi

titre "5. Fichiers du dépôt"
for f in compose.yaml docker/client/Dockerfile docker/ftp/Dockerfile docker/ssh/Dockerfile \
         docker/ftp/conf/plain.conf docker/ftp/conf/explicit.conf docker/ftp/conf/implicit.conf \
         docker/ssh/conf/sshd_weak.conf docker/ssh/conf/sshd_secure.conf docker/ssh/conf/sshd_impostor.conf \
         config/pki/ftps-server.ext config/pki/ftps-server-v2.ext \
         scripts/setup.sh scripts/verifier_lab.sh; do
  if [ -f "$f" ]; then ok "$f"; else echec "$f manquant" "Récupérez une copie complète du dépôt."; fi
done

titre "6. Fichier Compose et sécurité du laboratoire"
if CONFIG=$(docker compose config 2>/dev/null); then
  ok "compose.yaml est syntaxiquement valide"
  if printf '%s\n' "$CONFIG" | grep -qE '^\s+published:'; then
    echec "Au moins un port est PUBLIÉ vers l'extérieur" \
          "Supprimez toute section « ports: » de compose.yaml : les services vulnérables ne doivent jamais être exposés."
  else
    ok "Aucun port publié : les services ne sont pas exposés hors du Codespace"
  fi
  if printf '%s\n' "$CONFIG" | grep -qE '^\s+internal: true'; then
    ok "Le réseau labnet est interne (aucune sortie vers Internet)"
  else
    avert "Le réseau labnet n'est pas déclaré « internal: true »."
  fi
else
  echec "compose.yaml contient une erreur" "Affichez le détail avec : docker compose config"
fi

titre "7. Répertoires de travail de l'élève"
for d in .lab/pki .lab/ssh/deploy captures telechargements; do
  if [ -d "$d" ] && [ -w "$d" ]; then
    ok "$d existe et est accessible en écriture"
  elif [ -d "$d" ]; then
    echec "$d n'est pas accessible en écriture" "sudo chown -R $(id -u):$(id -g) $d"
  else
    avert "$d absent : il sera créé par scripts/setup.sh"
  fi
done
NB_CLES=$(find .lab -type f \( -name '*.key' -o -name '*.crt' \) 2>/dev/null | wc -l)
ok "Clés/certificats déjà créés par l'élève dans .lab : $NB_CLES (normal : 0 au tout début du TP)"

titre "Bilan"
if [ "$ERREURS" -eq 0 ]; then
  printf '  \e[32mEnvironnement prêt\e[0m (%d avertissement(s)). Étape suivante : bash scripts/setup.sh\n' "$AVERTISSEMENTS"
  exit 0
else
  printf '  \e[31m%d problème(s) bloquant(s)\e[0m, %d avertissement(s). Corrigez-les puis relancez ce script.\n' "$ERREURS" "$AVERTISSEMENTS"
  exit 1
fi

#!/usr/bin/env bash
# =============================================================================
#  verifier_lab.sh — Vérification fonctionnelle du laboratoire
#
#  À exécuter dans un terminal du Codespace (terminal C, « hôte ») :
#        bash scripts/verifier_lab.sh
#
#  Les tests réseau sont exécutés DEPUIS le conteneur client (docker compose
#  exec -T client ...), c'est-à-dire depuis le réseau privé du laboratoire.
#  Le script ne modifie aucun fichier de l'élève et ne crée aucune clé.
# =============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

REUSSIS=0; ECHECS=0; IGNORES=0
ok()   { printf '  \e[32m[OK]\e[0m     %s\n' "$1"; REUSSIS=$((REUSSIS+1)); }
ko()   { printf '  \e[31m[ÉCHEC]\e[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '           → %s\n' "$2"; ECHECS=$((ECHECS+1)); }
skip() { printf '  \e[33m[IGNORÉ]\e[0m %s\n' "$1"; IGNORES=$((IGNORES+1)); }
titre(){ printf '\n\e[1m== %s\e[0m\n' "$1"; }
# Exécute une commande dans le conteneur client.
dans_client() { docker compose exec -T client bash -c "$1" 2>&1; }

en_service() { docker compose ps --status running --services 2>/dev/null | grep -qx "$1"; }

titre "1. Conteneurs en fonctionnement"
# Les serveurs FTPS exigent la PKI créée par l'élève (partie 2) : tant
# qu'elle n'existe pas, ils sont signalés « IGNORÉ », pas en échec.
prerequis_absent() {
  case "$1" in
    ftps-secure|ftps-implicit) [ ! -s .lab/pki/ftps.crt ] || [ ! -s .lab/pki/ftps.key ] || [ ! -s .lab/pki/ca.crt ] ;;
    *) return 1 ;;
  esac
}
for srv in client ftp-plain ftps-secure ftps-implicit ssh-weak ssh-secure ssh-impostor; do
  if en_service "$srv"; then ok "$srv est démarré"
  elif prerequis_absent "$srv"; then
    skip "$srv non démarré : PKI pas encore créée (partie 2)"
  else ko "$srv n'est pas démarré" "bash scripts/setup.sh  puis  docker compose logs $srv"; fi
done
en_service client || { echo "Le conteneur client est indispensable aux tests suivants."; exit 1; }

titre "2. Isolement du laboratoire"
RESEAU=$(docker network ls --filter label=com.docker.compose.network=labnet --format '{{.Name}}' | head -1)
if [ -n "$RESEAU" ] && [ "$(docker network inspect -f '{{.Internal}}' "$RESEAU")" = "true" ]; then
  ok "Réseau $RESEAU interne (pas d'accès Internet)"
else
  ko "Le réseau du laboratoire n'est pas interne"
fi
PUBLIES=$(docker compose ps --format '{{.Publishers}}' 2>/dev/null | grep -c 'PublishedPort:[1-9]' || true)
if [ "$PUBLIES" = "0" ]; then ok "Aucun port publié vers l'extérieur"; else ko "$PUBLIES conteneur(s) publient des ports"; fi

titre "3. Résolution des noms (DNS interne de Docker)"
for nom in ftp-plain ftps-secure ftps-implicit ssh-weak ssh-secure ssh-impostor ftps.tp.lan; do
  R=$(dans_client "getent hosts $nom")
  if [ -n "$R" ]; then ok "$(echo "$R" | tr -s ' ')"; else skip "$nom non résolu (service arrêté ?)"; fi
done

titre "4. Ports TCP en écoute"
for cible in ftp-plain:21 ftps-secure:21 ftps-implicit:990 ssh-weak:22 ssh-secure:22 ssh-impostor:22; do
  h=${cible%:*}; p=${cible#*:}
  if ! en_service "$h"; then skip "$cible (service arrêté)"; continue; fi
  if dans_client "nc -z -w 3 $h $p" >/dev/null; then ok "$cible accepte les connexions"
  else ko "$cible ne répond pas" "docker compose logs $h"; fi
done

titre "5. FTP non chiffré (ftp-plain)"
if en_service ftp-plain; then
  B=$(dans_client "python3 -c \"from ftplib import FTP; print(FTP('ftp-plain', timeout=5).getwelcome())\"")
  [[ "$B" == 220* ]] && ok "Bannière reçue : $B" || ko "Bannière FTP inattendue : $B"
fi

titre "6. Certificats (PKI de l'élève)"
if [ -s .lab/pki/ca.crt ] && [ -s .lab/pki/ftps.crt ] && [ -s .lab/pki/ftps.key ]; then
  V=$(dans_client "openssl verify -CAfile .lab/pki/ca.crt .lab/pki/ftps.crt")
  [[ "$V" == *": OK" ]] && ok "ftps.crt est signé par la CA locale" || ko "Chaîne de confiance invalide : $V"
  SAN=$(dans_client "openssl x509 -in .lab/pki/ftps.crt -noout -ext subjectAltName | tail -1")
  if [[ "$SAN" == *"DNS:ftps-secure"* && "$SAN" == *"DNS:ftps-implicit"* ]]; then
    ok "SAN conforme aux noms Docker :$SAN"
  else
    ko "SAN incomplet :$SAN" "Le SAN doit contenir DNS:ftps-secure et DNS:ftps-implicit"
  fi
  P1=$(dans_client "openssl x509 -in .lab/pki/ftps.crt -noout -pubkey | sha256sum")
  P2=$(dans_client "openssl pkey -in .lab/pki/ftps.key -pubout | sha256sum")
  [ "$P1" = "$P2" ] && ok "La clé privée correspond au certificat" || ko "ftps.key ne correspond pas à ftps.crt"
  for f in ca.crt ftps.crt; do
    if dans_client "openssl x509 -in .lab/pki/$f -noout -checkend 3600" >/dev/null; then ok "$f valide encore au moins 1 heure"
    else ko "$f expire dans moins d'une heure ou est expiré" "Recréez-le (procédure, partie 2)"; fi
  done
  M=$(stat -c '%a' .lab/pki/ca.key 2>/dev/null || echo "?")
  [ "$M" = "600" ] && ok "ca.key protégée (mode 600)" || ko "ca.key a le mode $M" "chmod 600 .lab/pki/ca.key"
else
  skip "PKI absente (.lab/pki/ca.crt, ftps.crt, ftps.key)"
fi

titre "7. FTPS explicite (ftps-secure:21) et implicite (ftps-implicit:990)"
if en_service ftps-secure; then
  R=$(dans_client "openssl s_client -connect ftps-secure:21 -starttls ftp -CAfile .lab/pki/ca.crt -verify_hostname ftps-secure -verify_return_error -brief </dev/null")
  if [[ "$R" == *"Verification: OK"* ]]; then ok "AUTH TLS + certificat validé ($(echo "$R" | grep -m1 'Protocol version' | sed 's/.*: //'))"
  else ko "Échec TLS sur ftps-secure" "$(echo "$R" | grep -m1 -i error)"; fi
  R=$(dans_client "openssl s_client -connect ftps-secure:21 -starttls ftp -tls1_1 -cipher DEFAULT@SECLEVEL=0 </dev/null")
  [[ "$R" == *"alert protocol version"* || "$R" == *"no protocols available"* ]] && ok "TLS 1.1 refusé par ftps-secure" || ko "TLS 1.1 semble accepté"
  R=$(dans_client "python3 -c \"
from ftplib import FTP
f = FTP('ftps-secure', timeout=5)
try:
    f.login('stagiaire', 'demo-ftps-456')
except Exception as e:
    print(e)
\"")
  [[ "$R" == 530* ]] && ok "Authentification en clair refusée : $R" || ko "Réponse inattendue à une authentification en clair : $R"
else skip "ftps-secure arrêté"; fi
if en_service ftps-implicit; then
  R=$(dans_client "openssl s_client -connect ftps-implicit:990 -CAfile .lab/pki/ca.crt -verify_hostname ftps-implicit -verify_return_error -brief </dev/null")
  [[ "$R" == *"Verification: OK"* ]] && ok "TLS immédiat sur 990 + certificat validé" || ko "Échec TLS sur ftps-implicit:990" "$(echo "$R" | grep -m1 -i error)"
else skip "ftps-implicit arrêté"; fi

titre "8. SSH : clés d'hôte"
# L'empreinte annoncée sur le réseau (ssh-keyscan, depuis le client) doit être
# celle de la clé réellement stockée sur le serveur (lue par l'administrateur).
declare -A EMPREINTE
for srv in ssh-weak ssh-secure ssh-impostor; do
  if ! en_service "$srv"; then skip "$srv arrêté"; continue; fi
  ATTENDU=$(docker compose exec -T "$srv" ssh-keygen -lf /var/lib/lab-hostkeys/ssh_host_ed25519_key.pub 2>/dev/null | cut -d' ' -f2)
  RECU=$(dans_client "ssh-keyscan -t ed25519 $srv 2>/dev/null | ssh-keygen -lf - | cut -d' ' -f2")
  EMPREINTE[$srv]=$RECU
  if [ -n "$RECU" ] && [ "$ATTENDU" = "$RECU" ]; then ok "$srv : empreinte $RECU"
  else ko "$srv : empreinte reçue « $RECU » ≠ clé du serveur « $ATTENDU »" "docker compose restart $srv"; fi
done
if [ -n "${EMPREINTE[ssh-secure]:-}" ] && [ -n "${EMPREINTE[ssh-impostor]:-}" ]; then
  if [ "${EMPREINTE[ssh-secure]}" = "${EMPREINTE[ssh-impostor]}" ]; then
    ko "ssh-secure et ssh-impostor ont la MÊME clé d'hôte" "docker compose down -v puis bash scripts/setup.sh"
  else ok "ssh-secure et ssh-impostor ont des clés d'hôte différentes"; fi
fi

titre "9. SSH : politique d'authentification"
if en_service ssh-secure; then
  R=$(dans_client "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no stagiaire@ssh-secure true")
  [[ "$R" == *"Permission denied (publickey)"* ]] && ok "ssh-secure n'accepte que les clés publiques" || ko "Réponse inattendue : $R"
  [ -s .lab/ssh/deploy/stagiaire.pub ] && ok "Clé publique déployée : $(dans_client 'ssh-keygen -lf .lab/ssh/deploy/stagiaire.pub' | cut -d' ' -f2)" \
    || skip "Pas encore de clé publique dans .lab/ssh/deploy/stagiaire.pub"
fi
if en_service ssh-weak; then
  R=$(dans_client "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no stagiaire@ssh-weak true")
  [[ "$R" == *"publickey,password"* ]] && ok "ssh-weak accepte les mots de passe (faiblesse volontaire)" || ko "Réponse inattendue de ssh-weak : $R"
fi

titre "Bilan"
printf '  Réussis : %d   Échecs : %d   Ignorés : %d\n' "$REUSSIS" "$ECHECS" "$IGNORES"
[ "$ECHECS" -eq 0 ] && exit 0 || exit 1

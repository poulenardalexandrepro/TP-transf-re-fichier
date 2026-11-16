#!/bin/bash
# Démarrage d'un serveur vsftpd du laboratoire.
# VSFTPD_PROFILE = plain | explicit | implicit
# FTP_PASSWORD   = mot de passe du compte « stagiaire »
set -euo pipefail

PROFILE="${VSFTPD_PROFILE:-plain}"
CONF_SRC="/etc/vsftpd-lab/${PROFILE}.conf"
CONF="/etc/vsftpd.conf"

if [[ ! -f "$CONF_SRC" ]]; then
  echo "[ERREUR] Profil vsftpd inconnu : ${PROFILE}" >&2
  exit 1
fi

# Les profils TLS exigent la clé et le certificat créés par l'élève.
if [[ "$PROFILE" != "plain" ]]; then
  for f in /etc/lab-pki/ftps.crt /etc/lab-pki/ftps.key /etc/lab-pki/ca.crt; do
    if [[ ! -s "$f" ]]; then
      echo "[ERREUR] Fichier manquant : ${f#/etc/lab-pki/} dans .lab/pki/" >&2
      echo "         Créez l'autorité de certification puis le certificat du" >&2
      echo "         serveur FTPS (procédure, partie 2), puis relancez :" >&2
      echo "         bash scripts/setup.sh" >&2
      exit 1
    fi
  done
  # Copie de la clé et du certificat avec les droits attendus pour une clé
  # privée de serveur : propriétaire root, lecture réservée (600).
  install -d -o root -g root -m 700 /etc/vsftpd-tls
  install -o root -g root -m 644 /etc/lab-pki/ftps.crt /etc/vsftpd-tls/ftps.crt
  install -o root -g root -m 600 /etc/lab-pki/ftps.key /etc/vsftpd-tls/ftps.key
  if ! openssl x509 -in /etc/vsftpd-tls/ftps.crt -noout -checkend 0 >/dev/null; then
    echo "[AVERTISSEMENT] Le certificat du serveur est EXPIRÉ : les clients refuseront la connexion." >&2
  fi
  echo "[INFO] Certificat présenté par le serveur :"
  openssl x509 -in /etc/vsftpd-tls/ftps.crt -noout -subject -issuer -enddate -ext subjectAltName 2>/dev/null | sed 's/^/        /'
fi

echo "stagiaire:${FTP_PASSWORD:-demo-ftp-123}" | chpasswd

cat /etc/vsftpd-lab/commun.conf "$CONF_SRC" > "$CONF"

# Journal vsftpd recopié en continu sur la sortie standard du conteneur :
# il est ainsi consultable avec « docker compose logs -f <service> ».
touch /var/log/vsftpd.log
echo "[INFO] vsftpd démarre avec le profil « ${PROFILE} »"

# vsftpd ne doit pas être le processus n°1 du conteneur : en mode autonome,
# il interrompt brutalement (erreur de segmentation) lorsqu'il reçoit la fin
# d'un processus enfant qu'il n'a pas créé lui-même (ici « tail »).
# Bash reste donc le processus n°1 et surveille les deux processus.
/usr/sbin/vsftpd "$CONF" &
PID_VSFTPD=$!
tail -F -n 0 /var/log/vsftpd.log &
PID_TAIL=$!
trap 'kill -TERM "$PID_VSFTPD" "$PID_TAIL" 2>/dev/null' TERM INT
wait -n "$PID_VSFTPD" "$PID_TAIL"
CODE=$?
kill -TERM "$PID_VSFTPD" "$PID_TAIL" 2>/dev/null || true
echo "[INFO] vsftpd s'est arrêté (code ${CODE})"
exit "$CODE"

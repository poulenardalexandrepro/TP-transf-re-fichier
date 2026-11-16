# Image commune aux trois serveurs FTP du laboratoire (vsftpd).
# Le profil (plain / explicit / implicit) est choisi au démarrage par la
# variable d'environnement VSFTPD_PROFILE définie dans compose.yaml.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends vsftpd openssl ca-certificates iproute2 \
 && rm -rf /var/lib/apt/lists/*

# Compte utilisé dans le TP. Le mot de passe est fixé au démarrage
# (variable FTP_PASSWORD) : il diffère entre FTP et FTPS.
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -d /home/stagiaire -s /bin/bash stagiaire \
 && mkdir -p /var/run/vsftpd/empty /srv/ftp/public

# Fichiers de démonstration
COPY --chown=stagiaire:stagiaire fichiers/stagiaire/ /home/stagiaire/
COPY fichiers/public/ /srv/ftp/public/
RUN mkdir -p /home/stagiaire/depot && chown stagiaire:stagiaire /home/stagiaire/depot \
 && chown -R root:root /srv/ftp && chmod -R a+rX,go-w /srv/ftp

COPY conf/ /etc/vsftpd-lab/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

EXPOSE 21 990 30000-30009 30100-30109
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

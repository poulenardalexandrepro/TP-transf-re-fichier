# Poste client du laboratoire : outils de manipulation et d'analyse.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python-is-python3 python3-paramiko \
      openssh-client sshpass openssl ca-certificates faketime \
      lftp curl netcat-openbsd \
      tcpdump tshark iproute2 iptables iputils-ping procps \
      sudo less nano vim-tiny file xxd tree bash-completion \
 && rm -rf /var/lib/apt/lists/*

# Compte de travail « etudiant » (UID 1000, comme l'utilisateur de
# Codespaces) : les fichiers créés dans /lab appartiennent à l'élève.
# sudo est autorisé sans mot de passe pour tcpdump, tshark et iptables.
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -m -u 1000 -s /bin/bash etudiant \
 && echo 'etudiant ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/etudiant \
 && chmod 440 /etc/sudoers.d/etudiant

RUN install -d -o etudiant -g etudiant -m 700 /home/etudiant/.ssh

COPY bashrc_lab.sh /etc/profile.d/bashrc_lab.sh
RUN echo '. /etc/profile.d/bashrc_lab.sh' >> /home/etudiant/.bashrc

USER etudiant
WORKDIR /lab
CMD ["sleep", "infinity"]

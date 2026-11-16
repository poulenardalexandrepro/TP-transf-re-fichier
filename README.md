# TP — Transfert de fichiers : fonctionnement des protocoles, failles de sécurité et remédiations

Laboratoire **GitHub Codespaces** pour le BTS SIO (SISR / SLAM) et la préparation du CAPET Informatique.
Protocoles étudiés : **FTP, FTPS explicite, FTPS implicite, SSH, SCP, SFTP**.

Démarche suivie dans chaque atelier :

> exécuter une instruction → observer la réponse du serveur → observer les paquets → comprendre le protocole → constater une faille → appliquer une remédiation → vérifier expérimentalement son efficacité.

La procédure complète (consignes, explications, captures, questions et corrigés) se trouve dans le document Word **`Procedure_TP_Transfert_Fichiers_Securite.docx`**, distribué séparément.

---

## 1. Démarrage rapide

1. Sur la page GitHub du dépôt : **Code → Codespaces → Create codespace on main**.
   (`github.dev`, ouvert avec la touche « . », n'a **pas** de terminal : il ne convient pas.)
2. Attendez l'ouverture de VS Code dans le navigateur, puis ouvrez un terminal : **Terminal → New Terminal** (ou `Ctrl+ù`).
3. Dans ce terminal (terminal **C**, « hôte » du Codespace) :

```bash
bash scripts/check_environment.sh   # contrôle de l'environnement
bash scripts/setup.sh               # construction des images + démarrage
```

4. Ouvrez deux autres terminaux (bouton **+** du panneau Terminal, ou **Split**) et entrez dans le poste client :

```bash
docker compose exec client bash     # terminal A : manipulations
docker compose exec client bash     # terminal B : captures tcpdump / tshark
```

5. Le TP suit la progression du cours en **deux blocs** :
   - **Bloc A — FTP / FTPS** : après la création de la CA et du certificat (procédure, partie 2), relancez `bash scripts/setup.sh` : `ftps-secure` et `ftps-implicit` démarrent ;
   - **Bloc B — SSH / SCP / SFTP** : les serveurs SSH fonctionnent dès le départ (ils créent eux-mêmes leurs clés d'hôte) ; l'élève ne crée que **sa clé utilisateur**, au moment du cours sur SSH.

   `bash scripts/verifier_lab.sh` peut être lancé à tout moment : `ftps-secure` et `ftps-implicit` sont signalés `[IGNORÉ]` tant que la PKI n'existe pas.

| Terminal | Où ?                                | Rôle                                                             |
|----------|-------------------------------------|------------------------------------------------------------------|
| A        | `docker compose exec client bash`   | Commandes client : `python -q`, `openssl`, `ssh`, `scp`, `sftp`… |
| B        | `docker compose exec client bash`   | Observation du trafic : `sudo tcpdump …`, `tshark …`             |
| C        | Terminal du Codespace (hôte)        | Scripts, `docker compose logs -f <service>`, `docker compose restart …` |

---

## 2. Architecture

```
                      Réseau Docker privé « labnet » 172.30.89.0/24 (internal: true)
 ┌────────────┐
 │  client    │ .100  ── python3 (ftplib, ssl, paramiko), openssl, ssh/scp/sftp,
 │ (etudiant) │          lftp, curl, tcpdump, tshark, ss, iptables
 └─────┬──────┘
       │
 ┌─────┴──────┬──────────────┬───────────────┬────────────┬─────────────┬──────────────┐
 │ ftp-plain  │ ftps-secure  │ ftps-implicit │ ssh-weak   │ ssh-secure  │ ssh-impostor │
 │ .10  21/tcp│ .11  21/tcp  │ .12  990/tcp  │ .20 22/tcp │ .21 22/tcp  │ .22 22/tcp   │
 │ vsftpd     │ vsftpd + TLS │ vsftpd + TLS  │ OpenSSH    │ OpenSSH     │ OpenSSH      │
 └────────────┴──────────────┴───────────────┴────────────┴─────────────┴──────────────┘
```

* Aucun service ne publie de port (`ports:` absent de `compose.yaml`) : rien n'est joignable depuis Internet.
* Le réseau est `internal: true` : les conteneurs n'ont pas d'accès à Internet.
* Le dépôt est monté dans le client sous **`/lab`** : clés, certificats et captures créés par l'élève apparaissent dans l'explorateur de fichiers du Codespace.
* L'utilisateur du client, `etudiant`, a l'UID 1000 (comme `vscode` dans le Codespace) et peut utiliser `sudo` sans mot de passe pour `tcpdump`, `tshark` et `iptables`.

### Pourquoi les noms Docker servent de noms d'hôtes

Docker Compose crée un réseau utilisateur et fournit à chaque conteneur un **serveur DNS interne** (`127.0.0.11`). Ce serveur résout le **nom de chaque service** (et ses éventuels alias) en l'adresse IP du conteneur sur ce réseau. Depuis le client :

```bash
getent hosts ftp-plain ftps-secure ssh-secure
# 172.30.89.10    ftp-plain
# 172.30.89.11    ftps-secure
# 172.30.89.21    ssh-secure
```

`getent` interroge les bases de noms du système dans l'ordre défini par `/etc/nsswitch.conf` (`files` = `/etc/hosts`, puis `dns`). La base `hosts` renvoie l'adresse IP associée à chaque nom. **Un nom résolu ne prouve pas que le service écoute** : `nc -zv ftp-plain 22` échoue (`Connection refused`) alors que `ftp-plain` est résolu. Un service arrêté, lui, n'est plus résolu du tout (code de retour 2 de `getent`).

---

## 3. Les conteneurs

### `ftp-plain` — FTP non chiffré

| Élément | Valeur |
|---|---|
| Protocole | FTP (RFC 959) |
| Ports | contrôle **TCP/21** ; données actif depuis **TCP/20** ; passif **30000–30009** |
| Sécurité | **Faible (volontaire)** |
| Vulnérabilités | aucun chiffrement (identifiants, commandes, fichiers en clair) ; accès **anonyme** autorisé à `/srv/ftp/public` (contient un fichier interne déposé par erreur) |
| Protections | chroot des utilisateurs ; 3 échecs d'authentification maximum ; journal du protocole (mot de passe masqué) |
| Compte | `stagiaire` / `demo-ftp-123` ; `anonymous` sans mot de passe |
| Commandes | `python -q` puis `from ftplib import FTP` ; `lftp -u stagiaire ftp-plain` ; `curl -u stagiaire:demo-ftp-123 ftp://ftp-plain/` |

### `ftps-secure` — FTPS explicite

| Élément | Valeur |
|---|---|
| Protocole | FTP + TLS négocié par **`AUTH TLS`** (RFC 4217) |
| Ports | **TCP/21** ; passif **30000–30009** ; alias DNS supplémentaire **`ftps.tp.lan`** |
| Sécurité | **Renforcée** |
| Vulnérabilités volontaires | l'alias `ftps.tp.lan` est absent du SAN initial (étude de cas) ; `require_ssl_reuse=NO` (compatibilité avec `ftplib`, voir procédure) |
| Protections | authentification **et** données chiffrées obligatoires (`force_local_logins_ssl`, `force_local_data_ssl` → `530` / `522` sinon) ; TLS 1.2 et 1.3 uniquement ; suites ECDHE + AEAD ; pas d'anonyme |
| Compte | `stagiaire` / `demo-ftps-456` |
| Certificat | `.lab/pki/ftps.crt` + `.lab/pki/ftps.key`, **créés par l'élève**, signés par sa CA locale `.lab/pki/ca.crt` |
| Commandes | `ftplib.FTP_TLS` ; `openssl s_client -connect ftps-secure:21 -starttls ftp -CAfile .lab/pki/ca.crt` ; `curl --ssl-reqd --cacert .lab/pki/ca.crt ftp://ftps-secure/` |

### `ftps-implicit` — FTPS implicite

| Élément | Valeur |
|---|---|
| Protocole | FTP dans TLS établi **dès la connexion** |
| Ports | **TCP/990** ; passif **30100–30109** |
| Sécurité | **Renforcée** (mêmes protections que `ftps-secure`) |
| Compte / certificat | identiques à `ftps-secure` (le SAN contient les deux noms) |
| Commandes | `socket` + `ssl.SSLContext.wrap_socket` + `ftplib.FTP_TLS` ; `openssl s_client -connect ftps-implicit:990 -CAfile .lab/pki/ca.crt` ; `curl --cacert .lab/pki/ca.crt ftps://ftps-implicit/` |

### `ssh-weak` — SSH mal configuré

| Élément | Valeur |
|---|---|
| Protocole | SSH-2 (OpenSSH 9.6) — SFTP disponible |
| Port | **TCP/22** |
| Sécurité | **Faible (volontaire)** |
| Vulnérabilités | `PermitRootLogin yes` ; mots de passe faibles ; 10 essais par connexion ; `StrictModes no` ; redirections autorisées ; `LogLevel QUIET` (aucune trace) |
| Comptes | `stagiaire` / `azerty` ; `root` / `toor` |
| Clés d'hôte | générées par le serveur au premier démarrage (volume `ssh-weak-hostkeys`) |
| Commandes | `ssh stagiaire@ssh-weak` ; `ssh-copy-id` ; `paramiko` |

### `ssh-secure` — SSH durci

| Élément | Valeur |
|---|---|
| Port | **TCP/22** |
| Sécurité | **Renforcée** |
| Protections | clé publique **uniquement** ; `root` interdit ; `AllowUsers stagiaire depot` ; `MaxAuthTries 3` ; `StrictModes yes` ; algorithmes modernes (sntrup761x25519, curve25519, chacha20-poly1305, AES-GCM/CTR, HMAC-SHA2) ; aucune redirection ; `LogLevel VERBOSE` ; compte `depot` limité à SFTP et enfermé dans `/srv/sftp-depot` |
| Clé d'hôte | générée par le serveur au premier démarrage (volume `ssh-secure-hostkeys`) ; empreinte affichée par `docker compose logs ssh-secure` |
| Clé utilisateur autorisée | `.lab/ssh/deploy/stagiaire.pub` (copiée au démarrage dans `authorized_keys` de `stagiaire` et `depot`) — après modification : `docker compose restart ssh-secure` |
| Commandes | `ssh`, `scp`, `sftp`, `paramiko` |

### `ssh-impostor` — serveur usurpateur

| Élément | Valeur |
|---|---|
| Port | **TCP/22** |
| Rôle | se faire passer pour `ssh-secure` avec une **autre clé d'hôte** |
| Vulnérabilité démontrée | si l'utilisateur ignore l'alerte de clé d'hôte et saisit son mot de passe, l'imposteur l'**intercepte** (journal : `[IMPOSTEUR] Mot de passe intercepté…`) |
| Clé d'hôte | générée par le serveur lui-même, donc **différente** de celle de `ssh-secure` (volume `ssh-impostor-hostkeys`) |
| Commandes | usurpation DNS simulée dans `/etc/hosts` du client, ou `ssh -o HostKeyAlias=ssh-secure stagiaire@ssh-impostor` |

### `client` — poste de l'élève

Outils : `python3` (`ftplib`, `ssl`, `socket`, `paramiko`), `openssl`, `ssh`, `scp`, `sftp`, `ssh-keygen`, `ssh-keyscan`, `sshpass`, `lftp`, `curl`, `nc`, `tcpdump`, `tshark`, `ss`, `iptables`, `faketime`.
Capacités Docker : `NET_RAW` (captures) et `NET_ADMIN` (simulation de pare-feu, limitée au conteneur client).

---

## 4. Scripts

| Script | Où l'exécuter | Rôle |
|---|---|---|
| `scripts/check_environment.sh` | terminal C | Vérifie Codespaces, Docker, Compose, espace disque, fichiers, absence de ports publiés, réseau interne, droits sur `.lab/` |
| `scripts/setup.sh` | terminal C | Crée les répertoires vides, construit les images, démarre les services ; `ftps-secure` et `ftps-implicit` seulement si la PKI existe : à relancer après la partie 2 |
| `scripts/verifier_lab.sh` | terminal C | Tests fonctionnels depuis le client : DNS, ports, bannières, chaîne de certificats, SAN, TLS 1.1 refusé, empreintes SSH, politique d'authentification ; les serveurs dont les clés ne sont pas encore créées sont « IGNORÉS » |

**Aucun script ne crée la PKI ni la clé utilisateur** : l'élève les produit lui-même avec `openssl` (CA et certificat FTPS) et `ssh-keygen` (sa clé SSH). Les serveurs SSH, eux, génèrent leurs clés d'hôte comme lors d'une installation d'OpenSSH.

---

## 5. Arborescence

```
.devcontainer/devcontainer.json    Codespace Ubuntu 24.04 + Docker (docker-in-docker)
compose.yaml                       7 services, réseau privé labnet, aucun port publié
docker/client/                     Image du poste client
docker/ftp/                        Image vsftpd + profils plain / explicit / implicit + fichiers de démonstration
docker/ssh/                        Image OpenSSH + profils weak / secure / impostor
config/pki/ftps-server.ext         Extensions X.509 du certificat serveur (SAN : ftps-secure, ftps-implicit)
config/pki/ftps-server-v2.ext      Version corrigée (ajout de ftps.tp.lan)
ressources/client/a_envoyer/       Fichiers à téléverser (STOR, scp, put)
scripts/                           check_environment.sh, setup.sh, verifier_lab.sh
.lab/pki/                          (vide) CA, clé, CSR et certificat créés par l'élève
.lab/ssh/deploy/                   (vide) clé publique de l'élève à autoriser sur ssh-secure
captures/                          (vide) fichiers PCAP
telechargements/                   (vide) fichiers récupérés
```

Le contenu de `.lab/`, `captures/` et `telechargements/` est exclu de Git (`.gitignore`) : **ne versionnez jamais de clé privée**.

---

## 6. Remise à zéro

```bash
docker compose down -v                       # supprime conteneurs, réseau et volumes
rm -f .lab/pki/* .lab/ssh/deploy/*.pub captures/*.pcap telechargements/*
```

Ces commandes n'agissent que dans le dépôt du laboratoire.

## 7. Problèmes fréquents

| Symptôme | Cause | Solution |
|---|---|---|
| `Cannot connect to the Docker daemon` | Codespace encore en démarrage | Patienter, puis `sudo service docker start` si besoin |
| `ftps-secure` absent de `docker compose ps` | PKI absente ou incomplète | Créer `ca.crt`, `ftps.key`, `ftps.crt`, puis `bash scripts/setup.sh` ; lire `docker compose logs ftps-secure` |
| `CERTIFICATE_VERIFY_FAILED … certificate has expired` | CA ou certificat créés il y a plus de 7 jours | Recréer la CA et le certificat (procédure, partie 2), puis `docker compose restart ftps-secure ftps-implicit` |
| `Hostname mismatch` | Nom utilisé absent du SAN | Utiliser `ftps-secure` / `ftps-implicit`, ou réémettre le certificat avec `ftps-server-v2.ext` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` (hors exercice) | Volumes de clés d'hôte supprimés (`down -v`) : nouvelles clés | Vérifier l'empreinte (`docker compose logs <serveur>`), puis `ssh-keygen -R <serveur>` |
| `Permission denied (publickey)` sur `ssh-secure` | Clé non déployée ou phrase de passe non chargée | `cp ~/.ssh/id_ed25519.pub .lab/ssh/deploy/stagiaire.pub` puis (terminal C) `docker compose restart ssh-secure` ; `ssh-add` |
| `tcpdump: … Permission denied` | Lancé sans `sudo` | `sudo tcpdump …` |
| `Temporary failure in name resolution` | Service arrêté | `docker compose ps`, puis `bash scripts/setup.sh` |

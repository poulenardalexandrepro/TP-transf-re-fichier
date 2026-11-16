# Environnement du poste client du laboratoire.
export PS1='\[\e[1;32m\]etudiant@client\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
if [[ $- == *i* ]] && [[ -z "${LAB_BANNIERE_AFFICHEE:-}" ]]; then
  export LAB_BANNIERE_AFFICHEE=1
  echo "Poste client du TP « Transfert de fichiers » — répertoire de travail : /lab"
  echo "Services : ftp-plain ftps-secure ftps-implicit ssh-weak ssh-secure ssh-impostor"
fi
umask 022

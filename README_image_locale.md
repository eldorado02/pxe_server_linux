# Démarrer l'image Docker déjà présente (guide pour non-techniques)

Ce guide explique, pas à pas et en langage simple, comment démarrer le serveur PXE si l'image Docker est déjà présente sur le PC serveur mais n'est pas en cours d'exécution (par exemple après un redémarrage du serveur).

Important : ce guide suppose que l'image s'appelle `pxe_server` et qu'elle est déjà disponible localement sur le serveur.

Avant de commencer
- Assurez-vous que le serveur est allumé et que vous pouvez ouvrir un terminal (ou vous connecter via SSH).
- Vérifiez que Docker est installé :

```bash
docker --version
```

Si la commande renvoie une version (par ex. `Docker version 20.x.x`), Docker est installé. Si la commande n'existe pas, contactez la personne technique.

Vérifier que l'image est présente
1. Ouvrez un terminal.
2. Allez dans le dossier où se trouve ce projet (exemple) :

```bash
cd /chemin/vers/le/dossier/du-projet
# Exemple : cd /home/monuser/Projects/pxe_server_linux
```

3. Vérifiez la présence de l'image :

```bash
docker image ls | grep pxe_server || echo "Image 'pxe_server' introuvable"
```

Si vous voyez une ligne contenant `pxe_server`, l'image est présente. Si vous voyez `Image 'pxe_server' introuvable`, contactez le support technique — ne continuez pas.

Démarrer le serveur (très simple)
1. Depuis le dossier du projet, lancez le script de démarrage :

```bash
./run.sh
```

2. Si le script refuse de s'exécuter (permission refusée), tapez :

```bash
chmod +x run.sh
./run.sh
# OU
bash run.sh
```

3. Si Docker demande des droits, essayez avec `sudo` :

```bash
sudo ./run.sh
```

Ce que vous verrez après démarrage
- Le script affiche des lignes comme "=== Serveur PXE démarré ! ===".
- Les rapports sont sauvegardés dans un dossier (le script affiche le chemin). Vous pouvez lister les rapports :

```bash
# Remplacez par le chemin affiché par le script si différent
ls $HOME/rapports_wipe
```

Commandes utiles (copier-coller)
- Voir les logs en direct :

```bash
docker logs -f pxe
```

- Entrer dans le conteneur (pour une personne technique seulement) :

```bash
docker exec -it pxe bash
```

- Arrêter le serveur :

```bash
docker stop pxe
```

Si quelque chose ne fonctionne pas
- Si l'image n'est pas trouvée, n'essayez pas de reconstruire vous-même : contactez la personne technique responsable.
- Si Docker n'est pas installé ou si les commandes demandent un mot de passe, demandez l'aide du support.

Notes pour la personne qui va lancer
- Suivez les étapes exactement dans l'ordre : vérifier Docker, vérifier l'image, exécuter `./run.sh`.
- Ne modifiez pas le script ou les fichiers du dossier si vous n'êtes pas sûr de ce que vous faites.

Fichier de référence : le script de lancement utilisé est [run.sh](run.sh#L1-L50)

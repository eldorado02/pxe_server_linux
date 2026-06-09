# Démarrer l'image Docker déjà présente (guide pour non-techniques)

Ce guide explique, pas à pas et en langage simple, comment démarrer le serveur PXE si l'image Docker est déjà présente sur le PC serveur mais n'est pas en cours d'exécution (par exemple après un redémarrage du serveur).

> **Important :** ce guide suppose que l'image s'appelle `pxe_server` et qu'elle est déjà disponible localement sur le serveur.

---

## Partie 1 — Côté CLIENT (PC à effacer) : configuration du BIOS

Avant de pouvoir démarrer un PC client via le réseau (PXE), il faut configurer son BIOS pour :
1. **Activer le démarrage réseau (Network Boot / PXE Boot)**
2. **Désactiver le Secure Boot**

> ⚠️ **Attention :** ces réglages doivent être effectués sur **chaque PC client**, pas sur le serveur.

---

### 1.1 — Entrer dans le BIOS

Dès que le PC démarre (avant que Windows ou Linux se lance), appuyez **rapidement et à plusieurs reprises** sur la touche d'accès au BIOS :

| Marque / Modèle         | Touche(s) BIOS         | Notes                                     |
|-------------------------|------------------------|-------------------------------------------|
| **Fujitsu** (tous modèles) | `F2` ou `Del`       | Appuyez dès l'apparition du logo Fujitsu  |
| **HP**                  | `F10` ou `Esc`         | Puis `F10` pour entrer dans Setup         |
| **Dell**                | `F2` ou `Del`          |                                           |
| **Lenovo**              | `F1`, `F2` ou `Enter`  | Parfois `Fn+F2`                           |
| **Acer**                | `F2` ou `Del`          |                                           |
| **Asus**                | `F2` ou `Del`          |                                           |
| **Toshiba / Dynabook**  | `F2`                   |                                           |
| **Autre / inconnu**     | `Del`, `F2` ou `F12`   | Essayez l'une après l'autre au démarrage  |

> 💡 Si vous ratez la fenêtre, éteignez et rallumez le PC, puis réessayez immédiatement.

---

### 1.2 — Désactiver le Secure Boot

Le **Secure Boot** empêche le démarrage via le réseau PXE. Il faut le **désactiver**.

#### Sur Fujitsu (LIFEBOOK, ESPRIMO, CELSIUS, etc.)

1. Dans le BIOS, allez dans l'onglet **`Security`** (avec les touches ← →).
2. Cherchez l'option **`Secure Boot`** ou **`Secure Boot Control`**.
3. Passez-la à **`Disabled`** (avec Entrée ou +/–).
4. Confirmez si une boîte de dialogue apparaît.

#### Sur HP

1. Allez dans **`Security`** → **`Secure Boot Configuration`**.
2. Décochez ou mettez à **`Disable`** l'option **`Secure Boot`**.

#### Sur Dell

1. Allez dans **`Secure Boot`** → **`Secure Boot Enable`**.
2. Décochez la case ou sélectionnez **`Disabled`**.

#### Sur Lenovo

1. Allez dans **`Security`** → **`Secure Boot`**.
2. Mettez à **`Disabled`**.

#### Règle générale (toutes marques)
- Cherchez un onglet ou menu nommé **Security**, **Boot**, ou **Authentication**.
- Repérez **Secure Boot** et mettez-le sur **Disabled**.

---

### 1.3 — Activer le démarrage réseau (Network Boot / PXE)

#### Sur Fujitsu

1. Dans le BIOS, allez dans l'onglet **`Boot`**.
2. Cherchez **`Boot Option Priorities`** ou **`Boot Device Priority`**.
3. Cherchez une entrée nommée **`Network`**, **`LAN`**, **`PXE`**, ou **`Onboard LAN`**.
4. Montez cette entrée **en première position** (avec `+` ou `F6`, selon le modèle).
5. Si vous ne voyez pas l'option réseau dans la liste :
   - Allez dans **`Advanced`** → **`Network Stack`** → activez **`Network Stack`**, **`IPv4 PXE Support`** (et/ou **`IPv6 PXE Support`**).
   - Revenez dans **`Boot`** pour vérifier que l'entrée réseau est maintenant visible.

#### Sur HP

1. Allez dans **`Advanced`** → **`Boot Options`**.
2. Cochez **`Network (PXE) Boot`** ou activez **`LAN / Network Boot`**.
3. Dans **`Boot Order`**, montez le réseau en premier.

#### Sur Dell

1. Allez dans **`General`** → **`Boot Sequence`**.
2. Cochez **`Onboard NIC`** ou **`Network`**.
3. Utilisez les flèches pour le mettre en première position.

#### Sur Lenovo

1. Allez dans **`Config`** → **`Network`** → activez **`Wake On LAN`** et **`PXE Boot`**.
2. Dans **`Startup`** → **`Boot`**, montez le réseau en premier.

#### Règle générale (toutes marques)
- Cherchez un onglet **Boot**, **Boot Order**, ou **Startup**.
- Activez **Network / LAN / PXE** et mettez-le **en premier** dans l'ordre de démarrage.

---

### 1.4 — Sauvegarder et redémarrer

1. Appuyez sur **`F10`** (ou allez dans **`Exit`** → **`Save & Exit`**).
2. Confirmez la sauvegarde.
3. Le PC redémarre — il cherchera automatiquement le serveur PXE sur le réseau.

> ✅ Si tout est correct, le PC affichera un écran de chargement réseau (ex. : `PXE-E61`, puis le menu de démarrage PXE du serveur).

---

## Partie 2 — Côté SERVEUR : démarrer l'image Docker

### Avant de commencer

- Assurez-vous que le serveur est allumé et que vous pouvez ouvrir un terminal (ou vous connecter via SSH).
- Vérifiez que Docker est installé :

```bash
docker --version
```

Si la commande renvoie une version (par ex. `Docker version 20.x.x`), Docker est installé. Sinon, contactez la personne technique.

---

### Vérifier que l'image est présente

1. Ouvrez un terminal.
2. Allez dans le dossier où se trouve ce projet :

```bash
cd /chemin/vers/le/dossier/du-projet
# Exemple : cd /home/monuser/Projects/pxe_server_linux
```

3. Vérifiez la présence de l'image :

```bash
docker image ls | grep pxe_server || echo "Image 'pxe_server' introuvable"
```

Si vous voyez une ligne contenant `pxe_server`, l'image est présente. Si vous voyez `Image 'pxe_server' introuvable`, contactez le support technique — ne continuez pas.

---

### Démarrer le serveur

1. Depuis le dossier du projet, lancez le script de démarrage :

```bash
./run.sh
```

2. Si le script refuse de s'exécuter (permission refusée) :

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

---

### Ce que vous verrez après démarrage

- Le script affiche des lignes comme `=== Serveur PXE démarré ! ===`.
- Les rapports sont sauvegardés dans un dossier (le script affiche le chemin). Vous pouvez lister les rapports :

```bash
# Remplacez par le chemin affiché par le script si différent
ls $HOME/rapports_wipe
```

---

### Commandes utiles (copier-coller)

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

---

### Si quelque chose ne fonctionne pas

- Si l'image n'est pas trouvée, n'essayez pas de reconstruire vous-même : contactez la personne technique responsable.
- Si Docker n'est pas installé ou si les commandes demandent un mot de passe, demandez l'aide du support.
- Si le PC client ne trouve pas le serveur PXE, vérifiez que :
  - Le câble réseau est bien branché sur le PC client.
  - Le serveur Docker est bien démarré (étapes ci-dessus).
  - Le PC client est sur le même réseau (même switch/routeur) que le serveur.

---

### Notes pour la personne qui va lancer

- Suivez les étapes exactement dans l'ordre : vérifier Docker, vérifier l'image, exécuter `./run.sh`.
- Ne modifiez pas le script ou les fichiers du dossier si vous n'êtes pas sûr de ce que vous faites.

---

Fichier de référence : le script de lancement utilisé est [run.sh](run.sh#L1-L50)

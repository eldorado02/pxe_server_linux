# 🖥️ Serveur PXE — Effacement Sécurisé de PC

Ce système permet d'effacer de manière définitive et sécurisée les disques durs de plusieurs ordinateurs en même temps, via le réseau (sans avoir besoin de brancher de clé USB sur chaque ordinateur).

Il utilise actuellement la méthode **Zero (1 passe)** pour un effacement rapide et efficace, et génère automatiquement un **certificat PDF** professionnel avec le nom de votre entreprise à la fin de chaque effacement.

---

## 🛠️ Configuration Initiale (À faire une seule fois)

Avant d'utiliser le système pour la première fois, vous devez faire deux choses :

1. **Le fichier système :** Assurez-vous d'avoir téléchargé l'image Debian Live (`debian-live-13.5.0-amd64-gnome.iso`) et de l'avoir placée dans le même dossier que ce projet.
2. **Vos informations d'entreprise :** Ouvrez le fichier `nwipe.conf` avec un éditeur de texte simple et remplacez les informations par défaut (Nom, Adresse, Téléphone). Ces informations s'afficheront en en-tête de vos certificats d'effacement ! Vous pouvez aussi modifier `nwipe_customers.csv` pour indiquer un client par défaut.

---

## 🚀 Comment lancer le système (Côté Serveur)

Sur l'ordinateur "Maître" (le serveur) :

1. **Préparer le système** (à faire une fois, ou après avoir modifié `nwipe.conf`) :
   Ouvrez un terminal dans le dossier du projet et tapez :
   ```bash
   bash build.sh
   ```
   *(Patientez, cette étape prépare le système et peut prendre de 20 à 40 minutes).*

2. **Démarrer le serveur** :
   ```bash
   bash run.sh
   ```
   Voilà ! Le serveur est allumé et prêt à accueillir les PC à effacer.

---

## 💻 Comment effacer un PC (Côté Client)

Pour chaque ordinateur que vous souhaitez vider, suivez ces étapes :

1. Branchez le PC au réseau avec un câble (Ethernet).
2. Allumez le PC et tapotez la touche pour entrer dans le **BIOS** (souvent `F2`, `F12`, `Suppr` ou `Entrée` selon la marque du PC).
3. Allez dans le menu de démarrage (Boot priority) et placez le **Démarrage Réseau (PXE / Network Boot)** en **première position**.
4. *(Si le PC refuse de démarrer, cherchez une option "Secure Boot" et désactivez-la).*
5. Sauvegardez et redémarrez le PC.

**C'est tout !** Le PC va démarrer sur le réseau, lancer l'effacement, créer le certificat PDF, l'envoyer sur le serveur, puis **s'éteindre tout seul**.

---

## 📁 Où retrouver les certificats PDF ?

Une fois qu'un ordinateur s'est éteint de lui-même, son effacement est terminé. 

Vous retrouverez ses certificats sur l'ordinateur serveur dans le dossier suivant :
👉 `~/rapports_wipe/`

Ils sont automatiquement rangés **par date** puis **par numéro de série de l'ordinateur** :

```text
rapports_wipe/
└── 2026_06_02/                          ← Date du jour
    ├── DSBX044852/                      ← Numéro de série du 1er PC
    │   ├── nwipe_2026_06_02_DSBX044852.pdf       ← Le certificat officiel
    │   └── old_rapport_2026_06_02_DSBX044852.pdf ← Le rapport secondaire
    │
    └── YMDC091241/                      ← Numéro de série du 2ème PC
        ├── nwipe_2026_06_02_YMDC091241.pdf
        └── old_rapport_2026_06_02_YMDC091241.pdf
```

*(Nous avons simplifié ce dossier : il ne contient plus de fichiers de code indéchiffrables, uniquement les PDF prêts à être remis à vos clients).*

---

## ❓ Commandes utiles (Pour s'arrêter)

Si vous avez terminé votre journée d'effacements, vous pouvez éteindre le serveur avec la commande suivante dans le terminal :

```bash
docker stop pxe
```

*(Pour rallumer le serveur le lendemain, il suffira de retaper `bash run.sh` !)*

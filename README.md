# 🖥️ PXE Server Linux — Effacement sécurisé en masse

Serveur PXE dockerisé permettant d'**effacer simultanément plusieurs PC** via le réseau, selon la norme **DoD 5220.22-M (7 passes)** reconnue par les autorités françaises (ANSSI / douane).

---

## 📋 Description

Ce projet crée une image Docker qui agit comme un **serveur PXE complet**. Quand un PC client démarre via le réseau (PXE boot) :

1. Le serveur lui envoie une image **Debian Live** modifiée et allégée
2. Le PC client démarre sur ce live boot en mode texte
3. Le script `client_wipe.sh` se lance **automatiquement**
4. Le disque est effacé selon la méthode **DoD 5220.22-M (7 passes)** avec vérification
5. Un **rapport PDF + log** est généré et envoyé automatiquement vers le serveur
6. Le PC client s'éteint tout seul

Plusieurs PC fils peuvent être traités **en parallèle** au même moment.

---

## 🗂️ Structure du projet

```
pxe_server_linux/
├── Dockerfile                              # Image Docker multi-stage (build + serveur PXE)
├── client_wipe.sh                          # Script d'effacement exécuté sur les PC fils
├── entrypoint.sh                           # Point d'entrée du conteneur (DHCP, TFTP, NFS, SSH)
├── build.sh                                # Script de build de l'image Docker
├── run.sh                                  # Script de lancement du conteneur
├── rapports/                               # Dossier de réception qui contient des exemples des rapports d'effacement
└── debian-live-13.5.0-amd64-gnome.iso     # ⚠️ ISO Debian Live (voir section ci-dessous)
```

---

## ⚠️ Prérequis obligatoire — ISO Debian Live

**Avant de builder l'image**, vous devez placer l'ISO Debian Live dans le **même dossier que le Dockerfile** :

```
debian-live-13.5.0-amd64-gnome.iso
```

Le nom du fichier doit être **exactement** :
```
debian-live-13.5.0-amd64-gnome.iso
```

> 💡 Téléchargeable sur [https://www.debian.org/CD/live/](https://www.debian.org/CD/live/)  
> Choisir : **Debian 13 (trixie)** → **amd64** → **gnome**

L'ISO fait environ **3,5 Go**. Le Dockerfile l'extrait, la dégraisse (suppression GNOME, Firefox, sons, etc.) et réinjecte nwipe + le script d'effacement.

---

## 🚀 Lancement rapide

### 1. Prérequis système

- Linux (Ubuntu, Debian…)
- **Docker** installé et démarré
- Être connecté au même réseau local que les PC à effacer

### 2. Placer l'ISO

Copier l'ISO dans le dossier du projet :

```bash
cp /chemin/vers/debian-live-13.5.0-amd64-gnome.iso ./
```

### 3. Builder l'image Docker

```bash
bash build.sh
```

> ⏳ Le build peut prendre **20 à 40 minutes** selon la vitesse de la machine et de la connexion internet (téléchargement des paquets Debian).

### 4. Lancer le serveur PXE

```bash
bash run.sh
```

Le serveur démarre en arrière-plan. Les rapports d'effacement seront sauvegardés dans :
```
~/rapports_wipe/
```

---

## 📊 Méthode d'effacement

| Paramètre        | Valeur                          |
|------------------|---------------------------------|
| **Méthode**      | DoD 5220.22-M (7 passes)        |
| **Vérification** | Activée (dernière passe)        |
| **Outil**        | nwipe                           |
| **Rapport**      | PDF + log horodaté par machine  |
| **Conformité**   | ANSSI / douane française / RGPD |

---

## 📁 Rapports d'effacement

Chaque PC effacé génère automatiquement un dossier de rapport contenant :

- **`nwipe_*.pdf`** — Certificat d'effacement officiel nwipe (avec numéro de série, modèle, méthode, statut)
- **`nwipe_*.log`** — Log complet de l'effacement
- **`old_rapport_*.pdf`** — Rapport PDF secondaire avec résumé et log intégré

Les rapports sont identifiés par l'**adresse MAC** de la machine et **l'horodatage** :
```
~/rapports_wipe/
└── AABBCCDDEEFF_20250601_143022/
    ├── nwipe_AABBCCDDEEFF_20250601_143022.pdf
    ├── nwipe_20250601_143022.log
    └── old_rapport_AABBCCDDEEFF_20250601_143022.pdf
```

---

## 🛠️ Commandes utiles

```bash
# Voir les logs du serveur en temps réel
docker logs -f pxe

# Entrer dans le conteneur
docker exec -it pxe bash

# Voir les rapports reçus
ls ~/rapports_wipe/

# Arrêter le serveur
docker stop pxe

# Supprimer le conteneur (les rapports restent sur l'hôte)
docker rm pxe
```

---

## 🏗️ Architecture technique

```
PC Serveur (Docker)
│
├── dnsmasq     → DHCP + TFTP (boot PXE)
├── NFS server  → Partage du filesystem live (squashfs)
├── SSH server  → Réception des rapports PDF/log des PC fils
│
└── PXE Boot Flow :
    PC fils démarre → reçoit IP via DHCP → charge vmlinuz + initrd
    → monte le filesystem NFS → lance client_wipe.sh → efface →
    → envoie rapport SSH → poweroff
```

---

## 🖥️ Configuration BIOS des PC fils (obligatoire)

Chaque PC à effacer doit être configuré pour **booter sur le réseau en priorité**.

### Accéder au BIOS
Au démarrage du PC, appuyer sur la touche BIOS selon la marque :

| Marque | Touche BIOS | Touche Boot Menu |
|--------|------------|------------------|
| Dell | `F2` | `F12` |
| HP | `F10` ou `Esc` | `F9` |
| Lenovo | `F1` ou `Enter` | `F12` |
| Asus | `F2` ou `Del` | `F8` |
| Acer | `F2` | `F12` |
| Gigabyte | `Del` | `F12` |

### Ordre de boot à configurer

Dans le BIOS, aller dans **Boot** → **Boot Priority** (ou **Boot Order**) et mettre **Network Boot** (ou **LAN / PXE**) en **première position** :

```
1. 🥇 Network Boot (PXE)     ← DOIT être en premier
2.    Disque dur (HDD/SSD)
3.    USB
```

> ⚠️ **IMPORTANT** : Si le Network Boot n'est pas en tête de liste, le PC démarrera sur son disque dur au lieu de booter sur le serveur PXE et **l'effacement ne se lancera pas**.

### Secure Boot

Si le PC ne boote pas malgré le bon ordre, **désactiver le Secure Boot** dans le BIOS :
- BIOS → **Security** → **Secure Boot** → **Disabled**

Sauvegarder les changements (généralement `F10`) et redémarrer.

---

## ❓ Dépannage

**Le PC fils ne boote pas via PXE**
- ✅ Vérifier que **Network Boot est en 1ère position** dans l'ordre de boot du BIOS
- ✅ Vérifier que le **Secure Boot est désactivé** si nécessaire
- S'assurer que le serveur Docker est démarré **avant** d'allumer le PC fils
- Le serveur et le PC fils doivent être sur le **même réseau local** (même switch/routeur)

**L'image ne se build pas**
- Vérifier que l'ISO est présente dans le dossier et porte **exactement** le bon nom
- Vérifier la connexion internet (le build télécharge des paquets Debian)

**Les rapports n'arrivent pas**
- Vérifier les logs du conteneur : `docker logs -f pxe`
- Vérifier que le dossier `~/rapports_wipe/` existe et est accessible en écriture

---

## 📜 Licence

Usage interne — Effacement professionnel de matériel informatique.

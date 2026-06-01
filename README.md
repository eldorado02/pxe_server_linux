# PXE ShredOS - effacement automatique sans intervention

Ce projet fournit un serveur PXE conteneurisé pour booter ShredOS sur les clients, lancer nwipe sans GUI, puis récupérer automatiquement logs et certificats via FTP.

## Flux global

1. Le client démarre en PXE (BIOS/UEFI).
2. Le serveur fournit kernel/initrd via TFTP et le système live via NFS.
3. ShredOS lance nwipe en mode non interactif.
4. Le client envoie les fichiers de sortie en FTP.
5. Le serveur renomme les fichiers en format `MAC_disqueID_date`.
6. Le client s'éteint automatiquement à la fin.

## Prérequis d'exploitation

1. L'utilisateur qui lance le projet doit appartenir au groupe `docker`.
2. Docker Engine + Docker Compose plugin doivent être installés.
3. L'image ShredOS locale est attendue dans le dossier:
	`./shredos-2025.11_28_i686_v0.40_20260204_lite-1/`

Aucune commande `sudo` n'est requise dans le workflow standard.

## Démarrage

```bash
./run.sh start
./run.sh logs
./run.sh health
./run.sh rapports
./run.sh stop
```

## Configuration

Copie recommandée:

```bash
cp .env.example .env
```

Variables principales:

| Variable | Défaut | Rôle |
|---|---|---|
| SHREDOS_SOURCE | local | source image (`local`, `remote`, `auto`) |
| SHREDOS_LOCAL_DIR | ./shredos-2025.11_28_i686_v0.40_20260204_lite-1 | dossier local monté dans le conteneur PXE |
| SHREDOS_LOCAL_PATH | /opt/local-shredos | chemin interne conteneur vers les images |
| NWIPE_METHOD | zero | méthode nwipe (`zero` en test, `dod` en prod) |
| NWIPE_VERIFY | off | vérification (`off`, `last`, `all`) |
| NWIPE_EXTRA_OPTIONS | (vide) | options supplémentaires nwipe |
| RAPPORTS_DIR | ./rapports | stockage persistant des sorties |
| FTP_USER / FTP_PASS | shredreports / ... | compte FTP de réception |

## Profils test et production

### Test (rapide)

```dotenv
NWIPE_METHOD=zero
NWIPE_VERIFY=off
```

### Production (plus long)

```dotenv
NWIPE_METHOD=dod
NWIPE_VERIFY=last
```

## Nommage des rapports

Le service FTP post-traite automatiquement les fichiers reçus pour les renommer sous la forme:

`MAC_disqueID_date.ext`

Exemple:

`52_54_00_ab_cd_ef_nwipe_log_20260527T083001_20260527T083210Z.log`

La MAC est corrélée à partir des leases DHCP (`dnsmasq.leases`) et des traces de transfert FTP.

## Vérification rapide

1. Lancer `./run.sh start`.
2. Vérifier `./run.sh health`.
3. Démarrer un client PXE.
4. Vérifier la présence des fichiers dans `./rapports`.
5. Confirmer le renommage en `MAC_disqueID_date`.

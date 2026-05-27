# PXE ShredOS — Serveur d'effacement automatique

## Architecture

```
Serveur (Docker)                    Clients (réseau)
┌─────────────────────┐             ┌──────────────┐
│  service pxe        │  DHCP/TFTP  │              │
│  - dnsmasq          │ ──────────► │  Boot PXE    │
│  - NFS (ShredOS)    │  NFS        │  ShredOS     │
│  - entrypoint.sh    │ ──────────► │  nwipe zero  │
│                     │             │  (autonuke)  │
│  service ftp        │  FTP        │              │
│  - vsftpd           │ ◄────────── │  PDF + log   │
│  - /rapports        │             │  poweroff    │
└─────────────────────┘             └──────────────┘
```

## Démarrage

```bash
./run.sh start      # build + démarrage
./run.sh stop       # arrêt
./run.sh logs       # logs en temps réel
./run.sh rapports   # liste les PDF reçus
```

## Configuration (.env)

| Variable         | Défaut         | Description                        |
|------------------|----------------|------------------------------------|
| SHREDOS_VERSION  | latest         | Version ShredOS (ex: v2025.11_29…) |
| RAPPORTS_DIR     | ./rapports     | Dossier persistant des rapports    |
| FTP_USER         | shredreports   | Utilisateur FTP                    |
| FTP_PASS         | shredos2025    | Mot de passe FTP                   |

## Ce qui se passe côté client

1. Le PC client boot via PXE → reçoit ShredOS par NFS
2. ShredOS démarre → nwipe lance automatiquement l'effacement zero
3. nwipe génère un PDF natif certifié pour chaque disque effacé
4. ShredOS transfère les PDF + logs vers le serveur FTP via lftp
5. Le PC s'éteint automatiquement

## Rapports

Les PDF nwipe contiennent :
- Modèle et numéro de série du disque
- Méthode d'effacement et nombre de passes
- Statut (succès / erreur)
- Données SMART du disque (pages 2 et 3)
- Horodatage

Les fichiers sont déposés dans `./rapports/` sur le serveur hôte.

## Modifier la méthode d'effacement

Dans `pxe/entrypoint.sh`, modifier l'option `--method=` :

```
--method=zero       # Zéro (1 passe, rapide)
--method=dodshort   # DoD 3 passes
--method=dod        # DoD 7 passes
--method=gutmann    # Gutmann 35 passes
```

Puis redémarrer : `./run.sh stop && ./run.sh start`

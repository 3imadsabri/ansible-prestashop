# Déploiement automatisé de PrestaShop + MySQL avec Ansible

Projet d'évaluation du module **Ansible DevOps** : déployer une boutique e-commerce
[PrestaShop](https://www.prestashop.com/) reliée à une base **MySQL**, à l'aide de
**deux rôles Ansible** distincts orchestrés par un playbook.

## Architecture

```
            ┌────────────────────┐
            │  ansible-master    │   Ansible, inventaire, playbooks
            └─────────┬──────────┘
                SSH   │   (utilisateur liora + clé)
          ┌───────────┴────────────┐
          ▼                        ▼
┌───────────────────┐    3306   ┌───────────────────┐
│ web1  (groupe web)│ ────────► │ db1  (groupe db)  │
│ Apache + PHP 8.1  │           │ MySQL 8           │
│ PrestaShop 8.2.3  │           │ base "prestashop" │
└───────────────────┘           └───────────────────┘
        ▲ 80 (HTTP)
        │
    Navigateur
```

| Rôle | Machine | Ce qu'il fait |
|------|---------|---------------|
| `mysql` | `db` | Installe MySQL, écoute sur le réseau, supprime la base de test et les comptes anonymes, crée la base `prestashop` et un utilisateur autorisé **uniquement depuis les serveurs web** de l'inventaire. |
| `prestashop` | `web` | Installe PHP 8.1 + extensions, Apache (mod_rewrite, virtual host), télécharge PrestaShop 8.2.3, lance l'installateur en ligne de commande vers la base distante, supprime `install/` et renomme le dossier d'administration. |

## Prérequis

- **Machine de contrôle** : Ansible ≥ 2.14 (`ansible --version`) et la collection `community.mysql`
  (installée par `deploy.sh`, ou `ansible-galaxy collection install -r requirements.yml`).
- **Machines cibles** : Ubuntu **22.04** ou **24.04**, accessibles en SSH avec un utilisateur sudo
  (`liora` dans le cours) et une clé privée.
  - Sur Ubuntu 24.04, le rôle ajoute automatiquement le dépôt `ppa:ondrej/php`, car PrestaShop 8.2 exige PHP ≤ 8.1.
- **Accès Internet sortant** depuis le serveur web : GitHub (archive PrestaShop) et
  `i18n.prestashop-project.org` (pack de langue téléchargé par l'installateur).
- **Security Group AWS** (ou pare-feu équivalent) :

  | Port | Source | Usage |
  |------|--------|-------|
  | 22 | machine master | SSH (Ansible) |
  | 80 | 0.0.0.0/0 | Boutique (HTTP) |
  | 3306 | serveur web | MySQL |

## Mise en route

1. **Cloner le projet** sur la machine master :

   ```bash
   git clone <url-du-depot> ansible-prestashop
   cd ansible-prestashop
   ```

2. **Renseigner l'inventaire** `inventaire.yaml` avec les **IP privées** des machines :

   ```yaml
   db:
     hosts:
       db1:
         ansible_host: 172.31.x.x
   web:
     hosts:
       web1:
         ansible_host: 172.31.y.y
         # public_ip: 13.38.z.z   # optionnel
   ```

   Le domaine de la boutique est déterminé automatiquement : variable `public_ip` si elle est
   renseignée, sinon IP publique lue dans les métadonnées EC2, sinon `ansible_host`.

3. **Vérifier la connexion SSH** (clé attendue dans `~/.ansible/key.pem`, voir `group_vars/all/vars.yml`) :

   ```bash
   chmod 600 ~/.ansible/key.pem
   ansible all -m ping
   ```

4. **Changer les mots de passe** dans `group_vars/all/vault.yml`, puis le chiffrer :

   ```bash
   ansible-vault encrypt group_vars/all/vault.yml
   ```

## Lancer le déploiement

Tout en une commande (installe la collection, déploie, teste et enregistre les journaux) :

```bash
./deploy.sh                       # vault non chiffré, sudo sans mot de passe
./deploy.sh -K                    # sudo demande un mot de passe (cas des machines du cours)
./deploy.sh -K --ask-vault-pass   # + vault chiffré
```

`-K` (`--ask-become-pass`) demande le mot de passe sudo de l'utilisateur distant au lancement,
pour ne jamais l'écrire dans le dépôt.

Ou étape par étape :

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml  -K --ask-vault-pass
ansible-playbook tests.yml -K --ask-vault-pass
```

Durée indicative : 5 à 10 minutes (l'installation des données de démonstration est la plus longue).
À la fin, le playbook affiche l'URL de la boutique et du back-office :

```
Boutique    : http://<ip-publique>/
Back-office : http://<ip-publique>/admin-liora/
```

Connexion au back-office : `prestashop_admin_email` / mot de passe `vault_prestashop_admin_password`.

## Tests et journaux

`tests.yml` vérifie que :

- le service MySQL est actif et écoute sur le port 3306 ;
- la base `prestashop` contient les tables de la boutique ;
- Apache est actif et PHP 8.1 est utilisé ;
- **le serveur web se connecte à MySQL** et lit le catalogue ;
- la page d'accueil répond en HTTP 200, en local et depuis la machine master.

Journaux (dossier `logs/`) :

| Fichier | Contenu |
|---------|---------|
| `deploiement.txt` | sortie de `site.yml` (produit par `deploy.sh`) |
| `tests.txt` | sortie de `tests.yml` (produit par `deploy.sh`) |
| `ansible_run.txt` | journal complet de toutes les exécutions (`log_path` dans `ansible.cfg`) |
| `verification_statique.txt` | `--syntax-check` et `ansible-lint` (profil *production*) |

Les playbooks sont **idempotents** : un second `ansible-playbook site.yml` se termine sans modification.

## Structure du projet

```
ansible-prestashop/
├── ansible.cfg                 # inventaire, roles_path, journal, SSH
├── inventaire.yaml             # groupes db et web
├── requirements.yml            # collection community.mysql
├── site.yml                    # orchestration : rôle mysql puis rôle prestashop
├── tests.yml                   # tests de validation
├── deploy.sh                   # déploiement + tests + journaux
├── group_vars/all/
│   ├── vars.yml                # connexion SSH, base partagée, admin boutique
│   └── vault.yml               # secrets (à chiffrer avec ansible-vault)
├── logs/
└── roles/
    ├── mysql/
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── meta/main.yml
    │   └── tasks/main.yml
    └── prestashop/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── meta/main.yml
        ├── tasks/
        │   ├── main.yml        # enchaîne les fichiers ci-dessous
        │   ├── domain.yml      # domaine de la boutique (IP publique)
        │   ├── php.yml         # PHP 8.1 + extensions + php.ini
        │   ├── apache.yml      # Apache, modules, virtual host
        │   ├── download.yml    # téléchargement et extraction
        │   └── install.yml     # installation en ligne de commande
        └── templates/prestashop.conf.j2
```

## Principales variables

| Variable | Défaut | Où |
|----------|--------|----|
| `db_name` / `db_user` | `prestashop` | `group_vars/all/vars.yml` |
| `vault_db_password` | à changer | `group_vars/all/vault.yml` |
| `vault_prestashop_admin_password` | à changer | `group_vars/all/vault.yml` |
| `prestashop_version` | `8.2.3` | `roles/prestashop/defaults` |
| `prestashop_php_version` | `8.1` | `roles/prestashop/defaults` |
| `prestashop_language` / `prestashop_country` | `fr` / `fr` | `roles/prestashop/defaults` |
| `prestashop_install_demo_data` | `1` (catalogue de démo) | `roles/prestashop/defaults` |
| `prestashop_admin_dir` | `admin-liora` | `roles/prestashop/defaults` |
| `mysql_allowed_hosts` | IP des hôtes du groupe `web` | `roles/mysql/defaults` |

Toute variable peut être surchargée au lancement, par exemple :

```bash
ansible-playbook site.yml -e prestashop_install_demo_data=0 -e prestashop_language=en
```

## Dépannage

| Symptôme | Piste |
|----------|-------|
| `Missing sudo password` | Relancer avec `-K` pour saisir le mot de passe sudo de `liora`. |
| `UNREACHABLE` | Vérifier l'IP privée dans l'inventaire, le port 22 et les droits `chmod 600` de la clé. |
| L'installateur échoue | Relancer avec `-e prestashop_hide_secrets=false` pour voir le message ; vérifier l'accès Internet du serveur web et le port 3306 vers la base. Une relance reprend l'installation depuis le début. |
| « Cannot download language pack » | Le serveur web n'a pas accès à `i18n.prestashop-project.org`. |
| La boutique redirige vers une mauvaise adresse | Définir `public_ip` pour l'hôte web dans l'inventaire, puis supprimer `/var/www/prestashop` et relancer. |

## Nettoyage

Penser à **arrêter ou supprimer les instances EC2** après l'évaluation pour éviter des frais.

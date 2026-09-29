#!/usr/bin/env bash
# Déploie la boutique puis lance les tests ; toute la sortie est conservée dans logs/.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p logs

ansible-galaxy collection install -r requirements.yml

{
  echo "=== Déploiement - $(date '+%Y-%m-%d %H:%M:%S') ==="
  ansible-playbook site.yml "$@"
} 2>&1 | tee logs/deploiement.txt

{
  echo "=== Tests - $(date '+%Y-%m-%d %H:%M:%S') ==="
  ansible-playbook tests.yml "$@"
} 2>&1 | tee logs/tests.txt

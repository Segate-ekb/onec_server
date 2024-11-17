#!/bin/bash
set -e

# Проверяем, что rac доступен
if ! command -v /opt/1cv8/current/rac >/dev/null 2>&1; then
  echo "rac utility not found." >&2
  exit 1
fi

# Выполняем команду проверки кластера
if /opt/1cv8/current/rac cluster list | grep -q "cluster[[:space:]]\+:"; then
  echo "Cluster is running."
  exit 0
else
  echo "Cluster is not available." >&2
  exit 1
fi

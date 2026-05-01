#!/bin/bash
# manual_reset.sh
# Script para resetear manualmente el estado de orquestación
#
# Uso: ./manual_reset.sh <release_id>
# Ejemplo: ./manual_reset.sh 2026-05-01-001
#
# Requisitos:
#   - HARNESS_API_KEY en variable de entorno
#   - HARNESS_ACCOUNT_ID en variable de entorno
#   - curl y jq instalados
#
# ADVERTENCIA: Este script modifica el estado de producción.
#              Usar con precaución.

set -e

# Cargar variables de entorno si existe .env
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

# Validar argumentos
if [ -z "$1" ]; then
  echo "Uso: $0 <release_id>"
  echo "Ejemplo: $0 2026-05-01-001"
  exit 1
fi

RELEASE_ID="$1"

# Validar requisitos
if [ -z "$HARNESS_API_KEY" ]; then
  echo "ERROR: HARNESS_API_KEY no configurada"
  exit 1
fi

if [ -z "$HARNESS_ACCOUNT_ID" ]; then
  echo "ERROR: HARNESS_ACCOUNT_ID no configurada"
  exit 1
fi

BASE_URL="https://app.harness.io/gateway/ng/api/variables"

echo "=========================================="
echo "   MANUAL STATE RESET"
echo "=========================================="
echo ""
echo "Release ID: $RELEASE_ID"
echo ""

# Confirmar antes de proceder
read -p "⚠️  This will reset the release state. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Resetting state..."

# Reset NEXT_REQUIRED
echo -n "  STAGE_RELEASE_NEXT_REQUIRED = 1 ... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --request PUT \
  --url "${BASE_URL}?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "Content-Type: application/json" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  --data '{
    "variable": {
      "identifier": "STAGE_RELEASE_NEXT_REQUIRED",
      "name": "STAGE_RELEASE_NEXT_REQUIRED",
      "type": "String",
      "value": "1"
    }
  }')

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✓"
else
  echo "✗ (HTTP $HTTP_CODE)"
  exit 1
fi

# Reset COMPLETED
echo -n "  STAGE_RELEASE_COMPLETED = '' ... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --request PUT \
  --url "${BASE_URL}?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "Content-Type: application/json" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  --data '{
    "variable": {
      "identifier": "STAGE_RELEASE_COMPLETED",
      "name": "STAGE_RELEASE_COMPLETED",
      "type": "String",
      "value": ""
    }
  }')

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✓"
else
  echo "✗ (HTTP $HTTP_CODE)"
  exit 1
fi

# Update RELEASE_ID
echo -n "  STAGE_RELEASE_ID = $RELEASE_ID ... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --request PUT \
  --url "${BASE_URL}?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "Content-Type: application/json" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  --data '{
    "variable": {
      "identifier": "STAGE_RELEASE_ID",
      "name": "STAGE_RELEASE_ID",
      "type": "String",
      "value": "'"$RELEASE_ID"'"
    }
  }')

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "✓"
else
  echo "✗ (HTTP $HTTP_CODE)"
  exit 1
fi

echo ""
echo "=========================================="
echo "   RESET COMPLETE"
echo "=========================================="
echo ""
echo "New release cycle ready: $RELEASE_ID"
echo "Services can now be deployed in order (1 → 10)"

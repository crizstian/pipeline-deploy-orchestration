#!/bin/bash
# check_state.sh
# Script para verificar el estado actual de la orquestación de releases
#
# Uso: ./check_state.sh
# Requisitos:
#   - HARNESS_API_KEY en variable de entorno o archivo .env
#   - HARNESS_ACCOUNT_ID en variable de entorno o archivo .env
#   - curl y jq instalados

set -e

# Cargar variables de entorno si existe .env
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

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
echo "   STAGE RELEASE STATE"
echo "=========================================="
echo ""

# Obtener NEXT_REQUIRED
NEXT_REQUIRED=$(curl -s --request GET \
  --url "${BASE_URL}/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  | jq -r '.data.variable.value // "NOT_FOUND"')

# Obtener COMPLETED
COMPLETED=$(curl -s --request GET \
  --url "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  | jq -r '.data.variable.value // "NOT_FOUND"')

# Obtener RELEASE_ID
RELEASE_ID=$(curl -s --request GET \
  --url "${BASE_URL}/STAGE_RELEASE_ID?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
  --header "x-api-key: ${HARNESS_API_KEY}" \
  | jq -r '.data.variable.value // "NOT_FOUND"')

echo "Release ID:     $RELEASE_ID"
echo "Next Required:  $NEXT_REQUIRED"
echo "Completed:      $COMPLETED"
echo ""

# Mapeo de servicios
declare -A SERVICES
SERVICES[1]="auth-backend"
SERVICES[2]="graph-service"
SERVICES[3]="ur-backend"
SERVICES[4]="ur-core-ng"
SERVICES[5]="notifications-backend"
SERVICES[6]="oc-backend"
SERVICES[7]="oc-bads-backend"
SERVICES[8]="app-provider-fe"
SERVICES[9]="manage-frontend-fe"
SERVICES[10]="solutions-fe"

echo "Service Status:"
echo "---------------"

for i in {1..10}; do
  SERVICE_NAME="${SERVICES[$i]}"

  # Verificar si está en COMPLETED
  if echo ",$COMPLETED," | grep -q ",$i,"; then
    STATUS="✅ COMPLETED"
  elif [ "$i" -eq "$NEXT_REQUIRED" ]; then
    STATUS="⏳ NEXT (waiting)"
  elif [ "$i" -lt "$NEXT_REQUIRED" ]; then
    STATUS="❓ MISSING (inconsistent)"
  else
    STATUS="⏸️  PENDING"
  fi

  printf "  %2d. %-25s %s\n" "$i" "$SERVICE_NAME" "$STATUS"
done

echo ""
echo "=========================================="

# Advertencias
if [ "$NEXT_REQUIRED" = "11" ]; then
  echo "ℹ️  All services deployed. Ready for new release cycle."
elif [ "$NEXT_REQUIRED" = "NOT_FOUND" ]; then
  echo "⚠️  Variables not found. Initialize with reset_release pipeline."
fi

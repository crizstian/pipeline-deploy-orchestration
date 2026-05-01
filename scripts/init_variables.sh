#!/bin/bash
# init_variables.sh
# Script para crear las variables iniciales de orquestación en Harness
#
# Uso: ./init_variables.sh
# Requisitos:
#   - HARNESS_API_KEY en variable de entorno
#   - HARNESS_ACCOUNT_ID en variable de entorno
#   - curl y jq instalados
#
# Este script solo necesita ejecutarse UNA VEZ al configurar el sistema.

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
echo "   INITIALIZE ORCHESTRATION VARIABLES"
echo "=========================================="
echo ""
echo "Account ID: $HARNESS_ACCOUNT_ID"
echo ""

# Función para crear variable
create_variable() {
  local NAME="$1"
  local VALUE="$2"
  local DESCRIPTION="$3"

  echo -n "Creating $NAME ... "

  RESPONSE=$(curl -s --request POST \
    --url "${BASE_URL}?accountIdentifier=${HARNESS_ACCOUNT_ID}" \
    --header "Content-Type: application/json" \
    --header "x-api-key: ${HARNESS_API_KEY}" \
    --data '{
      "variable": {
        "identifier": "'"$NAME"'",
        "name": "'"$NAME"'",
        "description": "'"$DESCRIPTION"'",
        "type": "String",
        "valueType": "FIXED",
        "value": "'"$VALUE"'"
      }
    }')

  # Check if already exists (we get a different status)
  if echo "$RESPONSE" | jq -e '.status == "SUCCESS"' > /dev/null 2>&1; then
    echo "✓ Created"
  elif echo "$RESPONSE" | jq -e '.code == "DUPLICATE_FIELD"' > /dev/null 2>&1; then
    echo "⚠ Already exists"
  else
    echo "✗ Failed"
    echo "Response: $RESPONSE"
  fi
}

echo "Creating variables at Account scope..."
echo ""

create_variable \
  "STAGE_RELEASE_NEXT_REQUIRED" \
  "1" \
  "Next service order required for deployment (1-11)"

create_variable \
  "STAGE_RELEASE_COMPLETED" \
  "" \
  "Comma-separated list of completed service orders"

create_variable \
  "STAGE_RELEASE_ID" \
  "initial" \
  "Current release identifier"

echo ""
echo "=========================================="
echo "   INITIALIZATION COMPLETE"
echo "=========================================="
echo ""
echo "Variables created at Account level."
echo ""
echo "Next steps:"
echo "  1. Create the API Key secret: account.HARNESS_API_KEY"
echo "  2. Add deployment_order variable to each pipeline"
echo "  3. Add Deployment_Gate and Update_State stages"
echo "  4. Run reset_release pipeline to start first release"

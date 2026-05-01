# Quickstart: Orquestación de Despliegues

**Tiempo estimado:** 30 minutos para el primer pipeline

---

## TL;DR - 5 Pasos

```
1. Crear Secret     → account.HARNESS_API_KEY
2. Crear Variables  → STAGE_RELEASE_NEXT_REQUIRED, STAGE_RELEASE_COMPLETED
3. Agregar variable → deployment_order = "N" en cada pipeline
4. Agregar stage    → Deployment_Gate después de Build
5. Agregar stage    → Update_State al final
```

---

## Paso 1: Crear Secret (una sola vez)

```
Account Settings → Access Control → Service Accounts → New
  └── Name: deployment-orchestration-sa
  └── Generate API Key → Copiar

Account Settings → Account Resources → Secrets → New Secret → Text
  └── Name: HARNESS_API_KEY
  └── Value: [pegar API key]
```

## Paso 2: Crear Variables (una sola vez)

```
Account Settings → Account Resources → Variables → New Variable

Variable 1:
  Name: STAGE_RELEASE_NEXT_REQUIRED
  Value: 1

Variable 2:
  Name: STAGE_RELEASE_COMPLETED
  Value: [vacío]
```

## Paso 3: Por cada Pipeline

### 3.1 Agregar variable de orden

```yaml
# En pipeline YAML, agregar:
variables:
  - name: deployment_order
    type: String
    value: "1"  # Cambiar según el pipeline (1-10)
```

### 3.2 Copiar stage Deployment_Gate

Ubicación: **después de Build, antes de Deploy**

```yaml
- stage:
    name: Deployment_Gate
    identifier: Deployment_Gate
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: ShellScript
              name: Validate_Order
              identifier: Validate_Order
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      MY_ORDER="<+pipeline.variables.deployment_order>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      ACCOUNT_ID="<+account.identifier>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      while true; do
                        NEXT=$(curl -s "${BASE_URL}/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${ACCOUNT_ID}" \
                          -H "x-api-key: ${API_KEY}" | jq -r '.data.variable.value')
                        COMPLETED=$(curl -s "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${ACCOUNT_ID}" \
                          -H "x-api-key: ${API_KEY}" | jq -r '.data.variable.value // ""')
                        
                        if [ "$MY_ORDER" == "$NEXT" ]; then
                          echo "✅ PROCEED"; export DEPLOYMENT_MODE="NORMAL"; break
                        elif [ "$MY_ORDER" -lt "$NEXT" ] && echo ",$COMPLETED," | grep -q ",$MY_ORDER,"; then
                          echo "✅ HOTFIX"; export DEPLOYMENT_MODE="HOTFIX"; break
                        elif [ "$MY_ORDER" -gt "$NEXT" ]; then
                          echo "⏳ WAITING ($MY_ORDER > $NEXT)"; sleep 30
                        else
                          echo "❌ ERROR"; exit 1
                        fi
                      done
                outputVariables:
                  - name: DEPLOYMENT_MODE
                timeout: 4h
```

### 3.3 Copiar stage Update_State

Ubicación: **al final del pipeline**

```yaml
- stage:
    name: Update_State
    identifier: Update_State
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: ShellScript
              name: Write_State
              identifier: Write_State
              spec:
                shell: Bash
                source:
                  type: Inline
                  spec:
                    script: |
                      MODE="<+pipeline.stages.Deployment_Gate.spec.execution.steps.Validate_Order.output.outputVariables.DEPLOYMENT_MODE>"
                      [ "$MODE" == "HOTFIX" ] && echo "Skip update" && exit 0
                      
                      MY_ORDER="<+pipeline.variables.deployment_order>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      ACCOUNT_ID="<+account.identifier>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      COMPLETED=$(curl -s "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${ACCOUNT_ID}" \
                        -H "x-api-key: ${API_KEY}" | jq -r '.data.variable.value // ""')
                      
                      NEW_NEXT=$((MY_ORDER + 1))
                      NEW_COMPLETED="${COMPLETED:+$COMPLETED,}$MY_ORDER"
                      
                      curl -X PUT "${BASE_URL}?accountIdentifier=${ACCOUNT_ID}" \
                        -H "x-api-key: ${API_KEY}" -H "Content-Type: application/json" \
                        -d '{"variable":{"identifier":"STAGE_RELEASE_NEXT_REQUIRED","name":"STAGE_RELEASE_NEXT_REQUIRED","type":"String","value":"'$NEW_NEXT'"}}'
                      
                      curl -X PUT "${BASE_URL}?accountIdentifier=${ACCOUNT_ID}" \
                        -H "x-api-key: ${API_KEY}" -H "Content-Type: application/json" \
                        -d '{"variable":{"identifier":"STAGE_RELEASE_COMPLETED","name":"STAGE_RELEASE_COMPLETED","type":"String","value":"'$NEW_COMPLETED'"}}'
                      
                      echo "✅ Updated: NEXT=$NEW_NEXT, COMPLETED=$NEW_COMPLETED"
                timeout: 2m
```

## Paso 4: Probar

```bash
# Verificar estado
curl -s "https://app.harness.io/gateway/ng/api/variables/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" | jq '.data.variable.value'
```

## Ciclo de Release

```
NEXT=1  → Pipeline 1 ejecuta → NEXT=2
NEXT=2  → Pipeline 2 ejecuta → NEXT=3
...
NEXT=10 → Pipeline 10 ejecuta → NEXT=11

⚠️ NEXT=11 significa RELEASE COMPLETO
   Hacer RESET antes de nuevo ciclo:
```

```bash
# Reset para nuevo release (cuando NEXT=11)
curl -X PUT "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" -H "Content-Type: application/json" \
  -d '{"variable":{"identifier":"STAGE_RELEASE_NEXT_REQUIRED","name":"STAGE_RELEASE_NEXT_REQUIRED","type":"String","value":"1"}}'

curl -X PUT "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" -H "Content-Type: application/json" \
  -d '{"variable":{"identifier":"STAGE_RELEASE_COMPLETED","name":"STAGE_RELEASE_COMPLETED","type":"String","value":""}}'
```

---

## Orden de Pipelines

| Pipeline | Orden |
|----------|-------|
| auth-backend | 1 |
| glo_graph_service_build | 2 |
| ur_backend_build | 3 |
| ur_core_ng_build | 4 |
| glo_notifications_backend | 5 |
| oc_backend | 6 |
| oc_bads_backend | 7 |
| glo_app_provider_build | 8 |
| manage_frontend_app_provider_build | 9 |
| solutions_frontend_build | 10 |

---

## Más Información

- [Guía Completa de Implementación](./IMPLEMENTATION_GUIDE.md)
- [Documentación Técnica](./README.md)
- [Templates YAML](./templates/)

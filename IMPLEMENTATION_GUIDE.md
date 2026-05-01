# Guía de Implementación Paso a Paso

## Orquestación de Despliegues Secuenciales

**Objetivo:** Transformar 10 pipelines independientes en un sistema orquestado que garantiza despliegue secuencial 1→2→3→...→10.

---

## Índice

1. [Resumen de Transformación](#1-resumen-de-transformación)
2. [Fase 1: Preparación de Infraestructura](#2-fase-1-preparación-de-infraestructura)
3. [Fase 2: Modificación de Pipelines](#3-fase-2-modificación-de-pipelines)
4. [Fase 3: Validación](#4-fase-3-validación)
5. [Fase 4: Operación](#5-fase-4-operación)
6. [Referencia Rápida](#6-referencia-rápida)

---

## 1. Resumen de Transformación

### 1.1 Vista General: Antes vs Después

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ESTADO ACTUAL                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Pipeline 1          Pipeline 2          Pipeline 10                       │
│   ┌──────────┐        ┌──────────┐        ┌──────────┐                      │
│   │ Approval │        │ Approval │   ...  │ Approval │                      │
│   │ PR_Check │        │ PR_Check │        │ PR_Check │                      │
│   │ Build    │        │ Build    │        │ Build    │                      │
│   │ Deploy   │        │ Deploy   │        │ Deploy   │                      │
│   └──────────┘        └──────────┘        └──────────┘                      │
│        │                   │                   │                             │
│        ▼                   ▼                   ▼                             │
│   [EJECUTA             [EJECUTA            [EJECUTA                         │
│    INMEDIATAMENTE]      INMEDIATAMENTE]     INMEDIATAMENTE]                 │
│                                                                              │
│   ❌ Sin coordinación entre pipelines                                        │
│   ❌ Despliegues fuera de orden                                              │
│   ❌ Dependencias rotas en runtime                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    │ TRANSFORMACIÓN
                                    ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│                              ESTADO FUTURO                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    HARNESS ACCOUNT VARIABLES                         │   │
│   │  ┌─────────────────────────────────────────────────────────────┐    │   │
│   │  │ STAGE_RELEASE_NEXT_REQUIRED = "1"                           │    │   │
│   │  │ STAGE_RELEASE_COMPLETED = ""                                │    │   │
│   │  │ STAGE_RELEASE_ID = "2026-05-01-001"                         │    │   │
│   │  └─────────────────────────────────────────────────────────────┘    │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                         │
│                                    │ Lee/Escribe                             │
│                                    │                                         │
│   Pipeline 1          Pipeline 2          Pipeline 10                       │
│   ┌──────────┐        ┌──────────┐        ┌──────────┐                      │
│   │ Approval │        │ Approval │   ...  │ Approval │                      │
│   │ PR_Check │        │ PR_Check │        │ PR_Check │                      │
│   │ Build    │        │ Build    │        │ Build    │                      │
│   │ ┌──────┐ │        │ ┌──────┐ │        │ ┌──────┐ │  ◄── NUEVO          │
│   │ │ GATE │ │        │ │ GATE │ │        │ │ GATE │ │                      │
│   │ └──────┘ │        │ └──────┘ │        │ └──────┘ │                      │
│   │ Deploy   │        │ Deploy   │        │ Deploy   │                      │
│   │ ┌──────┐ │        │ ┌──────┐ │        │ ┌──────┐ │  ◄── NUEVO          │
│   │ │UPDATE│ │        │ │UPDATE│ │        │ │UPDATE│ │                      │
│   │ └──────┘ │        │ └──────┘ │        │ └──────┘ │                      │
│   └──────────┘        └──────────┘        └──────────┘                      │
│        │                   │                   │                             │
│        ▼                   ▼                   ▼                             │
│   [ESPERA TURNO]      [ESPERA TURNO]      [ESPERA TURNO]                    │
│   [ORDEN = 1]         [ORDEN = 2]         [ORDEN = 10]                      │
│                                                                              │
│   ✅ Despliegue secuencial garantizado                                       │
│   ✅ Hotfixes sin bloquear el flujo                                          │
│   ✅ Estado visible y auditable                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Checklist de Componentes a Crear/Modificar

| # | Componente | Tipo | Acción | Prioridad |
|---|------------|------|--------|-----------|
| 1 | Secret `HARNESS_API_KEY` | Secret | CREAR | Alta |
| 2 | Variable `STAGE_RELEASE_NEXT_REQUIRED` | Variable | CREAR | Alta |
| 3 | Variable `STAGE_RELEASE_COMPLETED` | Variable | CREAR | Alta |
| 4 | Variable `STAGE_RELEASE_ID` | Variable | CREAR | Media |
| 5 | Variable `deployment_order` por pipeline | Variable | AGREGAR | Alta |
| 6 | Stage `Deployment_Gate` por pipeline | Stage | AGREGAR | Alta |
| 7 | Stage `Update_State` por pipeline | Stage | AGREGAR | Alta |
| 8 | Pipeline `reset_release` | Pipeline | CREAR | Media |

---

## 2. Fase 1: Preparación de Infraestructura

### Paso 1.1: Crear API Key en Harness

**Ubicación:** Account Settings → Access Control → Service Accounts

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ACCIÓN: Crear Service Account y API Key                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Ir a: Account Settings → Access Control → Service Accounts              │
│                                                                              │
│  2. Click "New Service Account"                                             │
│     ├── Name: deployment-orchestration-sa                                   │
│     ├── Email: deployment-orchestration@serviceaccount.harness.io           │
│     └── Description: Service account for deployment orchestration           │
│                                                                              │
│  3. En el Service Account, click "Generate API Key"                         │
│     ├── Name: orchestration-api-key                                         │
│     ├── Expiry: 90 days (o según política)                                  │
│     └── ⚠️ COPIAR el API Key generado (solo se muestra una vez)            │
│                                                                              │
│  4. Asignar permisos al Service Account:                                    │
│     ├── Role: Account Viewer (para leer variables)                          │
│     └── Role: Account Admin (para escribir variables)                       │
│         └── O crear rol custom con solo permisos de Variables               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Paso 1.2: Crear Secret con API Key

**Ubicación:** Account Settings → Account Resources → Secrets

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ACCIÓN: Crear Secret para API Key                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Ir a: Account Settings → Account Resources → Secrets                    │
│                                                                              │
│  2. Click "New Secret" → "Text"                                             │
│                                                                              │
│  3. Configurar:                                                              │
│     ┌─────────────────────────────────────────────────────────────────┐     │
│     │ Secret Name:        HARNESS_API_KEY                             │     │
│     │ Secret Identifier:  HARNESS_API_KEY                             │     │
│     │ Secret Value:       [pegar API Key del paso anterior]           │     │
│     │ Scope:              Account                                      │     │
│     │ Description:        API Key for deployment orchestration        │     │
│     └─────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│  4. Click "Save"                                                             │
│                                                                              │
│  RESULTADO: El secret estará disponible como:                               │
│             <+secrets.getValue("account.HARNESS_API_KEY")>                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Paso 1.3: Crear Variables de Estado

**Ubicación:** Account Settings → Account Resources → Variables

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ACCIÓN: Crear 3 Variables de Account                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  VARIABLE 1: STAGE_RELEASE_NEXT_REQUIRED                                    │
│  ─────────────────────────────────────────                                  │
│  1. Click "New Variable"                                                     │
│  2. Configurar:                                                              │
│     ┌─────────────────────────────────────────────────────────────────┐     │
│     │ Name:          STAGE_RELEASE_NEXT_REQUIRED                      │     │
│     │ Identifier:    STAGE_RELEASE_NEXT_REQUIRED                      │     │
│     │ Type:          String                                            │     │
│     │ Fixed Value:   1                                                 │     │
│     │ Description:   Próximo servicio requerido para despliegue (1-11)│     │
│     └─────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│  VARIABLE 2: STAGE_RELEASE_COMPLETED                                        │
│  ────────────────────────────────────                                       │
│  1. Click "New Variable"                                                     │
│  2. Configurar:                                                              │
│     ┌─────────────────────────────────────────────────────────────────┐     │
│     │ Name:          STAGE_RELEASE_COMPLETED                          │     │
│     │ Identifier:    STAGE_RELEASE_COMPLETED                          │     │
│     │ Type:          String                                            │     │
│     │ Fixed Value:   [dejar vacío]                                    │     │
│     │ Description:   Lista de servicios completados (ej: 1,2,3)       │     │
│     └─────────────────────────────────────────────────────────────────┘     │
│                                                                              │
│  VARIABLE 3: STAGE_RELEASE_ID                                               │
│  ─────────────────────────────                                              │
│  1. Click "New Variable"                                                     │
│  2. Configurar:                                                              │
│     ┌─────────────────────────────────────────────────────────────────┐     │
│     │ Name:          STAGE_RELEASE_ID                                 │     │
│     │ Identifier:    STAGE_RELEASE_ID                                 │     │
│     │ Type:          String                                            │     │
│     │ Fixed Value:   initial                                          │     │
│     │ Description:   Identificador del release actual                 │     │
│     └─────────────────────────────────────────────────────────────────┘     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Alternativa: Crear variables via script**

```bash
# Ejecutar desde terminal con acceso a Harness API
cd /workspace/docs/harness-platform/deployment-orchestration/scripts
chmod +x init_variables.sh
export HARNESS_API_KEY="tu-api-key"
export HARNESS_ACCOUNT_ID="tu-account-id"
./init_variables.sh
```

### Verificación Fase 1

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CHECKLIST DE VERIFICACIÓN - FASE 1                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  [ ] Service Account creado: deployment-orchestration-sa                    │
│  [ ] API Key generado y guardado de forma segura                            │
│  [ ] Secret creado: account.HARNESS_API_KEY                                 │
│  [ ] Variable creada: STAGE_RELEASE_NEXT_REQUIRED = "1"                     │
│  [ ] Variable creada: STAGE_RELEASE_COMPLETED = ""                          │
│  [ ] Variable creada: STAGE_RELEASE_ID = "initial"                          │
│                                                                              │
│  VERIFICAR via API:                                                          │
│  curl -s "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=ACCOUNT_ID" \
│       -H "x-api-key: $HARNESS_API_KEY" | jq '.data.content[].variable.name' │
│                                                                              │
│  Debe mostrar:                                                               │
│    "STAGE_RELEASE_NEXT_REQUIRED"                                            │
│    "STAGE_RELEASE_COMPLETED"                                                │
│    "STAGE_RELEASE_ID"                                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Fase 2: Modificación de Pipelines

### 3.1 Anatomía de la Transformación

Para cada pipeline, aplicarás esta transformación:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TRANSFORMACIÓN DE PIPELINE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ANTES (Pipeline Original)          DESPUÉS (Pipeline Modificado)          │
│   ─────────────────────────          ──────────────────────────────         │
│                                                                              │
│   pipeline:                          pipeline:                               │
│     name: auth-backend                 name: auth-backend                    │
│     stages:                            variables:                  ◄─ NUEVO  │
│       - stage: Approval                  - name: deployment_order  ◄─ NUEVO  │
│       - stage: PR_Checks                   type: String            ◄─ NUEVO  │
│       - stage: Branch_Checks               value: "1"              ◄─ NUEVO  │
│       - stage: Build_and_Push            stages:                             │
│       - stage: Apply_Migrations            - stage: Approval                 │
│       - stage: Deploy_Backend              - stage: PR_Checks                │
│       - stage: Deploy_EKS                  - stage: Branch_Checks            │
│                                            - stage: Build_and_Push           │
│                                            - stage: Deployment_Gate ◄─ NUEVO │
│                                            - stage: Apply_Migrations         │
│                                            - stage: Deploy_Backend           │
│                                            - stage: Deploy_EKS               │
│                                            - stage: Update_State   ◄─ NUEVO  │
│                                                                              │
│   CAMBIOS:                                                                   │
│   ─────────                                                                  │
│   1. Agregar variable "deployment_order" con valor del orden (1-10)         │
│   2. Insertar stage "Deployment_Gate" DESPUÉS de Build                      │
│   3. Insertar stage "Update_State" AL FINAL                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Paso a Paso: Modificar un Pipeline

#### Paso 3.2.1: Agregar Variable `deployment_order`

**Ubicación:** Pipeline Studio → Variables (panel izquierdo)

```yaml
# AGREGAR en la sección "variables" del pipeline
# Si no existe la sección, crearla

variables:
  - name: deployment_order
    type: String
    description: "Orden de despliegue para orquestación (1-10)"
    required: true
    value: "1"  # ← Cambiar según el pipeline (1, 2, 3, ... 10)
```

**Tabla de valores por pipeline:**

| Pipeline | `deployment_order` |
|----------|-------------------|
| auth-backend | `"1"` |
| glo_graph_service_build | `"2"` |
| ur_backend_build | `"3"` |
| ur_core_ng_build | `"4"` |
| glo_notifications_backend | `"5"` |
| oc_backend | `"6"` |
| oc_bads_backend | `"7"` |
| glo_app_provider_build | `"8"` |
| manage_frontend_app_provider_build | `"9"` |
| solutions_frontend_build | `"10"` |

#### Paso 3.2.2: Insertar Stage `Deployment_Gate`

**Ubicación:** Pipeline Studio → Agregar Stage después de Build stages

```yaml
# COPIAR este stage completo
# Insertar DESPUÉS del último stage de Build/PR_Checks
# y ANTES del primer stage de Deploy/Migrations

- stage:
    name: Deployment_Gate
    identifier: Deployment_Gate
    description: "Verifica orden de despliegue antes de proceder"
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: ShellScript
              name: Read_State
              identifier: Read_State
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      
                      echo "=== Reading Orchestration State ==="
                      
                      ACCOUNT_ID="<+account.identifier>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      # Read NEXT_REQUIRED
                      NEXT_REQUIRED=$(curl -s --request GET \
                        --url "${BASE_URL}/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${ACCOUNT_ID}" \
                        --header "x-api-key: ${API_KEY}" \
                        | jq -r '.data.variable.value // "1"')
                      
                      # Read COMPLETED
                      COMPLETED=$(curl -s --request GET \
                        --url "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${ACCOUNT_ID}" \
                        --header "x-api-key: ${API_KEY}" \
                        | jq -r '.data.variable.value // ""')
                      
                      echo "NEXT_REQUIRED: $NEXT_REQUIRED"
                      echo "COMPLETED: $COMPLETED"
                      
                      # Export for next steps
                      export NEXT_REQUIRED
                      export COMPLETED
                outputVariables:
                  - name: NEXT_REQUIRED
                  - name: COMPLETED
                timeout: 1m
          
          - step:
              type: ShellScript
              name: Validate_Order
              identifier: Validate_Order
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      
                      MY_ORDER="<+pipeline.variables.deployment_order>"
                      NEXT_REQUIRED="<+execution.steps.Read_State.output.outputVariables.NEXT_REQUIRED>"
                      COMPLETED="<+execution.steps.Read_State.output.outputVariables.COMPLETED>"
                      
                      MAX_WAIT_SECONDS=14400  # 4 hours
                      POLL_INTERVAL=30
                      ELAPSED=0
                      
                      ACCOUNT_ID="<+account.identifier>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      echo "=== Deployment Gate ==="
                      echo "My Order: $MY_ORDER"
                      echo "Next Required: $NEXT_REQUIRED"
                      echo "Completed: $COMPLETED"
                      
                      while true; do
                        # Case 1: Normal flow - it's my turn
                        if [ "$MY_ORDER" == "$NEXT_REQUIRED" ]; then
                          echo "✅ NORMAL MODE: Order $MY_ORDER matches NEXT_REQUIRED"
                          echo "DEPLOYMENT_MODE=NORMAL" 
                          export DEPLOYMENT_MODE="NORMAL"
                          break
                        fi
                        
                        # Case 2: Hotfix - already deployed, re-deploying
                        if [ "$MY_ORDER" -lt "$NEXT_REQUIRED" ]; then
                          if echo ",$COMPLETED," | grep -q ",$MY_ORDER,"; then
                            echo "✅ HOTFIX MODE: Order $MY_ORDER already in COMPLETED"
                            echo "DEPLOYMENT_MODE=HOTFIX"
                            export DEPLOYMENT_MODE="HOTFIX"
                            break
                          else
                            echo "❌ ERROR: Inconsistent state"
                            echo "Order $MY_ORDER < NEXT_REQUIRED $NEXT_REQUIRED but NOT in COMPLETED"
                            exit 1
                          fi
                        fi
                        
                        # Case 3: Waiting - not my turn yet
                        if [ "$MY_ORDER" -gt "$NEXT_REQUIRED" ]; then
                          echo "⏳ WAITING: Order $MY_ORDER > NEXT_REQUIRED $NEXT_REQUIRED"
                          echo "Polling in $POLL_INTERVAL seconds... (elapsed: ${ELAPSED}s / ${MAX_WAIT_SECONDS}s)"
                          
                          if [ "$ELAPSED" -ge "$MAX_WAIT_SECONDS" ]; then
                            echo "❌ TIMEOUT: Max wait time exceeded"
                            echo "Blocked waiting for service $NEXT_REQUIRED"
                            exit 1
                          fi
                          
                          sleep $POLL_INTERVAL
                          ELAPSED=$((ELAPSED + POLL_INTERVAL))
                          
                          # Re-read state
                          NEXT_REQUIRED=$(curl -s --request GET \
                            --url "${BASE_URL}/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${ACCOUNT_ID}" \
                            --header "x-api-key: ${API_KEY}" \
                            | jq -r '.data.variable.value // "1"')
                          
                          COMPLETED=$(curl -s --request GET \
                            --url "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${ACCOUNT_ID}" \
                            --header "x-api-key: ${API_KEY}" \
                            | jq -r '.data.variable.value // ""')
                          
                          echo "Updated - NEXT_REQUIRED: $NEXT_REQUIRED, COMPLETED: $COMPLETED"
                        fi
                      done
                outputVariables:
                  - name: DEPLOYMENT_MODE
                timeout: 5h
          
          - step:
              type: ShellScript
              name: Release_Gate
              identifier: Release_Gate
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      echo "=== Gate Passed ==="
                      echo "Mode: <+execution.steps.Validate_Order.output.outputVariables.DEPLOYMENT_MODE>"
                      echo "Proceeding to deployment..."
                timeout: 1m
    tags: {}
```

#### Paso 3.2.3: Insertar Stage `Update_State`

**Ubicación:** Pipeline Studio → Agregar Stage AL FINAL del pipeline

```yaml
# COPIAR este stage completo
# Insertar como ÚLTIMO stage del pipeline

- stage:
    name: Update_State
    identifier: Update_State
    description: "Actualiza estado de orquestación post-deploy"
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: ShellScript
              name: Read_Current_State
              identifier: Read_Current_State
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      
                      ACCOUNT_ID="<+account.identifier>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      NEXT_REQUIRED=$(curl -s --request GET \
                        --url "${BASE_URL}/STAGE_RELEASE_NEXT_REQUIRED?accountIdentifier=${ACCOUNT_ID}" \
                        --header "x-api-key: ${API_KEY}" \
                        | jq -r '.data.variable.value // "1"')
                      
                      COMPLETED=$(curl -s --request GET \
                        --url "${BASE_URL}/STAGE_RELEASE_COMPLETED?accountIdentifier=${ACCOUNT_ID}" \
                        --header "x-api-key: ${API_KEY}" \
                        | jq -r '.data.variable.value // ""')
                      
                      echo "Current NEXT_REQUIRED: $NEXT_REQUIRED"
                      echo "Current COMPLETED: $COMPLETED"
                      
                      export CURRENT_NEXT="$NEXT_REQUIRED"
                      export CURRENT_COMPLETED="$COMPLETED"
                outputVariables:
                  - name: CURRENT_NEXT
                  - name: CURRENT_COMPLETED
                timeout: 1m
          
          - step:
              type: ShellScript
              name: Calculate_New_State
              identifier: Calculate_New_State
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      
                      MY_ORDER="<+pipeline.variables.deployment_order>"
                      DEPLOYMENT_MODE="<+pipeline.stages.Deployment_Gate.spec.execution.steps.Validate_Order.output.outputVariables.DEPLOYMENT_MODE>"
                      CURRENT_NEXT="<+execution.steps.Read_Current_State.output.outputVariables.CURRENT_NEXT>"
                      CURRENT_COMPLETED="<+execution.steps.Read_Current_State.output.outputVariables.CURRENT_COMPLETED>"
                      
                      echo "=== Calculating New State ==="
                      echo "My Order: $MY_ORDER"
                      echo "Deployment Mode: $DEPLOYMENT_MODE"
                      
                      if [ "$DEPLOYMENT_MODE" == "HOTFIX" ]; then
                        echo "HOTFIX mode - No state update required"
                        export NEW_NEXT="$CURRENT_NEXT"
                        export NEW_COMPLETED="$CURRENT_COMPLETED"
                        export SKIP_UPDATE="true"
                      else
                        # Normal mode - increment and add to completed
                        NEW_NEXT=$((MY_ORDER + 1))
                        
                        if [ -z "$CURRENT_COMPLETED" ]; then
                          NEW_COMPLETED="$MY_ORDER"
                        else
                          NEW_COMPLETED="${CURRENT_COMPLETED},${MY_ORDER}"
                        fi
                        
                        echo "New NEXT_REQUIRED: $NEW_NEXT"
                        echo "New COMPLETED: $NEW_COMPLETED"
                        
                        export NEW_NEXT
                        export NEW_COMPLETED
                        export SKIP_UPDATE="false"
                      fi
                outputVariables:
                  - name: NEW_NEXT
                  - name: NEW_COMPLETED
                  - name: SKIP_UPDATE
                timeout: 1m
          
          - step:
              type: ShellScript
              name: Write_State
              identifier: Write_State
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      set -e
                      
                      SKIP_UPDATE="<+execution.steps.Calculate_New_State.output.outputVariables.SKIP_UPDATE>"
                      
                      if [ "$SKIP_UPDATE" == "true" ]; then
                        echo "Skipping state update (HOTFIX mode)"
                        exit 0
                      fi
                      
                      NEW_NEXT="<+execution.steps.Calculate_New_State.output.outputVariables.NEW_NEXT>"
                      NEW_COMPLETED="<+execution.steps.Calculate_New_State.output.outputVariables.NEW_COMPLETED>"
                      
                      ACCOUNT_ID="<+account.identifier>"
                      API_KEY="<+secrets.getValue(\"account.HARNESS_API_KEY\")>"
                      BASE_URL="https://app.harness.io/gateway/ng/api/variables"
                      
                      echo "=== Writing New State ==="
                      echo "Setting NEXT_REQUIRED to: $NEW_NEXT"
                      echo "Setting COMPLETED to: $NEW_COMPLETED"
                      
                      # Update NEXT_REQUIRED
                      curl -s --request PUT \
                        --url "${BASE_URL}?accountIdentifier=${ACCOUNT_ID}" \
                        --header "Content-Type: application/json" \
                        --header "x-api-key: ${API_KEY}" \
                        --data '{
                          "variable": {
                            "identifier": "STAGE_RELEASE_NEXT_REQUIRED",
                            "name": "STAGE_RELEASE_NEXT_REQUIRED",
                            "type": "String",
                            "value": "'"$NEW_NEXT"'"
                          }
                        }'
                      
                      # Update COMPLETED
                      curl -s --request PUT \
                        --url "${BASE_URL}?accountIdentifier=${ACCOUNT_ID}" \
                        --header "Content-Type: application/json" \
                        --header "x-api-key: ${API_KEY}" \
                        --data '{
                          "variable": {
                            "identifier": "STAGE_RELEASE_COMPLETED",
                            "name": "STAGE_RELEASE_COMPLETED",
                            "type": "String",
                            "value": "'"$NEW_COMPLETED"'"
                          }
                        }'
                      
                      echo "✅ State updated successfully"
                timeout: 2m
          
          - step:
              type: ShellScript
              name: Deployment_Complete
              identifier: Deployment_Complete
              spec:
                shell: Bash
                executionTarget: {}
                source:
                  type: Inline
                  spec:
                    script: |
                      #!/bin/bash
                      echo "=== Deployment Complete ==="
                      echo "Service Order: <+pipeline.variables.deployment_order>"
                      echo "Pipeline: <+pipeline.name>"
                      echo "Execution ID: <+pipeline.executionId>"
                      echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
                timeout: 1m
    tags: {}
```

### 3.3 Ubicación de Stages por Pipeline

> **Nota:** La ubicación de los stages `[Deployment_Gate]` y `[Update_State]` se determinó
> analizando la estructura de ejecución de cada pipeline y sus trigger stages.
> El gate se inserta después de los stages de CI (build, checks) y antes de los stages de CD (deploy, migrations).
> Consultar el documento [pipeline_modifications.md](./templates/pipeline_modifications.md) para el análisis detallado.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    UBICACIÓN DE STAGES POR PIPELINE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Pipeline 1: auth-backend                                                    │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Build_and_Push →                    │
│  [Deployment_Gate] → Apply_Migrations → Deploy_Backend → Deploy_EKS →       │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 2: glo_graph_service_build                                        │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks →                                     │
│  [Deployment_Gate] → Stop_Graph_Services → Import_Data_Neo4j →              │
│  Build_and_Push → Apply_Schema_Neo4j → Rollout → Deploy →                   │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 3: ur_backend_build                                               │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → IPM_Checks → Build →                │
│  [Deployment_Gate] → Migrations → Custom_Commands → Deploy → Deploy_EKS →  │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 4: ur_core_ng_build (SIN Approval)                                │
│  ────────────────────────────────────────────────────────────────────────   │
│  PR_Checks →                                                                 │
│  [Deployment_Gate] → Build_and_Push →                                       │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 5: glo_notifications_backend                                      │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Env_Variables_Checks → Build →      │
│  [Deployment_Gate] → Automate_Snapshot_DBs → Migrations → Deploy_EKS →      │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 6: oc_backend                                                      │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Build_and_Push →                    │
│  [Deployment_Gate] → Apply_Migrations → Deploy_EKS →                        │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 7: oc_bads_backend                                                │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Build_and_Push_Backend →            │
│  [Deployment_Gate] → Automate_Snapshot_DBs → Apply_Migrations →             │
│  IPM_Sync → Deploy_EKS →                                                     │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 8: glo_app_provider_build                                         │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Check_Environments →                │
│  Build_APP_Provider →                                                        │
│  [Deployment_Gate] → Deploy →                                               │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 9: manage_frontend_app_provider_build                             │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Build →                             │
│  [Deployment_Gate] → Deploy_Cloudfront →                                    │
│  [Update_State]                                                              │
│                                                                              │
│  Pipeline 10: solutions_frontend_build                                      │
│  ────────────────────────────────────────────────────────────────────────   │
│  Approval → PR_Checks → Branch_Checks → Env_Variables_Checks →              │
│  Build_Solutions_MF →                                                        │
│  [Deployment_Gate] → Deploy →                                               │
│  [Update_State]                                                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Fase 3: Validación

### 4.1 Test de Pipeline Individual

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TEST: Pipeline Individual (usar pipeline 10 - solutions_frontend_build)    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PREPARACIÓN:                                                                │
│  1. Asegurar que STAGE_RELEASE_NEXT_REQUIRED = "10"                         │
│  2. Asegurar que STAGE_RELEASE_COMPLETED = "1,2,3,4,5,6,7,8,9"              │
│                                                                              │
│  EJECUCIÓN:                                                                  │
│  1. Triggear pipeline 10 manualmente                                        │
│  2. Observar logs del stage Deployment_Gate                                 │
│                                                                              │
│  RESULTADO ESPERADO:                                                         │
│  ✅ Read_State muestra: NEXT_REQUIRED=10, COMPLETED=1,2,3,4,5,6,7,8,9       │
│  ✅ Validate_Order muestra: "NORMAL MODE: Order 10 matches NEXT_REQUIRED"   │
│  ✅ Pipeline procede a Deploy                                                │
│  ✅ Update_State actualiza: NEXT_REQUIRED=11, COMPLETED=1,2,...,10          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Test de Polling (Espera)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TEST: Pipeline en Espera                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PREPARACIÓN:                                                                │
│  1. Resetear estado: NEXT_REQUIRED = "1", COMPLETED = ""                    │
│                                                                              │
│  EJECUCIÓN:                                                                  │
│  1. Triggear pipeline 5 (glo_notifications_backend)                         │
│  2. Observar que entra en polling                                           │
│  3. Mientras P5 está en polling, triggear y completar P1, P2, P3, P4        │
│                                                                              │
│  RESULTADO ESPERADO:                                                         │
│  ✅ P5 muestra: "WAITING: Order 5 > NEXT_REQUIRED 1"                        │
│  ✅ P5 hace polling cada 30 segundos                                        │
│  ✅ Cuando P4 completa (NEXT=5), P5 detecta cambio                          │
│  ✅ P5 muestra: "NORMAL MODE: Order 5 matches NEXT_REQUIRED"                │
│  ✅ P5 procede a deploy                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Test de Hotfix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TEST: Hotfix de Servicio Ya Completado                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PREPARACIÓN:                                                                │
│  1. Estado: NEXT_REQUIRED = "5", COMPLETED = "1,2,3,4"                      │
│                                                                              │
│  EJECUCIÓN:                                                                  │
│  1. Triggear pipeline 2 (glo_graph_service_build) como hotfix               │
│                                                                              │
│  RESULTADO ESPERADO:                                                         │
│  ✅ Read_State muestra: NEXT_REQUIRED=5, COMPLETED=1,2,3,4                  │
│  ✅ Validate_Order muestra: "HOTFIX MODE: Order 2 already in COMPLETED"     │
│  ✅ Pipeline procede a deploy SIN esperar                                   │
│  ✅ Update_State muestra: "Skipping state update (HOTFIX mode)"             │
│  ✅ Estado NO cambia: NEXT_REQUIRED=5, COMPLETED=1,2,3,4                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 Test de Release Completo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TEST: Release Completo 1→10                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PREPARACIÓN:                                                                │
│  1. Resetear estado: NEXT_REQUIRED = "1", COMPLETED = ""                    │
│  2. Preparar cambios en todos los repositorios                              │
│                                                                              │
│  EJECUCIÓN:                                                                  │
│  1. Triggear TODOS los pipelines simultáneamente (o en orden inverso)       │
│                                                                              │
│  RESULTADO ESPERADO:                                                         │
│  ✅ P1 ejecuta inmediatamente (order=1, NEXT=1)                             │
│  ✅ P2-P10 entran en polling                                                │
│  ✅ Cuando P1 completa, P2 detecta y ejecuta                                │
│  ✅ Secuencia continúa: P3, P4, ..., P10                                    │
│  ✅ Estado final: NEXT_REQUIRED=11, COMPLETED=1,2,3,4,5,6,7,8,9,10          │
│                                                                              │
│  MÉTRICAS A CAPTURAR:                                                        │
│  - Tiempo total de release                                                  │
│  - Tiempo promedio de espera en polling                                     │
│  - Consumo de API calls                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Fase 4: Operación

### 5.1 Ciclo de Vida del Release

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CICLO DE VIDA DEL RELEASE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ESTADO INICIAL (nuevo release)                                            │
│   ─────────────────────────────────                                         │
│   NEXT_REQUIRED = "1"                                                       │
│   COMPLETED = ""                                                            │
│                                                                              │
│                          │                                                   │
│                          ▼                                                   │
│                                                                              │
│   RELEASE EN PROGRESO                                                       │
│   ───────────────────────                                                   │
│   Pipeline 1 completa → NEXT=2, COMPLETED="1"                               │
│   Pipeline 2 completa → NEXT=3, COMPLETED="1,2"                             │
│   ...                                                                        │
│   Pipeline 9 completa → NEXT=10, COMPLETED="1,2,3,4,5,6,7,8,9"              │
│                                                                              │
│                          │                                                   │
│                          ▼                                                   │
│                                                                              │
│   RELEASE COMPLETADO                                                        │
│   ──────────────────────                                                    │
│   Pipeline 10 completa → NEXT=11, COMPLETED="1,2,3,4,5,6,7,8,9,10"          │
│                                                                              │
│   ⚠️  NEXT_REQUIRED = "11" indica que el release está COMPLETO              │
│       No hay pipeline 11, así que ningún pipeline puede proceder            │
│       hasta que se haga RESET para un nuevo release.                        │
│                                                                              │
│                          │                                                   │
│                          ▼                                                   │
│                                                                              │
│   RESET (para nuevo release)                                                │
│   ──────────────────────────                                                │
│   Ejecutar reset → NEXT=1, COMPLETED=""                                     │
│   Nuevo ciclo comienza                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Reset para Nuevo Release

**¿Cuándo hacer reset?**
- Después de que Pipeline 10 completa (`NEXT_REQUIRED = "11"`)
- Antes de iniciar un nuevo ciclo de despliegue coordinado

**Opciones para hacer reset:**

```bash
# Opción A: Via script
cd /workspace/docs/harness-platform/deployment-orchestration/scripts
./manual_reset.sh "2026-05-02-001"

# Opción B: Via pipeline reset_release
# Ejecutar pipeline: reset_release con input release_id="2026-05-02-001"

# Opción C: Via API directamente
curl -X PUT "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"variable":{"identifier":"STAGE_RELEASE_NEXT_REQUIRED","name":"STAGE_RELEASE_NEXT_REQUIRED","type":"String","value":"1"}}'

curl -X PUT "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"variable":{"identifier":"STAGE_RELEASE_COMPLETED","name":"STAGE_RELEASE_COMPLETED","type":"String","value":""}}'
```

### 5.3 Verificar Estado Actual

```bash
# Via script
./check_state.sh

# Output esperado:
# ==========================================
#    STAGE RELEASE STATE
# ==========================================
# 
# Release ID:     2026-05-01-001
# Next Required:  5
# Completed:      1,2,3,4
# 
# Service Status:
# ---------------
#    1. auth-backend              ✅ COMPLETED
#    2. graph-service             ✅ COMPLETED
#    3. ur-backend                ✅ COMPLETED
#    4. ur-core-ng                ✅ COMPLETED
#    5. notifications-backend     ⏳ NEXT (waiting)
#    6. oc-backend                ⏸️  PENDING
#    7. oc-bads-backend           ⏸️  PENDING
#    8. app-provider-fe           ⏸️  PENDING
#    9. manage-frontend-fe        ⏸️  PENDING
#   10. solutions-fe              ⏸️  PENDING
```

### 5.4 Desbloquear Pipeline Stuck

```bash
# Si un pipeline está bloqueando el flujo y necesitas saltarlo:

# 1. Verificar estado actual
./check_state.sh

# 2. Incrementar NEXT manualmente (salta el servicio bloqueado)
# ⚠️ USAR CON PRECAUCIÓN - el servicio saltado NO se desplegará
curl -X PUT "https://app.harness.io/gateway/ng/api/variables?accountIdentifier=${ACCOUNT_ID}" \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"variable":{"identifier":"STAGE_RELEASE_NEXT_REQUIRED","name":"STAGE_RELEASE_NEXT_REQUIRED","type":"String","value":"5"}}'

# 3. Actualizar COMPLETED (agregar el servicio saltado si corresponde)
# Solo si el servicio realmente se desplegó por otro medio
```

### 5.5 Monitoreo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  QUERIES DE MONITOREO                                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. Ver pipelines en espera (polling):                                       │
│     Harness UI → Deployments → Filter by status: "Running"                  │
│     Buscar pipelines con stage "Deployment_Gate" en ejecución               │
│                                                                              │
│  2. Ver historial de cambios de variables:                                   │
│     Account Settings → Audit Trail → Filter: "Variables"                    │
│                                                                              │
│  3. Ver tiempo de espera promedio:                                           │
│     Deployments → Pipeline → Execution History                              │
│     Columna "Duration" del stage Deployment_Gate                            │
│                                                                              │
│  4. Alertas sugeridas:                                                       │
│     - Pipeline en polling > 1 hora                                          │
│     - NEXT_REQUIRED sin cambio > 2 horas                                    │
│     - Más de 3 pipelines en polling simultáneamente                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Referencia Rápida

### 6.1 Comandos Frecuentes

```bash
# Ver estado actual
./scripts/check_state.sh

# Resetear para nuevo release
./scripts/manual_reset.sh "YYYY-MM-DD-NNN"

# Inicializar variables (solo primera vez)
./scripts/init_variables.sh
```

### 6.2 Variables de Pipeline

| Variable | Tipo | Dónde | Valor |
|----------|------|-------|-------|
| `deployment_order` | Pipeline Variable | Cada pipeline | "1" a "10" |
| `STAGE_RELEASE_NEXT_REQUIRED` | Account Variable | Harness Account | "1" a "11" |
| `STAGE_RELEASE_COMPLETED` | Account Variable | Harness Account | "" o "1,2,3,..." |
| `STAGE_RELEASE_ID` | Account Variable | Harness Account | "YYYY-MM-DD-NNN" |

### 6.3 Stages Nuevos

| Stage | Ubicación | Función |
|-------|-----------|---------|
| `Deployment_Gate` | Después de Build, antes de Deploy | Verifica turno, polling si necesario |
| `Update_State` | Último stage | Actualiza NEXT y COMPLETED |

### 6.4 Modos de Ejecución

| Modo | Condición | Comportamiento |
|------|-----------|----------------|
| **NORMAL** | `order == NEXT_REQUIRED` | Ejecuta, incrementa NEXT, agrega a COMPLETED |
| **HOTFIX** | `order < NEXT_REQUIRED && order in COMPLETED` | Ejecuta, NO modifica estado |
| **WAITING** | `order > NEXT_REQUIRED` | Polling cada 30s hasta que sea su turno |
| **ERROR** | `order < NEXT_REQUIRED && order NOT in COMPLETED` | Falla - estado inconsistente |

### 6.5 Troubleshooting

| Síntoma | Causa Probable | Solución |
|---------|----------------|----------|
| Pipeline stuck en polling | Pipeline anterior falló | Investigar y reintentar pipeline anterior |
| "Estado inconsistente" | Intervención manual incorrecta | Verificar y corregir COMPLETED |
| API timeout | Problemas de red/Harness | Reintentar, verificar status de Harness |
| Secret not found | API Key expirado o mal configurado | Regenerar y actualizar secret |

---

## Apéndice: Archivos de Referencia

- [Templates YAML](./templates/)
  - `deployment_gate_stage.yaml` - Stage de gate completo
  - `update_state_stage.yaml` - Stage de update completo
  - `reset_release_pipeline.yaml` - Pipeline de reset

- [Scripts](./scripts/)
  - `init_variables.sh` - Inicialización única
  - `check_state.sh` - Verificar estado
  - `manual_reset.sh` - Reset manual

- [Diagramas](./diagrams/)
  - `architecture.md` - Diagramas Mermaid

---

**Última actualización:** 2026-05-01

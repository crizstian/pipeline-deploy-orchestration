# Orquestación de Despliegues Secuenciales en Harness

## Documento Técnico: Estrategia Variables + Polling

**Versión:** 1.0  
**Fecha:** 2026-05-01  
**Audiencia:** DevOps Team  
**Estado:** Propuesta de Implementación

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Contexto y Problemática](#2-contexto-y-problemática)
3. [Análisis de Alternativas](#3-análisis-de-alternativas)
4. [Solución Propuesta: Variables + Polling](#4-solución-propuesta-variables--polling)
5. [Arquitectura de Ejecución](#5-arquitectura-de-ejecución)
6. [Simulación Dry-Run](#6-simulación-dry-run)
7. [Escenarios y Edge Cases](#7-escenarios-y-edge-cases)
8. [Guía de Implementación](#8-guía-de-implementación)
9. [Consideraciones Futuras](#9-consideraciones-futuras)
10. [FAQ](#10-faq)

---

## 1. Resumen Ejecutivo

### Problema
10 servicios en repositorios independientes deben desplegarse en **secuencia estricta** (1→2→3→...→10) debido a dependencias de API en runtime. En Stage environment, los pipelines no tienen Approval gate, ejecutándose inmediatamente al trigger, lo que genera **coordinación manual** entre equipos.

### Solución
Implementar **Variables + Polling** como mecanismo de control de flujo:
- Cada pipeline consulta un estado centralizado antes de desplegar
- Solo procede cuando es su turno según el orden definido
- Soporta hotfixes sin bloquear servicios pendientes

### Impacto
- **Elimina** coordinación manual entre equipos
- **Automatiza** el orden de despliegue
- **Reduce** riesgo de errores por despliegue fuera de secuencia
- **Mantiene** pipelines existentes con modificaciones mínimas

---

## 2. Contexto y Problemática

### 2.1 Arquitectura Actual

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         REPOSITORIOS INDEPENDIENTES                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   [Repo 1]     [Repo 2]     [Repo 3]    ...    [Repo 10]               │
│   auth-be      graph-svc    ur-be              solutions-fe            │
│      │            │           │                     │                   │
│      ▼            ▼           ▼                     ▼                   │
│   ┌──────┐    ┌──────┐    ┌──────┐            ┌──────┐                 │
│   │ P1   │    │ P2   │    │ P3   │    ...     │ P10  │                 │
│   └──────┘    └──────┘    └──────┘            └──────┘                 │
│                                                                          │
│   Cada pipeline se ejecuta INDEPENDIENTEMENTE al recibir trigger        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Servicios y Orden de Despliegue

| Orden | Pipeline | Proyecto | Tipo | Descripción |
|-------|----------|----------|------|-------------|
| 1 | `auth-backend` | Global_Services | Backend Go | Autenticación base |
| 2 | `glo_graph_service_build` | Global_Services | Backend + Neo4j | Servicio de grafos |
| 3 | `ur_backend_build` | Universal_Conciliator | Backend Python | Conciliador universal |
| 4 | `ur_core_ng_build` | Global_Services | AWS Batch | Core NG (escucha ECR) |
| 5 | `glo_notifications_backend` | Global_Services | Backend | Notificaciones |
| 6 | `oc_backend` | Global_Services | Backend Python | OC Backend |
| 7 | `oc_bads_backend` | Global_Services | Backend Python/UV | OC BADS |
| 8 | `glo_app_provider_build` | Global_Services | Frontend Node | App Provider |
| 9 | `manage_frontend_app_provider_build` | Global_Services | Frontend Node | Manage Frontend |
| 10 | `solutions_frontend_build` | Solutions_v2 | Frontend Node | Solutions MF |

### 2.3 El Problema Central

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ESCENARIO PROBLEMÁTICO                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   T0: Developer hace push a solutions-frontend (Servicio 10)            │
│       → Pipeline 10 se ejecuta inmediatamente                           │
│       → Solutions frontend se despliega                                 │
│       → ❌ FALLA: auth-backend (Servicio 1) no está actualizado         │
│                                                                          │
│   T1: Developer hace push a auth-backend (Servicio 1)                   │
│       → Pipeline 1 se ejecuta                                           │
│       → Auth backend se despliega                                       │
│       → ❌ Solutions frontend ya está corriendo con APIs incompatibles  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.4 Dependencias de Runtime

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CADENA DE DEPENDENCIAS                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   auth-backend ◄── graph-service ◄── ur-backend ◄── ur-core-ng         │
│        │                │                │              │                │
│        └────────────────┴────────────────┴──────────────┘                │
│                              │                                           │
│                              ▼                                           │
│                    notifications-backend                                 │
│                              │                                           │
│                              ▼                                           │
│              ┌───────────────┴───────────────┐                          │
│              │                               │                          │
│              ▼                               ▼                          │
│         oc-backend ◄───────────────── oc-bads-backend                   │
│              │                               │                          │
│              └───────────────┬───────────────┘                          │
│                              │                                           │
│                              ▼                                           │
│   ┌──────────────────────────┴──────────────────────────┐               │
│   │                                                      │               │
│   ▼                          ▼                          ▼               │
│ app-provider-fe      manage-frontend-fe        solutions-fe            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

REGLA: Un servicio N solo puede desplegarse si servicios 1..(N-1) ya
       están desplegados en la versión actual del release.
```

### 2.5 Requisitos de la Solución

| Requisito | Descripción | Prioridad |
|-----------|-------------|-----------|
| **R1** | Orden estricto 1→2→3→...→10 | Alta |
| **R2** | Sin coordinación manual | Alta |
| **R3** | Modificaciones mínimas a pipelines existentes | Alta |
| **R4** | Soporte para hotfixes | Alta |
| **R5** | Visibilidad del estado | Media |
| **R6** | Timeout configurable | Media |
| **R7** | Elementos nativos de Harness | Media |

---

## 3. Análisis de Alternativas

### 3.1 Estrategias Evaluadas

| # | Estrategia | Descripción |
|---|------------|-------------|
| 1 | Pipeline Orchestrator | Un pipeline padre ejecuta los 10 como stages |
| 2 | **Variables + Polling** | Estado centralizado + verificación periódica |
| 3 | Queue Step | Serialización FIFO con resource key |
| 4 | EventListener | Push-based: esperar evento del pipeline anterior |
| 5 | Barriers | Sincronización de stages paralelos |
| 6 | OPA Policies | Governance pre-ejecución |

### 3.2 Matriz de Evaluación

| Criterio | Orchestrator | Variables+Polling | Queue | EventListener | Barriers | OPA |
|----------|:------------:|:-----------------:|:-----:|:-------------:|:--------:|:---:|
| Modificación mínima | ❌ | ✅ | ✅ | ⚠️ | ❌ | ⚠️ |
| Orden semántico | ✅ | ✅ | ❌ | ⚠️ | ❌ | ❌ |
| Hotfix support | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Multi-proyecto | ❌ | ✅ | ✅ | ⚠️ | ❌ | ✅ |
| Estado persistente | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| CI + CD stages | ✅ | ✅ | ⚠️ | ❌ | ⚠️ | ✅ |
| Sin infra externa | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 3.3 Por qué NO las otras estrategias

#### Pipeline Orchestrator
```
❌ Requiere consolidar N triggers de cada pipeline en uno central
❌ Pierde independencia de repositorios
❌ Cambio arquitectural mayor
```

#### Queue Step
```
❌ FIFO ≠ Orden semántico
   Si P5 llega antes que P1, P5 adquiere el lock primero
❌ No maneja "esperar mi turno"
❌ No soporta hotfixes naturalmente
```

#### EventListener
```
❌ Solo funciona en Deploy/Custom stages
❌ Eventos se pierden si receptor no está escuchando
❌ Requiere estado persistente de todas formas
❌ Push-based: ¿quién notifica en hotfixes?
```

#### Barriers
```
❌ Solo sincroniza stages DENTRO del mismo pipeline
❌ Cross-pipeline barriers requiere feature flag y config adicional
❌ No aplica para pipelines independientes
```

#### OPA Policies
```
❌ Solo evaluación pre-ejecución
❌ No puede acceder a estado externo en runtime
❌ No puede "esperar" - solo aprobar/rechazar
```

### 3.4 Por qué Variables + Polling

```
✅ Estado persistente usando Harness Variables API (100% nativo)
✅ Funciona en CI y CD stages (Run step universal)
✅ Pull-based: cada pipeline verifica sin coordinación externa
✅ Hotfixes: detecta "ya completado" y ejecuta sin afectar el contador
✅ Modificación mínima: 2 stages adicionales por pipeline
✅ Multi-proyecto: Variables a nivel Account son compartidas
```

---

## 4. Solución Propuesta: Variables + Polling

### 4.1 Concepto Central

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     ESTADO CENTRALIZADO                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Harness Account Variables:                                            │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  STAGE_RELEASE_NEXT_REQUIRED = "3"                              │   │
│   │                                                                  │   │
│   │  → "El próximo servicio que DEBE desplegarse es el orden 3"    │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  STAGE_RELEASE_COMPLETED = "1,2"                                │   │
│   │                                                                  │   │
│   │  → "Los servicios 1 y 2 ya completaron su despliegue"          │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Lógica de Decisión

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      ALGORITMO DE DECISIÓN                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   INPUT:                                                                 │
│     MY_ORDER = orden del pipeline actual (ej: 5)                        │
│     NEXT_REQUIRED = valor de variable centralizada (ej: 3)              │
│     COMPLETED = lista de servicios completados (ej: "1,2")              │
│                                                                          │
│   LÓGICA:                                                               │
│                                                                          │
│   if MY_ORDER == NEXT_REQUIRED:                                         │
│       # FLUJO NORMAL: Es mi turno                                       │
│       → Ejecutar deployment                                             │
│       → NEXT_REQUIRED = MY_ORDER + 1                                    │
│       → COMPLETED = COMPLETED + "," + MY_ORDER                          │
│                                                                          │
│   elif MY_ORDER < NEXT_REQUIRED AND MY_ORDER in COMPLETED:              │
│       # HOTFIX: Ya desplegué antes, es un fix                          │
│       → Ejecutar deployment                                             │
│       → NO modificar NEXT_REQUIRED                                      │
│       → COMPLETED ya contiene MY_ORDER (sin cambio)                     │
│                                                                          │
│   elif MY_ORDER > NEXT_REQUIRED:                                        │
│       # ESPERANDO: Aún no es mi turno                                   │
│       → Polling loop hasta que MY_ORDER == NEXT_REQUIRED                │
│                                                                          │
│   else:                                                                  │
│       # ERROR: Estado inconsistente                                     │
│       → Fallar con mensaje descriptivo                                  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.3 Componentes de la Solución

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    COMPONENTES DEL SISTEMA                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   1. HARNESS VARIABLES (Account Level)                                  │
│      ├── STAGE_RELEASE_NEXT_REQUIRED: String ("1" - "11")              │
│      └── STAGE_RELEASE_COMPLETED: String ("1,2,3,...")                 │
│                                                                          │
│   2. DEPLOYMENT_GATE STAGE (por pipeline)                               │
│      ├── Step: Read_State                                               │
│      │   └── Consulta variables via API                                │
│      ├── Step: Validate_Order                                          │
│      │   └── Polling loop si no es su turno                            │
│      └── Step: Release_Gate                                            │
│          └── Log de confirmación                                        │
│                                                                          │
│   3. UPDATE_STATE STAGE (por pipeline)                                  │
│      ├── Step: Calculate_New_State                                     │
│      │   └── Determina si es flujo normal o hotfix                     │
│      └── Step: Write_State                                             │
│          └── Actualiza variables via API                                │
│                                                                          │
│   4. PIPELINE VARIABLES (por pipeline)                                  │
│      └── deployment_order: String (valor fijo: "1", "2", etc.)         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.4 Modificación a Pipelines Existentes

```yaml
# ANTES (Pipeline actual)
stages:
  - stage: Approval           # Solo en ciertos environments
  - stage: PR_Checks          # CI
  - stage: Branch_Checks      # CI
  - stage: Build              # CI/CD
  - stage: Deploy             # CD

# DESPUÉS (Pipeline modificado)
stages:
  - stage: Approval           # Sin cambio
  - stage: PR_Checks          # Sin cambio
  - stage: Branch_Checks      # Sin cambio
  - stage: Build              # Sin cambio
  - stage: Deployment_Gate    # ← NUEVO: Espera turno
  - stage: Deploy             # Sin cambio
  - stage: Update_State       # ← NUEVO: Actualiza estado
```

---

## 5. Arquitectura de Ejecución

### 5.1 Diagrama de Flujo General

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FLUJO DE EJECUCIÓN                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                         ┌──────────────┐                                │
│                         │   TRIGGER    │                                │
│                         │  (PR merge)  │                                │
│                         └──────┬───────┘                                │
│                                │                                        │
│                                ▼                                        │
│                    ┌───────────────────────┐                            │
│                    │    EXISTING STAGES    │                            │
│                    │  (Approval, PR, Build)│                            │
│                    └───────────┬───────────┘                            │
│                                │                                        │
│                                ▼                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                    DEPLOYMENT_GATE                              │   │
│   │  ┌─────────────────────────────────────────────────────────┐   │   │
│   │  │                                                          │   │   │
│   │  │  ┌──────────────┐    ┌──────────────────────────────┐   │   │   │
│   │  │  │  Read_State  │───►│ NEXT_REQUIRED=3, COMPLETED=1,2│   │   │   │
│   │  │  └──────────────┘    └──────────────────────────────┘   │   │   │
│   │  │         │                                                │   │   │
│   │  │         ▼                                                │   │   │
│   │  │  ┌──────────────────────────────────────────────────┐   │   │   │
│   │  │  │              Validate_Order                       │   │   │   │
│   │  │  │                                                   │   │   │   │
│   │  │  │  MY_ORDER == NEXT_REQUIRED?                       │   │   │   │
│   │  │  │      │                                            │   │   │   │
│   │  │  │      ├── YES ──► Continuar                        │   │   │   │
│   │  │  │      │                                            │   │   │   │
│   │  │  │      ├── NO (hotfix) ──► Continuar                │   │   │   │
│   │  │  │      │                                            │   │   │   │
│   │  │  │      └── NO (waiting) ──► Sleep 30s ──► Retry     │   │   │   │
│   │  │  │                                                   │   │   │   │
│   │  │  └──────────────────────────────────────────────────┘   │   │   │
│   │  │                                                          │   │   │
│   │  └─────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────┘   │
│                                │                                        │
│                                ▼                                        │
│                    ┌───────────────────────┐                            │
│                    │    DEPLOY STAGES      │                            │
│                    │  (Migrations, EKS,    │                            │
│                    │   CloudFront, etc.)   │                            │
│                    └───────────┬───────────┘                            │
│                                │                                        │
│                                ▼                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                      UPDATE_STATE                               │   │
│   │  ┌─────────────────────────────────────────────────────────┐   │   │
│   │  │                                                          │   │   │
│   │  │  ┌────────────────────┐                                  │   │   │
│   │  │  │ Calculate_New_State│                                  │   │   │
│   │  │  │                    │                                  │   │   │
│   │  │  │ if NORMAL_FLOW:    │                                  │   │   │
│   │  │  │   NEXT++ , add to  │                                  │   │   │
│   │  │  │   COMPLETED        │                                  │   │   │
│   │  │  │                    │                                  │   │   │
│   │  │  │ if HOTFIX:         │                                  │   │   │
│   │  │  │   no change        │                                  │   │   │
│   │  │  └────────────────────┘                                  │   │   │
│   │  │           │                                               │   │   │
│   │  │           ▼                                               │   │   │
│   │  │  ┌────────────────────┐                                  │   │   │
│   │  │  │    Write_State     │───► Harness Variables API        │   │   │
│   │  │  └────────────────────┘                                  │   │   │
│   │  │                                                          │   │   │
│   │  └─────────────────────────────────────────────────────────┘   │   │
│   └────────────────────────────────────────────────────────────────┘   │
│                                │                                        │
│                                ▼                                        │
│                         ┌──────────────┐                                │
│                         │   COMPLETE   │                                │
│                         └──────────────┘                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Diagrama de Secuencia

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SECUENCIA DE MÚLTIPLES PIPELINES                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   P1          P3          P5          Variables          Time           │
│   │           │           │              │                 │            │
│   │           │           │              │ NEXT=1          │            │
│   │           │           │              │ COMPLETED=""    │ T0         │
│   │           │           │              │                 │            │
│   │──trigger──┼───────────┼──────────────┼─────────────────│ T1         │
│   │           │──trigger──┼──────────────┼─────────────────│ T2         │
│   │           │           │──trigger─────┼─────────────────│ T3         │
│   │           │           │              │                 │            │
│   │──read────────────────────────────────►│                │            │
│   │◄─────────────────────NEXT=1──────────│                │            │
│   │                       │              │                 │            │
│   │  order=1 == NEXT=1   │              │                 │            │
│   │  ✓ PROCEED           │              │                 │            │
│   │           │           │              │                 │            │
│   │           │──read────────────────────►│                │            │
│   │           │◄──────────NEXT=1─────────│                │            │
│   │           │                          │                 │            │
│   │           │  order=3 > NEXT=1        │                 │            │
│   │           │  ⏳ POLLING...           │                 │            │
│   │           │           │              │                 │            │
│   │           │           │──read────────►│                │            │
│   │           │           │◄──NEXT=1─────│                │            │
│   │           │           │              │                 │            │
│   │           │           │  order=5 > 1 │                 │            │
│   │           │           │  ⏳ POLLING..│                 │            │
│   │           │           │              │                 │            │
│   │==DEPLOY===│           │              │                 │            │
│   │           │           │              │                 │            │
│   │──update──────────────────────────────►│                │            │
│   │           │           │              │ NEXT=2          │            │
│   │           │           │              │ COMPLETED="1"   │ T4         │
│   │           │           │              │                 │            │
│   │           │──poll─────────────────────►│               │            │
│   │           │◄──────────NEXT=2─────────│                │            │
│   │           │                          │                 │            │
│   │           │  order=3 > NEXT=2        │                 │            │
│   │           │  ⏳ POLLING...           │                 │            │
│   │           │           │              │                 │            │
│   │           │           │──poll────────►│                │            │
│   │           │           │◄──NEXT=2─────│                │            │
│   │           │           │              │                 │            │
│   │           │           │  order=5 > 2 │                 │            │
│   │           │           │  ⏳ POLLING..│                 │            │
│   │           │           │              │                 │            │
│   │     [P2 triggered, executes, NEXT=3, COMPLETED="1,2"]  │            │
│   │           │           │              │                 │            │
│   │           │──poll─────────────────────►│               │            │
│   │           │◄──────────NEXT=3─────────│                │            │
│   │           │                          │                 │            │
│   │           │  order=3 == NEXT=3       │                 │            │
│   │           │  ✓ PROCEED               │                 │            │
│   │           │           │              │                 │            │
│   │           │==DEPLOY===│              │                 │            │
│   │           │           │              │                 │            │
│   │           │──update──────────────────►│                │            │
│   │           │           │              │ NEXT=4          │            │
│   │           │           │              │ COMPLETED=      │ T5         │
│   │           │           │              │   "1,2,3"       │            │
│   │           │           │              │                 │            │
│                    ...continúa...                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Diagrama de Estados

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    MÁQUINA DE ESTADOS POR SERVICIO                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                                                                          │
│              ┌────────────────────────────────────────┐                 │
│              │                                        │                 │
│              ▼                                        │                 │
│   ┌─────────────────┐                                 │                 │
│   │    TRIGGERED    │                                 │                 │
│   │   (Pipeline     │                                 │                 │
│   │    iniciado)    │                                 │                 │
│   └────────┬────────┘                                 │                 │
│            │                                          │                 │
│            │ Read State                               │                 │
│            ▼                                          │                 │
│   ┌─────────────────┐                                 │                 │
│   │   EVALUATING    │                                 │                 │
│   │  (Verificando   │                                 │                 │
│   │    turno)       │                                 │                 │
│   └────────┬────────┘                                 │                 │
│            │                                          │                 │
│            ├───────────────────────────────────┐      │                 │
│            │                                   │      │                 │
│            │ MY_ORDER == NEXT_REQUIRED         │      │                 │
│            │ (Normal flow)                     │      │                 │
│            │                                   │      │                 │
│            │         MY_ORDER < NEXT_REQUIRED  │      │                 │
│            │         AND in COMPLETED          │      │                 │
│            │         (Hotfix flow)             │      │                 │
│            │                                   │      │                 │
│            ▼                                   ▼      │                 │
│   ┌─────────────────┐               ┌─────────────────┐                 │
│   │    EXECUTING    │               │    EXECUTING    │                 │
│   │   (Normal)      │               │    (Hotfix)     │                 │
│   └────────┬────────┘               └────────┬────────┘                 │
│            │                                  │                         │
│            │                                  │                         │
│            │ Deploy exitoso                   │ Deploy exitoso          │
│            ▼                                  ▼                         │
│   ┌─────────────────┐               ┌─────────────────┐                 │
│   │    UPDATING     │               │   SKIPPING      │                 │
│   │   (NEXT++,      │               │   UPDATE        │                 │
│   │    add COMPL)   │               │  (sin cambio)   │                 │
│   └────────┬────────┘               └────────┬────────┘                 │
│            │                                  │                         │
│            └─────────────┬───────────────────┘                         │
│                          │                                              │
│                          ▼                                              │
│                 ┌─────────────────┐                                     │
│                 │    COMPLETED    │                                     │
│                 └─────────────────┘                                     │
│                                                                          │
│                                                                          │
│   ┌─────────────────┐                                                   │
│   │    WAITING      │◄────────────────┐                                │
│   │   (Polling)     │                 │                                │
│   └────────┬────────┘                 │                                │
│            │                          │                                 │
│            │ Poll cada 30s            │ MY_ORDER > NEXT_REQUIRED        │
│            │                          │ (Aún no es mi turno)            │
│            ▼                          │                                 │
│   ┌─────────────────┐                 │                                │
│   │   CHECK_STATE   │─────────────────┘                                │
│   │                 │                                                   │
│   │  MY_ORDER ==    │                                                   │
│   │  NEXT_REQUIRED? │────► YES ────► EXECUTING                         │
│   └─────────────────┘                                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Simulación Dry-Run

### 6.1 Escenario: Release Normal (Todos los servicios)

**Estado Inicial:**
```
STAGE_RELEASE_NEXT_REQUIRED = "1"
STAGE_RELEASE_COMPLETED = ""
```

**Secuencia de Eventos:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DRY-RUN: RELEASE NORMAL                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  T    │ Evento                    │ NEXT │ COMPLETED    │ Status        │
│───────┼───────────────────────────┼──────┼──────────────┼───────────────│
│  T0   │ Estado inicial            │  1   │ ""           │               │
│  T1   │ P5 triggered              │  1   │ ""           │ P5: WAITING   │
│  T2   │ P3 triggered              │  1   │ ""           │ P3: WAITING   │
│  T3   │ P1 triggered              │  1   │ ""           │ P1: CHECK     │
│  T4   │ P1: order=1 == NEXT=1 ✓   │  1   │ ""           │ P1: EXECUTING │
│  T5   │ P1: Deploy complete       │  2   │ "1"          │ P1: DONE      │
│       │                           │      │              │ P3,P5: POLL   │
│  T6   │ P2 triggered              │  2   │ "1"          │ P2: CHECK     │
│  T7   │ P2: order=2 == NEXT=2 ✓   │  2   │ "1"          │ P2: EXECUTING │
│  T8   │ P2: Deploy complete       │  3   │ "1,2"        │ P2: DONE      │
│       │                           │      │              │ P3: POLL →✓   │
│  T9   │ P3: order=3 == NEXT=3 ✓   │  3   │ "1,2"        │ P3: EXECUTING │
│  T10  │ P3: Deploy complete       │  4   │ "1,2,3"      │ P3: DONE      │
│       │                           │      │              │ P5: POLLING   │
│  T11  │ P4 triggered              │  4   │ "1,2,3"      │ P4: CHECK     │
│  T12  │ P4: order=4 == NEXT=4 ✓   │  4   │ "1,2,3"      │ P4: EXECUTING │
│  T13  │ P4: Deploy complete       │  5   │ "1,2,3,4"    │ P4: DONE      │
│       │                           │      │              │ P5: POLL →✓   │
│  T14  │ P5: order=5 == NEXT=5 ✓   │  5   │ "1,2,3,4"    │ P5: EXECUTING │
│  T15  │ P5: Deploy complete       │  6   │ "1,2,3,4,5"  │ P5: DONE      │
│       │                           │      │              │               │
│  ...  │ [P6-P10 siguen igual]     │      │              │               │
│       │                           │      │              │               │
│  T25  │ P10: Deploy complete      │  11  │ "1,..,10"    │ ALL DONE      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Escenario: Hotfix después de despliegue parcial

**Estado Inicial:**
```
STAGE_RELEASE_NEXT_REQUIRED = "5"
STAGE_RELEASE_COMPLETED = "1,2,3,4"
```

**Secuencia de Eventos:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DRY-RUN: HOTFIX PARA SERVICIO 2                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  T    │ Evento                    │ NEXT │ COMPLETED    │ Status        │
│───────┼───────────────────────────┼──────┼──────────────┼───────────────│
│  T0   │ Estado: 1-4 completados   │  5   │ "1,2,3,4"    │ P5: WAITING   │
│       │ P5 está en polling        │      │              │               │
│       │                           │      │              │               │
│  T1   │ P2 hotfix triggered       │  5   │ "1,2,3,4"    │ P2: CHECK     │
│       │                           │      │              │               │
│  T2   │ P2: order=2 < NEXT=5      │  5   │ "1,2,3,4"    │               │
│       │ P2: "2" in COMPLETED ✓    │      │              │               │
│       │ P2: HOTFIX MODE           │      │              │ P2: EXECUTING │
│       │                           │      │              │               │
│  T3   │ P2: Deploy complete       │  5   │ "1,2,3,4"    │ P2: DONE      │
│       │ P2: NO incrementa NEXT    │      │              │ (sin cambio)  │
│       │ P2: COMPLETED sin cambio  │      │              │               │
│       │                           │      │              │               │
│  T4   │ P5: poll → order=5==NEXT  │  5   │ "1,2,3,4"    │ P5: CHECK →✓  │
│       │                           │      │              │               │
│  T5   │ P5: Deploy complete       │  6   │ "1,2,3,4,5"  │ P5: DONE      │
│       │                           │      │              │               │
│  ...  │ [P6-P10 continúan]        │      │              │               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

RESULTADO: El hotfix de P2 se desplegó sin afectar el flujo de P5.
           P5 no tuvo que esperar a que P2 "volviera a pasar".
```

### 6.3 Escenario: Múltiples Hotfixes Simultáneos

**Estado Inicial:**
```
STAGE_RELEASE_NEXT_REQUIRED = "7"
STAGE_RELEASE_COMPLETED = "1,2,3,4,5,6"
```

**Secuencia de Eventos:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                DRY-RUN: HOTFIXES SIMULTÁNEOS P1 Y P4                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  T    │ Evento                    │ NEXT │ COMPLETED      │ Status      │
│───────┼───────────────────────────┼──────┼────────────────┼─────────────│
│  T0   │ Estado: 1-6 completados   │  7   │ "1,2,3,4,5,6"  │ P7: WAITING │
│       │                           │      │                │             │
│  T1   │ P1 hotfix triggered       │  7   │ "1,2,3,4,5,6"  │ P1: CHECK   │
│  T2   │ P4 hotfix triggered       │  7   │ "1,2,3,4,5,6"  │ P4: CHECK   │
│       │                           │      │                │             │
│  T3   │ P1: order=1 < NEXT=7      │      │                │             │
│       │ P1: "1" in COMPLETED ✓    │      │                │             │
│       │ P1: HOTFIX MODE           │  7   │ "1,2,3,4,5,6"  │ P1: EXEC    │
│       │                           │      │                │             │
│  T4   │ P4: order=4 < NEXT=7      │      │                │             │
│       │ P4: "4" in COMPLETED ✓    │      │                │             │
│       │ P4: HOTFIX MODE           │  7   │ "1,2,3,4,5,6"  │ P4: EXEC    │
│       │                           │      │                │             │
│  T5   │ P1: Deploy complete       │  7   │ "1,2,3,4,5,6"  │ P1: DONE    │
│       │ (sin cambio en estado)    │      │                │             │
│       │                           │      │                │             │
│  T6   │ P4: Deploy complete       │  7   │ "1,2,3,4,5,6"  │ P4: DONE    │
│       │ (sin cambio en estado)    │      │                │             │
│       │                           │      │                │             │
│  T7   │ P7 triggered              │  7   │ "1,2,3,4,5,6"  │ P7: CHECK   │
│  T8   │ P7: order=7 == NEXT=7 ✓   │  7   │ "1,2,3,4,5,6"  │ P7: EXEC    │
│  T9   │ P7: Deploy complete       │  8   │ "1,..,7"       │ P7: DONE    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

RESULTADO: Ambos hotfixes (P1 y P4) se ejecutaron en paralelo.
           El flujo normal (P7) no fue afectado.
```

---

## 7. Escenarios y Edge Cases

### 7.1 Escenarios Cubiertos

| # | Escenario | Comportamiento |
|---|-----------|----------------|
| 1 | Release normal secuencial | Cada pipeline espera su turno, ejecuta, actualiza estado |
| 2 | Pipelines triggered fuera de orden | Los pipelines con orden > NEXT esperan en polling |
| 3 | Hotfix de servicio ya completado | Detecta HOTFIX MODE, ejecuta sin modificar NEXT |
| 4 | Múltiples hotfixes simultáneos | Cada hotfix ejecuta independientemente |
| 5 | Pipeline falla durante deploy | Estado NO se actualiza, se puede reintentar |
| 6 | Pipeline falla durante gate | No afecta a otros, se puede reintentar |
| 7 | Timeout de polling | Configurable, falla con mensaje descriptivo |

### 7.2 Edge Cases Documentados

#### EC-1: Pipeline duplicado (mismo servicio, doble trigger)

```
Situación: P3 se triggerea dos veces antes de completar la primera ejecución

Comportamiento:
  - Primera ejecución: espera su turno, ejecuta, actualiza estado
  - Segunda ejecución: cuando llega a Deployment_Gate:
    - order=3 < NEXT (porque ya se actualizó)
    - "3" in COMPLETED = true
    - HOTFIX MODE → ejecuta (es válido, puede ser un fix sobre el fix)

Mitigación: Si no es deseado, usar "Concurrency" en Harness 
            para limitar ejecuciones simultáneas del mismo pipeline.
```

#### EC-2: Estado inconsistente (NEXT > len(COMPLETED)+1)

```
Situación: NEXT=5, COMPLETED="1,3,4" (falta el 2)

Causa posible: Intervención manual o bug

Detección:
  - P2: order=2 < NEXT=5
  - P2: "2" NOT in COMPLETED
  - Ni es flujo normal ni hotfix
  - → ERROR: Estado inconsistente detectado

Resolución: Script de corrección manual o Reset del release
```

#### EC-3: Polling timeout (servicio anterior nunca completa)

```
Situación: P5 esperando, pero P4 falló y nadie lo reintenta

Comportamiento:
  - P5 hace polling por MAX_POLLING_TIME (configurable, default 4h)
  - Después de timeout: FAIL con mensaje:
    "Timeout esperando turno. NEXT_REQUIRED=4, MY_ORDER=5.
     Verifique estado del servicio 4."

Resolución: 
  - Investigar por qué P4 falló
  - Reintentar P4
  - O: reset del release si se decide no continuar
```

#### EC-4: Race condition en actualización de estado

```
Situación: P3 y P4 terminan casi al mismo tiempo

Riesgo: Ambos leen COMPLETED="1,2", ambos escriben, uno sobreescribe al otro

Mitigación: 
  - Usar PATCH atomico en la API de Variables
  - Implementar read-modify-write con verificación
  - O: Añadir Queue Step solo para el Update_State stage

Implementación recomendada:
  - Read current state
  - Calculate new state
  - Write with conditional (if NEXT still equals expected)
  - Retry if condition fails
```

#### EC-5: Reset de release (nuevo ciclo)

```
Situación: Completado release anterior, iniciar nuevo release

Acción requerida: Reset del estado

Opciones:
  A) Pipeline de Reset manual:
     - STAGE_RELEASE_NEXT_REQUIRED = "1"
     - STAGE_RELEASE_COMPLETED = ""
     - STAGE_RELEASE_ID = "2026-05-02-001"

  B) Reset automático al detectar nuevo release:
     - Primer pipeline detecta que todos COMPLETED y su código es nuevo
     - Inicia nuevo ciclo automáticamente

Recomendación: Opción A (explícito, auditable)
```

### 7.3 Limitaciones Conocidas

| Limitación | Impacto | Workaround |
|------------|---------|------------|
| Polling consume recursos | Bajo (1 request/30s) | Aumentar intervalo si necesario |
| Estado en Variables | Límite de tamaño | Usar JSON compacto |
| No hay UI visual del estado | Menor visibilidad | Dashboard custom o logs |
| Requiere API key en pipelines | Gestión de secrets | Usar Harness Secrets |

---

## 8. Guía de Implementación

### 8.1 Pre-requisitos

```
1. [ ] Harness API Key con permisos para Variables (Account level)
2. [ ] Secret configurado: account.HARNESS_API_KEY
3. [ ] Variables de cuenta creadas (ver 8.2)
4. [ ] Identificar punto de inserción en cada pipeline
```

### 8.2 Crear Variables de Estado

```bash
# Crear via API o UI de Harness

# Variable 1: Próximo servicio requerido
Name: STAGE_RELEASE_NEXT_REQUIRED
Type: String
Value: "1"
Scope: Account

# Variable 2: Lista de servicios completados
Name: STAGE_RELEASE_COMPLETED
Type: String
Value: ""
Scope: Account

# Variable 3 (opcional): ID del release actual
Name: STAGE_RELEASE_ID
Type: String
Value: "2026-05-01-001"
Scope: Account
```

### 8.3 Stage: Deployment_Gate

Ver archivo: [deployment_gate_stage.yaml](./templates/deployment_gate_stage.yaml)

### 8.4 Stage: Update_State

Ver archivo: [update_state_stage.yaml](./templates/update_state_stage.yaml)

### 8.5 Modificación por Pipeline

| Pipeline | Proyecto | Orden | Insertar Gate después de | Insertar Update después de |
|----------|----------|-------|--------------------------|---------------------------|
| auth-backend | Global_Services | 1 | Approval | Deploy_EKS |
| glo_graph_service_build | Global_Services | 2 | Approval | Deploy_graph_services |
| ur_backend_build | Universal_Conciliator | 3 | Approval | Deploy_EKS |
| ur_core_ng_build | Global_Services | 4 | PR_Checks | Build_and_Push |
| glo_notifications_backend | Global_Services | 5 | Approval | Deploy_EKS |
| oc_backend | Global_Services | 6 | Approval | Deploy_EKS |
| oc_bads_backend | Global_Services | 7 | Approval | Deploy_EKS |
| glo_app_provider_build | Global_Services | 8 | Approval | Deploy |
| manage_frontend_app_provider_build | Global_Services | 9 | Approval | Deploy_Cloudfront |
| solutions_frontend_build | Solutions_v2 | 10 | Approval | Deploy |

### 8.6 Rollout Plan

```
Fase 1: Preparación
  [ ] Crear variables de estado
  [ ] Crear secret con API key
  [ ] Crear templates de stages
  [ ] Documentar rollback plan

Fase 2: Pilot (1 pipeline)
  [ ] Seleccionar pipeline de bajo riesgo (ej: solutions_frontend_build)
  [ ] Implementar en ambiente de test
  [ ] Validar flujo completo
  [ ] Documentar issues encontrados

Fase 3: Rollout Gradual
  [ ] Implementar en pipelines 8, 9, 10 (frontends)
  [ ] Validar interacción entre ellos
  [ ] Implementar en pipelines 5, 6, 7 (backends secundarios)
  [ ] Validar flujo mixto
  [ ] Implementar en pipelines 1, 2, 3, 4 (core backends)

Fase 4: Validación Completa
  [ ] Ejecutar release completo 1→10
  [ ] Simular hotfix de servicio intermedio
  [ ] Validar timeout y recovery
  [ ] Documentar métricas y ajustes
```

---

## 9. Consideraciones Futuras

### 9.1 Esta solución es un puente, no el destino

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    EVOLUCIÓN RECOMENDADA                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   AHORA                          FUTURO                                  │
│   ─────                          ──────                                  │
│                                                                          │
│   Variables + Polling     →      Native CD Orchestration                │
│   (workaround táctico)           (solución estratégica)                 │
│                                                                          │
│   10 pipelines            →      Multi-Service Pipeline                 │
│   independientes                 con dependency graph                    │
│                                                                          │
│   Polling manual          →      Harness Barriers                       │
│                                  (cross-pipeline nativo)                │
│                                                                          │
│   Estado en Variables     →      Harness Service Dependency             │
│                                  DAG nativo                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Por qué Variables + Polling ahora

| Factor | Variables + Polling | Native CD |
|--------|---------------------|-----------|
| Tiempo de implementación | ~2 semanas | ~2 meses |
| Cambios a pipelines | Mínimos (2 stages) | Restructuración completa |
| Riesgo | Bajo | Medio-Alto |
| Curva de aprendizaje | Baja | Alta |
| Cobertura de requisitos | 100% | 100% |
| Deuda técnica | Media | Ninguna |
| Mantenibilidad | Media | Alta |

**Decisión:** Implementar Variables + Polling para resolver el problema inmediato, mientras se planifica la migración a Native CD en paralelo.

### 9.3 Roadmap hacia Native CD

```
Q2 2026: Variables + Polling (esta propuesta)
         ├── Eliminar coordinación manual
         ├── Automatizar orden de despliegue
         └── Estabilizar proceso de release

Q3 2026: Evaluación de Harness CD Native
         ├── Evaluar Service Dependencies
         ├── Evaluar Environment propagation
         └── POC con 2-3 servicios

Q4 2026: Migración Gradual
         ├── Migrar frontends a multi-environment pipeline
         ├── Migrar backends secundarios
         └── Validar con releases reales

Q1 2027: Full Native CD
         ├── Migrar core backends
         ├── Deprecar Variables + Polling
         └── Documentar arquitectura final
```

### 9.4 Harness Features a Evaluar

| Feature | Descripción | Relevancia |
|---------|-------------|------------|
| **Service Dependencies** | Definir DAG de dependencias entre servicios | Alta |
| **Environment Propagation** | Propagar deployments entre envs | Alta |
| **Pipeline Chains** | Ejecutar pipelines en secuencia nativa | Media |
| **Barriers (cross-pipeline)** | Sincronización entre pipelines | Alta |
| **Deployment Freeze** | Bloquear deployments en ventanas | Media |
| **GitOps** | ArgoCD integration | Futura |

---

## 10. FAQ

### Preguntas Generales

**Q: ¿Por qué no usar un Pipeline Orchestrator que llame a los 10 pipelines?**

A: Cada pipeline tiene N triggers configurados (PR merge, manual, scheduled). Consolidar todos los triggers en un orchestrator requeriría:
- Desactivar todos los triggers existentes
- Configurar el orchestrator para detectar cambios en 10 repos
- Perder la independencia de repositorios
- Mayor blast radius si el orchestrator falla

Variables + Polling mantiene los triggers existentes y añade control sin restructurar.

---

**Q: ¿Qué pasa si el servicio 4 nunca se despliega?**

A: Los servicios 5-10 quedarán en polling hasta el timeout configurado (default: 4 horas). Después del timeout:
- El pipeline falla con mensaje claro indicando qué servicio está bloqueando
- Se puede investigar y resolver el problema del servicio 4
- Una vez resuelto, los servicios pendientes detectarán el cambio en el siguiente poll

---

**Q: ¿Hay impacto en performance por el polling?**

A: Mínimo. Cada pipeline en espera hace 1 request HTTP cada 30 segundos a la API de Variables. Esto es:
- ~120 requests/hora por pipeline en espera
- Llamadas ligeras (solo lectura de 2 variables)
- No afecta la ejecución de otros stages

---

**Q: ¿Qué pasa si dos pipelines terminan exactamente al mismo tiempo?**

A: Existe un pequeño riesgo de race condition en la actualización del estado. Mitigaciones:
1. El orden semántico hace que esto sea raro (P3 no puede terminar antes que P2)
2. Si ocurre con hotfixes, ambos pueden proceder (hotfixes no modifican NEXT)
3. Para mayor seguridad, se puede añadir Queue Step solo en Update_State

---

**Q: ¿Cómo inicio un nuevo release cycle?**

A: Ejecutar el pipeline de Reset (o manualmente via API):
```bash
# Reset del estado
curl -X PUT "https://app.harness.io/v1/variables/STAGE_RELEASE_NEXT_REQUIRED" \
  -H "x-api-key: $API_KEY" \
  -d '{"value": "1"}'

curl -X PUT "https://app.harness.io/v1/variables/STAGE_RELEASE_COMPLETED" \
  -H "x-api-key: $API_KEY" \
  -d '{"value": ""}'
```

---

### Preguntas Técnicas

**Q: ¿Por qué usar Variables API en lugar de un ConfigMap o Secret externo?**

A: 
- Variables API es 100% nativa de Harness (sin infraestructura adicional)
- Scope Account permite compartir entre proyectos
- Auditable y versionable
- No requiere acceso a cluster Kubernetes
- Integración directa con pipelines

---

**Q: ¿Cómo manejo diferentes environments (dev, staging, prod)?**

A: Usar variables separadas por environment:
```
DEV_RELEASE_NEXT_REQUIRED
DEV_RELEASE_COMPLETED

STAGING_RELEASE_NEXT_REQUIRED
STAGING_RELEASE_COMPLETED

PROD_RELEASE_NEXT_REQUIRED
PROD_RELEASE_COMPLETED
```

El pipeline lee la variable correspondiente según `<+pipeline.variables.environment>`.

---

**Q: ¿Puedo saltarme un servicio si no tiene cambios?**

A: Sí, con dos opciones:

1. **Auto-skip**: El pipeline detecta que no hay cambios y ejecuta Update_State sin hacer deploy
2. **Manual skip**: Pipeline de gestión que actualiza NEXT sin ejecutar deploy

Recomendación: Auto-skip con detección de cambios via `git diff`.

---

**Q: ¿Qué logs debo monitorear?**

A: 
1. **Deployment_Gate/Validate_Order**: Ver el polling loop
2. **Update_State/Write_State**: Confirmar actualización del estado
3. **Variables API audit log**: Historial de cambios en el estado

Dashboard sugerido:
- Estado actual (NEXT, COMPLETED)
- Pipelines en espera (polling)
- Tiempo promedio de espera por servicio
- Hotfixes ejecutados

---

**Q: ¿Cómo hago rollback de un servicio específico?**

A: El rollback es ortogonal a esta orquestación:
1. El servicio hace rollback a versión anterior (proceso normal)
2. Si el rollback requiere que servicios dependientes también regresen:
   - Ejecutar hotfixes de esos servicios con versiones anteriores
   - El modo hotfix permite re-desplegar sin afectar el flujo

---

**Q: ¿Qué pasa si el polling loop tiene un bug y nunca detecta su turno?**

A: Protecciones implementadas:
1. **Timeout global**: El polling tiene un MAX_WAIT configurable
2. **Logs detallados**: Cada iteración logea el estado actual
3. **Fail-safe**: Si el estado leído es inconsistente, falla inmediatamente
4. **Alertas**: Integrar con Slack/PagerDuty si timeout ocurre

---

### Preguntas de Operación

**Q: ¿Cómo verifico el estado actual del release?**

A: 
```bash
# Via API
curl "https://app.harness.io/v1/variables?accountIdentifier=ACCOUNT_ID" \
  -H "x-api-key: $API_KEY" | jq '.[] | select(.name | startswith("STAGE_RELEASE"))'

# Via Harness UI
Account Settings → Account Resources → Variables
```

---

**Q: ¿Quién puede modificar las variables de estado?**

A: Configurar permisos en Harness:
- **Read**: Todos los pipelines (service accounts)
- **Write**: Solo pipelines (via service account) y admins
- **Delete**: Solo admins

---

**Q: ¿Cómo depuro un pipeline que está "stuck" en polling?**

A: 
1. Verificar qué valor tiene NEXT_REQUIRED
2. Identificar qué servicio debería actualizar NEXT
3. Revisar el estado de ese servicio:
   - ¿Está ejecutándose?
   - ¿Falló? ¿En qué stage?
   - ¿Necesita retry?
4. Si el servicio anterior completó pero NEXT no se actualizó:
   - Revisar logs de Update_State
   - Verificar conectividad a API
   - Actualizar manualmente si necesario

---

**Q: ¿Puedo probar la lógica sin hacer deploy real?**

A: Sí, crear pipelines de test:
1. Clonar pipeline existente
2. Reemplazar Deploy stages con `echo "Mock deploy"`
3. Ejecutar flujo completo
4. Verificar transiciones de estado

---

## Apéndices

- [Apéndice A: Templates YAML](./templates/)
- [Apéndice B: Scripts de Administración](./scripts/)
- [Apéndice C: Diagramas Mermaid](./diagrams/)
- [**Guía de Implementación Paso a Paso**](./IMPLEMENTATION_GUIDE.md) ← EMPEZAR AQUÍ

---

**Documento preparado por:** DevOps Team  
**Fecha de última actualización:** 2026-05-01  
**Próxima revisión:** 2026-05-15

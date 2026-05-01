# Modificaciones por Pipeline

## Resumen de Cambios

Para cada pipeline, se requiere:

1. **Agregar variable** `deployment_order` con el valor correspondiente
2. **Insertar stage** `Deployment_Gate` después de Approval (o después de PR_Checks si no hay Approval)
3. **Insertar stage** `Update_State` al final del pipeline

---

## Pipeline 1: auth-backend

**Proyecto:** Global_Services  
**Orden:** 1

### Variable a agregar:
```yaml
variables:
  # ... variables existentes ...
  - name: deployment_order
    type: String
    description: "Orden de despliegue para orquestación"
    required: true
    value: "1"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Build_and_Push              ├── Build_and_Push
├── Apply_Migrations            ├── [Deployment_Gate] ← INSERTAR
├── Deploy_Backend              ├── Apply_Migrations
├── Deploy_EKS                  ├── Deploy_Backend
                                ├── Deploy_EKS
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 2: glo_graph_service_build

**Proyecto:** Global_Services  
**Orden:** 2

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "2"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Stop_Graph_Services         ├── [Deployment_Gate] ← INSERTAR
├── Import_Data_Neo4j           ├── Stop_Graph_Services
├── Build_and_Push              ├── Import_Data_Neo4j
├── Apply_Schema_Neo4j          ├── Build_and_Push
├── Rollout_Graph_Services      ├── Apply_Schema_Neo4j
├── Deploy_graph_services       ├── Rollout_Graph_Services
                                ├── Deploy_graph_services
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 3: ur_backend_build

**Proyecto:** Universal_Conciliator  
**Orden:** 3

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "3"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks                   ├── PR_Checks
├── Branch_Checks               ├── Branch_Checks
├── IPM_Checks                  ├── IPM_Checks
├── Build (parallel)            ├── Build (parallel)
├── Migrations                  ├── [Deployment_Gate] ← INSERTAR
├── Custom_Commands             ├── Migrations
├── Deploy (parallel)           ├── Custom_Commands
├── Deploy_EKS                  ├── Deploy (parallel)
                                ├── Deploy_EKS
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 4: ur_core_ng_build

**Proyecto:** Global_Services  
**Orden:** 4  
**Nota:** Este pipeline NO tiene Approval stage

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "4"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── PR_Checks                   ├── PR_Checks
├── Build_and_Push              ├── [Deployment_Gate] ← INSERTAR
                                ├── Build_and_Push
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 5: glo_notifications_backend

**Proyecto:** Global_Services  
**Orden:** 5

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "5"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Env_Variables_Checks        ├── Env_Variables_Checks
├── Build                       ├── Build
├── Automate_Snapshot_DBs       ├── [Deployment_Gate] ← INSERTAR
├── Migrations                  ├── Automate_Snapshot_DBs
├── Deploy_EKS                  ├── Migrations
                                ├── Deploy_EKS
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 6: oc_backend

**Proyecto:** Global_Services  
**Orden:** 6

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "6"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Build_and_Push              ├── Build_and_Push
├── Apply_Migrations            ├── [Deployment_Gate] ← INSERTAR
├── Deploy_EKS                  ├── Apply_Migrations
                                ├── Deploy_EKS
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 7: oc_bads_backend

**Proyecto:** Global_Services  
**Orden:** 7

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "7"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Build_and_Push_Backend      ├── Build_and_Push_Backend
├── Automate_Snapshot_DBs       ├── [Deployment_Gate] ← INSERTAR
├── Apply_Migrations            ├── Automate_Snapshot_DBs
├── IPM_Sync                    ├── Apply_Migrations
├── Deploy_EKS                  ├── IPM_Sync
                                ├── Deploy_EKS
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 8: glo_app_provider_build

**Proyecto:** Global_Services  
**Orden:** 8

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "8"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Check_Environments          ├── Check_Environments
├── Build_APP_Provider          ├── Build_APP_Provider
├── Deploy                      ├── [Deployment_Gate] ← INSERTAR
                                ├── Deploy
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 9: manage_frontend_app_provider_build

**Proyecto:** Global_Services  
**Orden:** 9

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "9"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Build                       ├── Build
├── Deploy_Cloudfront           ├── [Deployment_Gate] ← INSERTAR
                                ├── Deploy_Cloudfront
                                └── [Update_State] ← INSERTAR
```

---

## Pipeline 10: solutions_frontend_build

**Proyecto:** Solutions_v2  
**Orden:** 10

### Variable a agregar:
```yaml
- name: deployment_order
  type: String
  value: "10"
```

### Ubicación de stages:
```
ANTES:                          DESPUÉS:
├── Approval                    ├── Approval
├── PR_Checks (parallel)        ├── PR_Checks (parallel)
├── Branch_Checks               ├── Branch_Checks
├── Env_Variables_Checks        ├── Env_Variables_Checks
├── Build_Solutions_MF          ├── Build_Solutions_MF
├── Deploy                      ├── [Deployment_Gate] ← INSERTAR
                                ├── Deploy
                                └── [Update_State] ← INSERTAR
```

---

## Checklist de Implementación

### Por cada pipeline:

- [ ] Agregar variable `deployment_order`
- [ ] Copiar template `deployment_gate_stage.yaml`
- [ ] Adaptar paths de variables según estructura del pipeline
- [ ] Copiar template `update_state_stage.yaml`
- [ ] Adaptar path a DEPLOYMENT_MODE del gate
- [ ] Probar en ambiente de desarrollo
- [ ] Validar con dry-run
- [ ] Desplegar en Stage

### Validación post-implementación:

- [ ] Ejecutar release completo 1→10
- [ ] Verificar logs de Deployment_Gate
- [ ] Verificar actualización de variables
- [ ] Simular hotfix de servicio intermedio
- [ ] Verificar timeout funciona correctamente

# Diagramas de Arquitectura

## 1. Flujo General de Orquestación

```mermaid
flowchart TB
    subgraph TRIGGER["🚀 Trigger"]
        T1[PR Merge]
        T2[Manual]
        T3[Schedule]
    end

    subgraph EXISTING["📦 Stages Existentes"]
        A[Approval]
        B[PR Checks]
        C[Branch Checks]
        D[Build]
    end

    subgraph GATE["🚧 Deployment Gate"]
        G1[Read State]
        G2{My Order == Next?}
        G3[Polling Loop]
        G4[Release Gate]
    end

    subgraph DEPLOY["🚢 Deploy Stages"]
        E1[Migrations]
        E2[Deploy EKS]
        E3[CloudFront]
    end

    subgraph UPDATE["📝 Update State"]
        U1{Mode?}
        U2[Increment Next]
        U3[Add to Completed]
        U4[Skip Update]
    end

    T1 & T2 & T3 --> A
    A --> B & C
    B & C --> D
    D --> G1

    G1 --> G2
    G2 -->|Yes| G4
    G2 -->|Hotfix| G4
    G2 -->|No - Waiting| G3
    G3 -->|30s| G1

    G4 --> E1
    E1 --> E2
    E2 --> E3
    E3 --> U1

    U1 -->|Normal| U2
    U2 --> U3
    U1 -->|Hotfix| U4

    style GATE fill:#f9f,stroke:#333,stroke-width:2px
    style UPDATE fill:#bbf,stroke:#333,stroke-width:2px
```

## 2. Máquina de Estados por Servicio

```mermaid
stateDiagram-v2
    [*] --> Triggered: Pipeline Start

    Triggered --> Evaluating: Read State

    Evaluating --> Executing_Normal: order == next_required
    Evaluating --> Executing_Hotfix: order < next && in completed
    Evaluating --> Waiting: order > next_required
    Evaluating --> Error: Inconsistent State

    Waiting --> Evaluating: Poll (30s)

    Executing_Normal --> Updating: Deploy Success
    Executing_Hotfix --> Complete: Deploy Success

    Updating --> Complete: State Written

    Complete --> [*]
    Error --> [*]

    note right of Waiting
        Polling cada 30s
        Timeout: 4 horas
    end note

    note right of Executing_Hotfix
        No modifica
        NEXT_REQUIRED
    end note
```

## 3. Secuencia de Release Normal

```mermaid
sequenceDiagram
    participant P1 as Pipeline 1
    participant P3 as Pipeline 3
    participant P5 as Pipeline 5
    participant VAR as Harness Variables

    Note over VAR: NEXT=1, COMPLETED=""

    P5->>+VAR: Read State
    VAR-->>-P5: NEXT=1
    Note over P5: order=5 > 1, WAIT

    P3->>+VAR: Read State
    VAR-->>-P3: NEXT=1
    Note over P3: order=3 > 1, WAIT

    P1->>+VAR: Read State
    VAR-->>-P1: NEXT=1
    Note over P1: order=1 == 1, PROCEED

    rect rgb(200, 255, 200)
        Note over P1: DEPLOYING...
    end

    P1->>VAR: Update(NEXT=2, COMPLETED="1")

    Note over VAR: NEXT=2, COMPLETED="1"

    P3-->>+VAR: Poll
    VAR-->>-P3: NEXT=2
    Note over P3: order=3 > 2, WAIT

    P5-->>+VAR: Poll
    VAR-->>-P5: NEXT=2
    Note over P5: order=5 > 2, WAIT

    Note over P1,VAR: [Pipeline 2 executes, NEXT=3]

    P3-->>+VAR: Poll
    VAR-->>-P3: NEXT=3
    Note over P3: order=3 == 3, PROCEED

    rect rgb(200, 255, 200)
        Note over P3: DEPLOYING...
    end

    P3->>VAR: Update(NEXT=4, COMPLETED="1,2,3")
```

## 4. Secuencia de Hotfix

```mermaid
sequenceDiagram
    participant P2 as Pipeline 2 (Hotfix)
    participant P5 as Pipeline 5 (Waiting)
    participant VAR as Harness Variables

    Note over VAR: NEXT=5, COMPLETED="1,2,3,4"
    Note over P5: Polling, waiting for NEXT=5

    rect rgb(255, 230, 200)
        Note over P2: Hotfix triggered!
    end

    P2->>+VAR: Read State
    VAR-->>-P2: NEXT=5, COMPLETED="1,2,3,4"

    Note over P2: order=2 < NEXT=5
    Note over P2: "2" in COMPLETED ✓
    Note over P2: HOTFIX MODE

    rect rgb(200, 255, 200)
        Note over P2: DEPLOYING HOTFIX...
    end

    Note over P2: Skip state update
    Note over VAR: State unchanged!

    P5-->>+VAR: Poll
    VAR-->>-P5: NEXT=5
    Note over P5: order=5 == 5, PROCEED

    rect rgb(200, 255, 200)
        Note over P5: DEPLOYING...
    end

    P5->>VAR: Update(NEXT=6, COMPLETED="1,2,3,4,5")
```

## 5. Arquitectura de Componentes

```mermaid
flowchart LR
    subgraph REPOS["Repositorios"]
        R1[(Repo 1)]
        R2[(Repo 2)]
        R3[(Repo N)]
    end

    subgraph PIPELINES["Harness Pipelines"]
        P1[Pipeline 1<br/>order=1]
        P2[Pipeline 2<br/>order=2]
        P3[Pipeline N<br/>order=N]
    end

    subgraph STATE["Estado Central"]
        V1[NEXT_REQUIRED]
        V2[COMPLETED]
        V3[RELEASE_ID]
    end

    subgraph DEPLOY["Infraestructura"]
        EKS[EKS Cluster]
        CF[CloudFront]
        ECR[ECR Registry]
    end

    R1 --> P1
    R2 --> P2
    R3 --> P3

    P1 <--> V1 & V2
    P2 <--> V1 & V2
    P3 <--> V1 & V2

    P1 --> EKS & ECR
    P2 --> EKS & ECR
    P3 --> CF & ECR

    style STATE fill:#f9f,stroke:#333,stroke-width:2px
```

## 6. Flujo de Decisión en Deployment Gate

```mermaid
flowchart TD
    START([Pipeline Triggered]) --> READ[Read Variables<br/>NEXT_REQUIRED, COMPLETED]

    READ --> CHECK{Compare<br/>MY_ORDER vs NEXT_REQUIRED}

    CHECK -->|order == next| NORMAL[/"NORMAL MODE<br/>Execute and Update"/]
    CHECK -->|order < next| HOTFIX_CHECK{order in<br/>COMPLETED?}
    CHECK -->|order > next| WAIT[/"WAITING MODE<br/>Enter Polling Loop"/]

    HOTFIX_CHECK -->|Yes| HOTFIX[/"HOTFIX MODE<br/>Execute, No Update"/]
    HOTFIX_CHECK -->|No| ERROR[/"ERROR<br/>Inconsistent State"/]

    WAIT --> SLEEP[Sleep 30s]
    SLEEP --> TIMEOUT{Elapsed ><br/>MAX_WAIT?}
    TIMEOUT -->|No| READ
    TIMEOUT -->|Yes| FAIL[/"TIMEOUT<br/>Fail Pipeline"/]

    NORMAL --> DEPLOY([Continue to Deploy])
    HOTFIX --> DEPLOY
    ERROR --> STOP([Fail Pipeline])
    FAIL --> STOP

    style NORMAL fill:#9f9,stroke:#333
    style HOTFIX fill:#ff9,stroke:#333
    style WAIT fill:#9ff,stroke:#333
    style ERROR fill:#f99,stroke:#333
```

## 7. Timeline de Release Completo

```mermaid
gantt
    title Release Timeline con Orquestación
    dateFormat  HH:mm
    axisFormat %H:%M

    section Service 1
    Build & Test        :a1, 09:00, 15m
    Deploy Gate (pass)  :a2, after a1, 1m
    Deploy              :a3, after a2, 10m
    Update State        :a4, after a3, 1m

    section Service 2
    Build & Test        :b1, 09:05, 15m
    Deploy Gate (wait)  :b2, after b1, 11m
    Deploy              :b3, after b2, 8m
    Update State        :b4, after b3, 1m

    section Service 3
    Build & Test        :c1, 09:10, 15m
    Deploy Gate (wait)  :c2, after c1, 20m
    Deploy              :c3, after c2, 12m
    Update State        :c4, after c3, 1m

    section Service 5
    Build & Test        :d1, 09:00, 20m
    Deploy Gate (wait)  :d2, after d1, 45m
    Deploy              :d3, after d2, 10m
    Update State        :d4, after d3, 1m
```

## 8. Flujo de Error y Recovery

```mermaid
flowchart TD
    DEPLOY[Deploy Stage] --> RESULT{Deploy<br/>Success?}

    RESULT -->|Yes| UPDATE[Update State]
    RESULT -->|No| FAIL[Pipeline Failed]

    FAIL --> NOTIFY[Notify Team]
    NOTIFY --> INVESTIGATE[Investigate Issue]
    INVESTIGATE --> FIX[Fix Issue]
    FIX --> RETRY{Retry<br/>Pipeline}

    RETRY --> GATE[Deployment Gate]
    GATE --> CHECK{State<br/>Check}

    CHECK -->|Same order as NEXT| PROCEED[Proceed with Deploy]
    CHECK -->|Order in COMPLETED| HOTFIX_MODE[Hotfix Mode<br/>Re-deploy]

    PROCEED --> DEPLOY
    HOTFIX_MODE --> DEPLOY

    UPDATE --> NEXT_PIPELINE[Next Pipeline<br/>Detects Change]

    style FAIL fill:#f99
    style UPDATE fill:#9f9
    style HOTFIX_MODE fill:#ff9
```

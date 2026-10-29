# Prometheus OTLP Receiver Lab

Lab per testare l'invio di metriche in **push** da applicazioni Quarkus verso Prometheus, utilizzando il protocollo **OpenTelemetry (OTLP)** e il receiver nativo di Prometheus 3.x.

Sono presenti **due applicazioni** che usano approcci diversi per l'export delle metriche:

| App | Approccio | Estensione Quarkus | Versione |
|-----|-----------|--------------------|----------|
| `quarkus-metrics-app` | OpenTelemetry SDK diretto | `quarkus-opentelemetry` + `opentelemetry-exporter-otlp` | Quarkus 3.23.0 |
| `quarkus-micrometer-app` | Micrometer con bridge OTel | `quarkus-micrometer-opentelemetry` | Quarkus 3.23.0 |

Entrambe inviano metriche via OTLP HTTP push allo stesso Prometheus ed e' possibile distinguerle tramite la label `job` (che corrisponde al `service.name` OTel).

## Architettura

```
┌──────────────────────────────────────────────────────────────────┐
│                         Kind Cluster                             │
│                                                                  │
│  ┌──────────────────────┐                                        │
│  │ quarkus-metrics-app  │    OTLP HTTP push    ┌──────────────┐  │
│  │ (OTel SDK diretto)   ├─────────────────────►│  Prometheus  │  │
│  │ job: quarkus-metrics │                      │   3.15.0     │  │
│  └──────────────────────┘                      │              │  │
│                                                │ OTLP receiver│  │
│  ┌──────────────────────┐                      │ abilitato    │  │
│  │quarkus-micrometer-app│    OTLP HTTP push    │              │  │
│  │ (Micrometer + OTel)  ├─────────────────────►│ /api/v1/otlp/│  │
│  │ job: quarkus-microm. │                      │  v1/metrics  │  │
│  └──────────────────────┘                      └──────┬───────┘  │
│                                                       │          │
│  ┌──────────────────────┐                             │          │
│  │  Prometheus Operator │  gestisce CR Prometheus     │          │
│  └──────────────────────┘                             │          │
└───────────────────────────────────────────────────────┼──────────┘
                                                        │
                                               NodePort 30090
                                                        │
                                                 ┌──────┴───────┐
                                                 │ Browser/curl │
                                                 │ localhost:   │
                                                 │    30090     │
                                                 └──────────────┘
```

## Prerequisiti

| Tool      | Versione testata | Note                         |
|-----------|------------------|------------------------------|
| Kind      | v0.26.0          |                              |
| Podman    | 5.5.0            | Usato come runtime container |
| kubectl   | v1.30.0          |                              |
| Helm      | v3.14.4          |                              |
| Java      | 21               | OpenJDK                      |
| Maven     | 3.x              |                              |

> **Nota:** Il progetto usa Podman al posto di Docker. Il Makefile imposta `KIND_EXPERIMENTAL_PROVIDER=podman` per la compatibilita' con Kind.

## Struttura del progetto

```
prometheus-otlp-receiver-lab/
├── Makefile                                  # Automazione completa del lab
├── kind/
│   └── kind-config.yaml                      # Cluster Kind single-node con porta 30090
├── prometheus/
│   └── values.yaml                           # Helm values per kube-prometheus-stack
├── quarkus-metrics-app/                      # App 1: OpenTelemetry SDK diretto
│   ├── pom.xml                               #   Quarkus 3.23.0 + quarkus-opentelemetry
│   ├── src/main/java/com/example/
│   │   ├── GreetingResource.java             #   Counter via OTel Meter API
│   │   └── HealthResource.java               #   Health endpoint per le probe K8s
│   ├── src/main/resources/
│   │   └── application.properties
│   ├── src/main/docker/
│   │   └── Dockerfile.jvm
│   └── k8s/
│       └── deployment.yaml
└── quarkus-micrometer-app/                   # App 2: Micrometer + OTel bridge
    ├── pom.xml                               #   Quarkus 3.23.0 + quarkus-micrometer-opentelemetry (min 3.19+)
    ├── src/main/java/com/example/
    │   ├── GreetingResource.java             #   Counter via @Counted annotation
    │   └── HealthResource.java
    ├── src/main/resources/
    │   └── application.properties
    ├── src/main/docker/
    │   └── Dockerfile.jvm
    └── k8s/
        └── deployment.yaml
```

## Quick Start

Creare l'intero lab con un singolo comando:

```bash
make all
```

Questo esegue in sequenza: creazione cluster Kind, installazione Prometheus, build di entrambe le app, caricamento immagini nel cluster e deploy.

Al termine:
- **Prometheus UI**: http://localhost:30090

## Comandi disponibili

| Comando                | Descrizione                                           |
|------------------------|-------------------------------------------------------|
| `make all`             | Setup completo (cluster + Prometheus + entrambe le app) |
| `make cluster-create`  | Crea il cluster Kind                                  |
| `make prometheus-install` | Installa kube-prometheus-stack via Helm            |
| `make app-build`       | Build di entrambe le app                              |
| `make app-load`        | Carica entrambe le immagini nel cluster Kind          |
| `make app-deploy`      | Deploy di entrambe le app su Kubernetes               |
| `make app1-build`      | Build solo quarkus-metrics-app (OTel SDK)             |
| `make app2-build`      | Build solo quarkus-micrometer-app (Micrometer)        |
| `make test`            | Invia 5+5 richieste e verifica le metriche            |
| `make clean`           | Distrugge il cluster Kind                             |

## Come funziona

### 1. Cluster Kind

Il file `kind/kind-config.yaml` configura un cluster single-node con `extraPortMappings` che mappa la porta **30090** dell'host sul nodo Kind, permettendo di raggiungere Prometheus da `localhost:30090`.

### 2. Prometheus con OTLP Receiver

Prometheus viene installato tramite il chart Helm **kube-prometheus-stack** nel namespace `monitoring`. La configurazione in `prometheus/values.yaml` abilita:

- **`--web.enable-otlp-receiver`**: attiva l'endpoint OTLP nativo di Prometheus 3.x, che espone `POST /api/v1/otlp/v1/metrics` sulla stessa porta del server (9090)
- **NodePort 30090**: espone Prometheus all'esterno del cluster
- Componenti non necessari (Grafana, Alertmanager, node-exporter, ecc.) sono disabilitati per velocizzare il lab

Il chart Helm genera la seguente **Custom Resource `Prometheus`** (gestita dal Prometheus Operator), qui riportata nei campi essenziali:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: kube-prometheus-stack-prometheus
  namespace: monitoring
spec:
  image: quay.io/prometheus/prometheus:v3.15.0-distroless
  version: v3.15.0-distroless
  replicas: 1
  retention: 10d
  scrapeInterval: 30s
  evaluationInterval: 30s

  # Abilita l'endpoint OTLP nativo (POST /api/v1/otlp/v1/metrics)
  additionalArgs:
    - name: web.enable-otlp-receiver

  # Abilita il remote write receiver (utile per debug)
  enableRemoteWriteReceiver: true

  # Selettori per ServiceMonitor, PodMonitor, ProbeSelector e Rule
  serviceMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  podMonitorSelector:
    matchLabels:
      release: kube-prometheus-stack
  ruleSelector:
    matchLabels:
      release: kube-prometheus-stack

  walCompression: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
```

La CR completa puo' essere ispezionata con:

```bash
kubectl get prometheus -n monitoring -o yaml
```

> **Nota su Prometheus 3.x**: nelle versioni precedenti (2.47-2.x) si usava `--enable-feature=otlp-write-receiver`. Da Prometheus 3.0 in poi, il flag corretto e' `--web.enable-otlp-receiver`.

> **Staleness e `--query.lookback-delta`**: con il push OTLP (a differenza dello scrape tradizionale), Prometheus non riceve un segnale esplicito quando un pod smette di inviare metriche. Una serie temporale viene considerata "stale" se non riceve nuovi campioni entro il *lookback delta*, che di default e' **5 minuti**. Questo significa che dopo un redeploy si possono vedere temporaneamente sia le metriche del vecchio pod che quelle del nuovo. Il parametro e' configurabile tramite il flag `--query.lookback-delta`. Nel Helm chart si puo' aggiungere in `prometheus.prometheusSpec.additionalArgs`, ad esempio per ridurlo a 2 minuti:
>
> ```yaml
> prometheus:
>   prometheusSpec:
>     additionalArgs:
>       - name: query.lookback-delta
>         value: 2m
> ```

### 3. App 1: quarkus-metrics-app (OpenTelemetry SDK diretto)

Usa le API native di OpenTelemetry per creare metriche custom:

```java
@Inject
public GreetingResource(OpenTelemetry openTelemetry) {
    Meter meter = openTelemetry.getMeter("com.example.quarkus-metrics-app");
    this.requestCounter = meter.counterBuilder("hello_requests")
            .setDescription("Number of hello requests")
            .build();
}
```

Dipendenze:
- `quarkus-opentelemetry` — integra l'OpenTelemetry SDK nel runtime Quarkus
- `opentelemetry-exporter-otlp` — exporter OTLP standard (basato su OkHttp)

L'exporter e' configurato con `quarkus.otel.metrics.exporter=otlp` e il protocollo `http/protobuf`.

### 4. App 2: quarkus-micrometer-app (Micrometer + OTel bridge)

Usa l'annotazione Micrometer `@Counted` per contare le invocazioni:

```java
@GET
@Counted(value = "hello_requests", description = "Number of hello endpoint requests")
public String hello() {
    return "Hello from Quarkus with Micrometer + OTel bridge!";
}
```

Dipendenza unica:
- `quarkus-micrometer-opentelemetry` — include Micrometer, OpenTelemetry SDK e il bridge che converte le metriche Micrometer in segnali OTel, esportandole via OTLP

> **Versione minima:** L'estensione `quarkus-micrometer-opentelemetry` e' disponibile **da Quarkus 3.19 in poi** (prima release: 3.20.1). Non esiste nelle versioni 3.18 e precedenti. Se si usa una versione di Quarkus anteriore alla 3.19, l'unica opzione per esportare metriche via OTLP e' l'approccio con OTel SDK diretto (app 1).

Il bridge converte automaticamente i meter Micrometer in metriche OpenTelemetry, che vengono poi esportate via OTLP verso Prometheus.

### 5. Differenze tra i due approcci

| | OTel SDK diretto | Micrometer + OTel bridge |
|---|---|---|
| **API per le metriche** | `io.opentelemetry.api.metrics.*` | `io.micrometer.core.annotation.*` |
| **Creazione counter** | Programmatica (`counterBuilder`) | Dichiarativa (`@Counted`) |
| **Label automatiche** | Nessuna | `class`, `method`, `exception`, `result` |
| **Quarkus minima** | 3.x | 3.19+ (prima release 3.20.1) |
| **Dipendenze extra** | `opentelemetry-exporter-otlp` (OkHttp) | Nessuna (tutto incluso nell'estensione) |

### 6. Flusso delle metriche

1. Le app raccolgono metriche (via OTel API o Micrometer)
2. Ogni **10 secondi**, l'exporter OTLP invia un batch in formato **protobuf** via HTTP POST
3. Prometheus riceve le metriche sull'endpoint `/api/v1/otlp/v1/metrics` e le salva nel TSDB
4. Le metriche sono interrogabili via PromQL dalla UI o dall'API, filtrabili per `job`

## Verifica

Eseguire il test automatizzato:

```bash
make test
```

Oppure manualmente:

```bash
# Traffico verso app 1 (OTel SDK)
kubectl exec $(kubectl get pod -l app=quarkus-metrics-app -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://localhost:8080/hello

# Traffico verso app 2 (Micrometer)
kubectl exec $(kubectl get pod -l app=quarkus-micrometer-app -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s http://localhost:8080/hello
```

### Query PromQL per distinguere le app

```promql
# Metriche solo dall'app OTel SDK
hello_requests_total{job="quarkus-metrics-app"}

# Metriche solo dall'app Micrometer
hello_requests_total{job="quarkus-micrometer-app"}

# Confronto side-by-side
hello_requests_total
```

### Metriche attese in Prometheus

| Metrica               | App                 | Label aggiuntive                        |
|-----------------------|---------------------|-----------------------------------------|
| `hello_requests_total`| quarkus-metrics-app | `job`                                   |
| `hello_requests_total`| quarkus-micrometer-app | `job`, `class`, `method`, `exception`, `result` |
| `target_info`         | entrambe            | `job`, `host_name`, `telemetry_sdk_version`, `webengine_version` |

La metrica `target_info` mostra anche le versioni di Quarkus e dell'OpenTelemetry SDK usate da ciascuna app.

## Cleanup

```bash
make clean
```

Distrugge il cluster Kind e tutte le risorse associate.

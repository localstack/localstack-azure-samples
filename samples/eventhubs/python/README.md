# Real-time payment fraud detection with Azure Event Hubs

A streaming platform in miniature, running entirely on LocalStack for Azure. Payments
arrive from three different kinds of producer, a serverless processor scores them for
fraud in real time, alerts flow onto a second stream, and every event is archived to a
data lake without a line of code being written for it.

The sample is built around the properties that make Event Hubs different from a queue:
**one log, many protocols, many independent readers, and a replayable history**.

## Architecture

```
  Producers (outside Azure)                LocalStack for Azure
  ┌───────────────────────┐        ┌──────────────────────────────────────────────┐
  │ POS terminals         │  AMQP  │  Event Hubs namespace (Standard, Kafka on)   │
  │ producer_amqp.py      ├───────►│                                              │
  │                       │        │   payments hub ─ 4 partitions ─── Capture ───┼──► Blob Storage
  │ Legacy gateway        │ Kafka  │     consumer groups:                         │    Avro archives
  │ producer_kafka.py     ├───────►│       fraud-detector ──┐  analytics  audit   │    (cold path)
  │                       │        │                        │                     │
  │ ATM / IoT devices     │ HTTPS  │                        ▼                     │
  │ producer_http.py      ├───────►│              Function App (Python)           │
  └───────────────────────┘        │              Event Hubs trigger              │
                                   │              fraud rules ──────┐             │
                                   │                                ▼             │
                                   │   fraud-alerts hub ─ 2 partitions            │
                                   │                                ▲             │
                                   │   Key Vault: connection strings │            │
                                   │   Schema Registry: Avro contract│            │
                                   │   App Insights + Log Analytics  │            │
                                   │                                 │            │
                                   │   Web App ── operations dashboard            │
                                   └──────────────────────────────────────────────┘
```

**Deployment flow.** The deploy script creates Log Analytics and Application Insights, a
storage account with the Capture container, the Event Hubs namespace with both hubs, three
consumer groups, least-privilege authorization rules and a Schema Registry group; stores
the connection strings in Key Vault; then deploys the Function App and the dashboard Web
App.

**At runtime.** Producers publish payments over AMQP, Kafka and HTTPS to the same hub. The
Function App's Event Hubs trigger reads the `fraud-detector` consumer group in batches,
applies the fraud rules, and writes alerts to the `fraud-alerts` hub through an output
binding. Event Hubs Capture independently archives everything to Blob Storage as Avro. The
dashboard reads the runtime state of both hubs, the checkpoints, the archives and the
schema registry.

## What this demonstrates

| Capability | Where to see it |
|------------|-----------------|
| **Multi-protocol ingestion** - AMQP 1.0, Kafka and HTTPS into one hub | `src/producers/`, step 2 of `run-pipeline.sh` |
| **Kafka compatibility** - an existing librdkafka app with no Azure SDK | `src/producers/producer_kafka.py` |
| **Partition keys and ordering** - all of an account's payments on one partition | `producer_amqp.py`, the velocity rule in `function_app.py` |
| **Consumer groups** - three independent readers of the same stream | `deploy.sh` step 6 |
| **Serverless stream processing** - Event Hubs trigger, batched | `src/functions/function_app.py` |
| **Checkpointing and recovery** - restart resumes where it left off | Step 4 of `run-pipeline.sh` |
| **Event Hubs Capture** - Avro archives to Blob Storage, no consumer code | Step 5 of `run-pipeline.sh`, `scripts/read_capture.py` |
| **Schema Registry** - a versioned Avro contract | `src/producers/schema_register.py` |
| **Least-privilege SAS** - send-only and listen-only rules | `deploy.sh` step 7, `validate.sh` check 5 |
| **Auto-inflate** - throughput units scale with ingress | `deploy.sh` step 4 |
| **Geo-disaster recovery** - namespace pairing behind an alias | `validate.sh` check 11 |
| **Application groups** - client throttling policies | `validate.sh` check 10 |
| **Service integration** - Event Hubs with Storage, Key Vault, Functions, App Service, Monitor | the whole sample |

## Prerequisites

- [LocalStack](https://docs.localstack.cloud/getting-started/installation/) with a valid
  `LOCALSTACK_AUTH_TOKEN`
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and
  [azlocal](https://pypi.org/project/azlocal/) (`pip install azlocal`)
- Python 3.12+ with `src/producers/requirements.txt` installed
- `jq` and `zip`
- [Terraform](https://developer.hashicorp.com/terraform/downloads) or the Bicep CLI, for
  the alternative deployments

## Quick start

```bash
# Start the LocalStack Azure emulator
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure localstack start -d
localstack wait -t 120

# Route the Azure CLI to the emulator
azlocal start-interception

cd samples/eventhubs/python
pip install -r src/producers/requirements.txt

bash scripts/deploy.sh        # create the pipeline
bash scripts/validate.sh      # verify every capability
bash scripts/run-pipeline.sh  # run the end-to-end demo
```

Then open the dashboard URL printed at the end of the deployment.

> **Note**
> The first deployment downloads the Azure Functions build image and core tools inside the
> emulator, which can take several minutes. Later runs reuse them.

## Alternative deployments

```bash
bash bicep/deploy.sh        # Bicep
bash terraform/deploy.sh    # Terraform
```

Both provision the same topology and then publish the same application packages.

## The demo, step by step

`scripts/run-pipeline.sh` walks through the whole story:

1. **Publish the contract.** The Avro payment schema is registered in the Schema Registry
   and read back by id, the way a serializer resolves one at runtime.
2. **Ingest over three protocols.** 40 payments over AMQP (keyed by account, plus a burst
   that trips the velocity rule), 15 over Kafka, 8 over HTTPS. The partition counts show
   they all landed in the same log.
3. **Detect fraud.** The Function App picks up each batch, applies the amount and velocity
   rules, and emits alerts to `fraud-alerts`.
4. **Prove checkpointing.** The function app is restarted while new payments arrive. It
   resumes from its checkpoint: nothing is lost and nothing is processed twice.
5. **Read the archive.** Once a Capture window flushes, the newest Avro blob is decoded
   and its records printed - the cold path, with no consumer code.
6. **Point at the dashboard** for the live view.

## Application

### Producers (`src/producers/`)

| File | Role |
|------|------|
| `common.py` | Shared config, the Avro contract, the payment generator |
| `producer_amqp.py` | POS terminals - official SDK, batches, partition keys |
| `producer_kafka.py` | Legacy gateway - confluent-kafka, bootstrap derived from the connection string |
| `producer_http.py` | ATM/IoT - HTTP runtime API with a hand-built SAS token |
| `schema_register.py` | Registers and resolves the Avro contract |

### Processor (`src/functions/`)

`function_app.py` is an Event Hubs-triggered function with an Event Hubs output binding.
Two rules: an amount threshold, and a per-account velocity window that is only correct
because producers key events by account, which pins each account to one partition.

### Dashboard (`src/dashboard/`)

A Flask app that polls the Event Hubs runtime API, the checkpoint blobs, the alerts hub,
the Capture container and the Schema Registry, and refreshes every five seconds.

| Route | Description |
|-------|-------------|
| `/` | The dashboard |
| `/api/overview` | JSON snapshot of the whole pipeline |
| `/health` | Health check |

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/deploy.sh` | Creates the full topology and deploys both workloads |
| `scripts/validate.sh` | Numbered checks over the control plane, data plane and bonus capabilities |
| `scripts/run-pipeline.sh` | The end-to-end demo |
| `scripts/cleanup.sh` | Deletes the resource group and local artifacts |
| `bicep/deploy.sh`, `terraform/deploy.sh` | The alternative deployment paths |

## Cleanup

```bash
bash scripts/cleanup.sh
```

## Emulator notes

- Kafka is served in plaintext by the emulator; Azure requires `SASL_SSL`. The producer
  shows the SASL settings needed against Azure in a comment.
- Data-plane authorization is existence-checked by the emulator, so the send-only and
  listen-only rules demonstrate the *deployment* pattern rather than an enforced boundary.
  Both rules are used exactly as they would be against Azure.
- The emulator serves the HTTP runtime API on the gateway port; `common.py` derives it
  from the connection string so the same code works against Azure unchanged.

## References

- [Azure Event Hubs documentation](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-about)
- [Event Hubs Capture](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-capture-overview)
- [Event Hubs for Apache Kafka](https://learn.microsoft.com/en-us/azure/event-hubs/azure-event-hubs-apache-kafka-overview)
- [Azure Schema Registry](https://learn.microsoft.com/en-us/azure/event-hubs/schema-registry-overview)
- [Azure Functions Event Hubs trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-hubs-trigger)
- [Event Hubs quotas and limits](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-quotas)
- [LocalStack for Azure](https://docs.localstack.cloud/azure/)

# Azure CLI deployment

Deploys the payment fraud detection pipeline with the Azure CLI, then verifies and
exercises it. Run `lstk az start-interception` first so every `az` call is routed to the
LocalStack Azure emulator.

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Creates the whole topology: Log Analytics and Application Insights, a storage account with the Capture container, the Event Hubs namespace (Standard, Kafka enabled, auto-inflate), the `payments` hub with Capture, the `fraud-alerts` hub, three consumer groups, send-only and listen-only rules, the Schema Registry group, a Key Vault holding the connection strings, the Event Hubs-triggered Function App, and the dashboard Web App. |
| `validate.sh` | Checks every deployed capability: control plane, Capture settings, consumer groups, authorization rights, Key Vault secrets, an AMQP send/receive round trip using the least-privilege rules, and partition runtime metadata. Bonus checks create and remove an application group with a throttling policy and a geo-disaster-recovery alias. |
| `run-pipeline.sh` | The end-to-end demo: registers the Avro contract, ingests over AMQP, Kafka and HTTPS, waits for the function's fraud alerts, restarts the processor to demonstrate checkpoint recovery, then waits for Capture and decodes an Avro archive. Every stage is an assertion — see below. |
| `cleanup.sh` | Deletes the resource group and the local artifacts. |
| `roundtrip_check.py` | Data-plane helper used by `validate.sh`. |
| `read_capture.py` | Decodes the newest Capture archive; used by `run-pipeline.sh`. |

## Usage

```bash
cd samples/eventhubs/python

bash scripts/deploy.sh
bash scripts/validate.sh
bash scripts/run-pipeline.sh

# when you are done
bash scripts/cleanup.sh
```

`deploy.sh` writes `scripts/.deployment-env` with the resource names and connection
strings; `run-pipeline.sh` sources it, and you can too:

```bash
source scripts/.deployment-env
cd src/producers && python producer_amqp.py --count 100
```

## What `run-pipeline.sh` asserts

The demo exits non-zero the moment the pipeline stops behaving, and prints the Function App
container's logs on the way out, so a run that finishes is proof the pipeline works rather
than a description of what it should have done. It fails if:

- the Avro contract cannot be registered;
- any producer cannot publish, or the payments hub does not grow by the full 75 events the
  three protocols sent — which catches a producer that reports success but writes nowhere;
- no fraud alert reaches `fraud-alerts` within `PROCESSING_WAIT_SECONDS`, meaning the Event
  Hubs trigger is not processing the stream;
- the processor cannot be redeployed, produces no alert after the restart, or re-emits the
  whole backlog instead of resuming at its checkpoint;
- Capture writes no archive, or the newest archive does not decode as Avro.

## Notes

- The first `deploy.sh` run pulls the Functions build image and can take several minutes.
  Later runs reuse it.
- `deploy.sh` is idempotent: every resource is created only when it does not already
  exist, so you can re-run it after a partial failure.
- These scripts need `src/producers/requirements.txt` installed (`azure-eventhub`,
  `azure-identity`, `azure-storage-blob`, `confluent-kafka`, `fastavro`, `requests`). The
  last two are for `read_capture.py`, which decodes a Capture archive in the final step of
  `run-pipeline.sh`. Set `PYTHON_BIN` if the interpreter holding them is not `python3`.

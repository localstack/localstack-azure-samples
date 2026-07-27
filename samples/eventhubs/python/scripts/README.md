# Azure CLI deployment

Deploys the payment fraud detection pipeline with the Azure CLI, then verifies and
exercises it. Run `azlocal start-interception` first so every `az` call is routed to the
LocalStack Azure emulator.

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Creates the whole topology: Log Analytics and Application Insights, a storage account with the Capture container, the Event Hubs namespace (Standard, Kafka enabled, auto-inflate), the `payments` hub with Capture, the `fraud-alerts` hub, three consumer groups, send-only and listen-only rules, the Schema Registry group, a Key Vault holding the connection strings, the Event Hubs-triggered Function App, and the dashboard Web App. |
| `validate.sh` | Checks every deployed capability: control plane, Capture settings, consumer groups, authorization rights, Key Vault secrets, an AMQP send/receive round trip using the least-privilege rules, and partition runtime metadata. Bonus checks create and remove an application group with a throttling policy and a geo-disaster-recovery alias. |
| `run-pipeline.sh` | The end-to-end demo: registers the Avro contract, ingests over AMQP, Kafka and HTTPS, shows the function's fraud alerts, restarts the processor to demonstrate checkpoint recovery, then waits for Capture and decodes an Avro archive. |
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

## Notes

- The first `deploy.sh` run pulls the Functions build image and can take several minutes.
  Later runs reuse it.
- `deploy.sh` is idempotent: every resource is created only when it does not already
  exist, so you can re-run it after a partial failure.
- The producers need `src/producers/requirements.txt` installed (`azure-eventhub`,
  `confluent-kafka`, `requests`, `azure-identity`). Set `PYTHON_BIN` if the interpreter
  holding them is not `python3`.

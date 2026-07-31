# Cold-path automation: Event Hubs Capture → Event Grid → Functions

A cold-chain monitoring pipeline where **Azure tells you when a batch is ready**, instead of your
code polling for it.

Devices publish temperature readings into an event hub. Event Hubs Capture archives the stream to
Blob Storage as Avro. The moment an archive lands, Event Hubs raises
`Microsoft.EventHub.CaptureFileCreated` to Event Grid, an Event Grid subscription delivers that
notification **into a second event hub**, and a Function App triggered on that hub downloads the
archive, aggregates it per device, and writes summaries to a curated hub.

```
 devices ──▶ telemetry hub ──── Capture (60s window) ────▶ Avro archive in Blob Storage
                  │                                                    │
                  │                        Microsoft.EventHub.CaptureFileCreated
                  │                                                    ▼
                  │                                    Event Grid system topic
                  │                                                    │
                  │                          subscription, EventHub destination
                  │                                                    ▼
                  │                                      capture-notifications hub
                  │                                                    │
                  │                                    Event Hubs trigger
                  │                                                    ▼
                  └───────────── archive read back ────────────  Function App
                                                                       │
                                                     Event Hubs output binding
                                                                       ▼
                                                                  curated hub
```

## Why this shape

The obvious way to process archives is a timer that lists a container and looks for new blobs.
That is a poll: it is late by up to its interval, it re-lists everything each run, and it needs
its own bookkeeping to avoid double-processing.

Here the platform does the telling:

| Concern | How the pipeline handles it |
|---|---|
| **When is a batch ready?** | Event Hubs says so — `CaptureFileCreated` carries the file URL, the partition, and the exact sequence range it contains |
| **How does the notification reach the processor?** | Event Grid delivers it into an **event hub**, so there is no public webhook to expose and no HTTP endpoint to keep available |
| **What if the processor is down?** | The notification sits in the hub for the retention window; the processor resumes from its checkpoint and catches up |
| **Is the aggregation correct?** | Readings are keyed by device, so a device's readings share a partition — and therefore share an archive, in order |
| **Can it be re-run?** | The archive is durable in Blob Storage; replaying is reading a file, not replaying a stream |

That last column is what makes it a *cold* path: it runs on whole, closed windows rather than on
whatever happened to be in the last batch.

## What it demonstrates

| Capability | Where |
|---|---|
| **Event Hubs Capture** to Avro in Blob Storage | `deploy.sh` step 4, `bicep/modules/event-hubs.bicep` |
| **`Microsoft.EventHub.CaptureFileCreated`** system event | Raised by Event Hubs; consumed in `src/functions/function_app.py` |
| **Event Grid system topic** over a namespace | `deploy.sh` step 7, `bicep/modules/event-grid.bicep` |
| **Event Grid subscription with an EventHub destination** | Same — this is what makes the notification a stream |
| **Event Hubs trigger** with `Cardinality.MANY` | `function_app.py` — batched delivery |
| **Event Hubs output binding** | `function_app.py` — writes the curated summaries |
| **Partition keys for correctness** | `telemetry_producer.py` — a device's readings stay together |
| **Consumer groups** | The processor reads the notifications hub with its own group |
| **Least-privilege SAS** | Send-only for producers, namespace-wide Listen-only for the demo scripts |
| **Avro decoding from Blob Storage** | `function_app.py` `_read_archive` |

## Prerequisites

- The LocalStack Azure emulator running, and `lstk az start-interception` run.
- [lstk](https://github.com/localstack/lstk) (`brew install localstack/tap/lstk` or
  `npm install -g @localstack/lstk`), which routes the Azure CLI to the emulator.
- Python 3.12+ with `src/producers/requirements.txt` installed.
- `jq` and `zip`.

> **The emulator must be able to resolve `cdn.functions.azure.com` from the function container.**
> The Event Hubs trigger lives in the Functions extension bundle, which the host downloads on
> every cold container. If the emulator's DNS server cannot forward external queries, the host
> aborts and the trigger silently never fires. Starting the emulator with `DNS_ADDRESS=0`
> sidesteps it.

## Usage

```bash
cd samples/eventhubs-eventgrid/python

bash scripts/deploy.sh          # nine steps: storage, hubs, Capture, Event Grid, Function App
bash scripts/validate.sh        # numbered checks over every capability above
bash scripts/run-pipeline.sh    # the end-to-end demo

bash scripts/cleanup.sh         # when you are done
```

`deploy.sh` writes `scripts/.deployment-env` with the resource names and connection strings;
the other scripts source it, and so can you:

```bash
source scripts/.deployment-env
cd src/producers && python telemetry_producer.py --count 200 --devices 8
```

### Infrastructure as code

The same topology through either IaC path; both then publish the application code with the CLI,
and both write the same `scripts/.deployment-env`, so the demo runs after either one:

```bash
cd bicep     && bash deploy.sh    # or:
cd terraform && bash deploy.sh

bash ../scripts/validate.sh
bash ../scripts/run-pipeline.sh
```

## The demo, step by step

`scripts/run-pipeline.sh` asserts each stage rather than narrating it — it exits non-zero, and
prints the processor's container logs, the moment the chain breaks:

1. **Publish telemetry.** 120 readings across 6 devices, keyed by device id. One device
   (`DEV-0003` by default) also emits readings above the temperature limit.
2. **Wait for Capture.** Polls the blob container until a new archive appears. Nothing downstream
   can happen until a window closes, so this sets the tempo.
3. **Show the notification.** Reads `capture-notifications` — the hub Event Grid delivered into.
4. **Read the curated summaries.** Polls the `curated` hub for the per-device aggregates the
   processor produced, and fails if the excursion device is missing from them.
5. **Recap** the path an event took.

## Application

### Producer (`src/producers/telemetry_producer.py`)

Publishes cold-chain readings with the device id as the **partition key**, one batch per device.
That is not a throughput trick: it is what guarantees a device's readings land in one archive, in
order, so the archive-level aggregation is exact.

```bash
python telemetry_producer.py [--count 120] [--devices 6] [--excursion-device DEV-0003]
```

### Processor (`src/functions/function_app.py`)

An Event Hubs-triggered function over `capture-notifications`. For each notification it:

1. parses the Event Grid **batch array** (Event Grid always delivers an array — "an array with a
   single event" by default),
2. downloads the archive named by `data.fileUrl`,
3. decodes the Avro records,
4. aggregates per device (count, min/mean/max, excursions), carrying the archive's sequence range
   through so a downstream consumer can spot a gap between windows,
5. writes one summary per device via the **output binding**.

Two details that are easy to get wrong, both commented in the code:

- The trigger declares `cardinality=func.Cardinality.MANY`. The default delivers a bare
  `EventHubEvent` and the handler fails with *"'EventHubEvent' object is not iterable"*.
- The handler annotates `List[func.EventHubEvent]` from `typing`. The builtin `list[...]` makes
  the Functions worker reject the function as an *"invalid non-type annotation"*, and it never
  loads at all.

## Notes

- The first `deploy.sh` run pulls the Functions build image and can take several minutes.
- `deploy.sh` is idempotent: every resource is created only when it does not already exist.
- Capture's minimum interval is 60 seconds, so the demo always takes at least that long.
- `skip_empty_archives` is on, so a window with no readings raises no event — otherwise the
  processor would be woken for empty files.

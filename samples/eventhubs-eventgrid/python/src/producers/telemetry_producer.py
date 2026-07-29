"""Publish cold-chain telemetry into the Event Hubs stream that Capture archives.

Every reading is keyed on the device id, so a device's readings always land on the same partition
and therefore appear in the same Capture archive in order. That is what lets the downstream
processor aggregate per device from a single file instead of stitching partitions together.

    python telemetry_producer.py [--count 120] [--devices 6] [--excursion-device DEV-0003]
"""

import argparse
import json
import os
import random
import sys
from datetime import UTC, datetime
from uuid import uuid4

from azure.eventhub import EventData, EventHubProducerClient

SITES = ["depot-lisbon", "depot-porto", "depot-madrid"]
# Normal cold-chain range; the excursion device deliberately breaches the upper limit.
NORMAL_RANGE = (2.0, 8.0)
EXCURSION_RANGE = (81.0, 95.0)


def progress(message: str) -> None:
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {message}", flush=True)


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Environment variable {name} is not set. "
            f"Run 'source scripts/.deployment-env' (written by scripts/deploy.sh) first."
        )
    return value


def make_reading(device_id: str, temperature: float) -> dict:
    return {
        "reading_id": str(uuid4()),
        "device_id": device_id,
        "site": random.choice(SITES),
        "temperature": round(temperature, 2),
        "humidity": round(random.uniform(30.0, 65.0), 2),
        "battery_pct": random.randint(40, 100),
        "recorded_at": datetime.now(UTC).isoformat(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Publish cold-chain telemetry readings.")
    parser.add_argument("--count", type=int, default=120, help="number of readings to publish")
    parser.add_argument("--devices", type=int, default=6, help="number of distinct devices")
    parser.add_argument(
        "--excursion-device",
        help="device id that also emits out-of-range readings, so the summary reports excursions",
    )
    args = parser.parse_args()

    connection_string = require_env("EVENTHUB_SEND_CONNECTION_STRING")
    hub_name = require_env("TELEMETRY_HUB_NAME")

    device_ids = [f"DEV-{index:04d}" for index in range(1, args.devices + 1)]
    readings = [
        make_reading(random.choice(device_ids), random.uniform(*NORMAL_RANGE))
        for _ in range(args.count)
    ]
    if args.excursion_device:
        readings += [
            make_reading(args.excursion_device, random.uniform(*EXCURSION_RANGE)) for _ in range(8)
        ]

    producer = EventHubProducerClient.from_connection_string(
        connection_string, eventhub_name=hub_name
    )
    progress(f"connected to '{hub_name}' over AMQP")

    # One batch per device: the partition key travels with the batch, so a device's readings stay
    # together and in order, which is what the archive-level aggregation depends on.
    by_device: dict[str, list[dict]] = {}
    for reading in readings:
        by_device.setdefault(reading["device_id"], []).append(reading)

    sent = 0
    with producer:
        for device_id, device_readings in by_device.items():
            batch = producer.create_batch(partition_key=device_id)
            for reading in device_readings:
                event = EventData(json.dumps(reading))
                event.properties = {"device_id": device_id, "site": reading["site"]}
                try:
                    batch.add(event)
                except ValueError:
                    producer.send_batch(batch)
                    sent += len(batch)
                    batch = producer.create_batch(partition_key=device_id)
                    batch.add(event)
            producer.send_batch(batch)
            sent += len(batch)

    excursions = sum(1 for reading in readings if reading["temperature"] >= 80)
    progress(
        f"published {sent} readings from {len(by_device)} device(s); "
        f"{excursions} above the temperature limit"
    )


if __name__ == "__main__":
    sys.exit(main())

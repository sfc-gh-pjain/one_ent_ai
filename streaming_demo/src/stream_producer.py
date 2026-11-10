"""
Snowpipe Streaming Demo: HCP Engagement Event Producer

Generates realistic pharmaceutical engagement events and streams them
into Snowflake via the Snowpipe Streaming Python SDK.

Usage:
    python stream_producer.py --profile keys/profile.json --duration 60 --rate 50
"""

import argparse
import json
import logging
import random
import time
import uuid
from datetime import datetime, timezone

from streaming_service import StreamingService

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# --- Event generation pools ---
EVENT_TYPES = ["DETAIL_VISIT", "DIGITAL_ENGAGE", "SAMPLE_DROP", "CONFERENCE", "PEER_REVIEW", "WEBINAR"]
CHANNELS = ["IN_PERSON", "VIDEO", "EMAIL", "PHONE", "CHAT"]
DRUG_IDS = [f"DRUG-{i:03d}" for i in range(1, 21)]
SPECIALTIES = ["Oncology", "Cardiology", "Neurology", "Immunology", "Endocrinology", "Dermatology"]
NOTES_TEMPLATES = [
    "Discussed efficacy data for {}",
    "Provided samples of {} — physician receptive",
    "Follow-up on {} trial results",
    "Addressed safety concerns about {}",
    "Reviewed new indication approval for {}",
    "Conference presentation on {} mechanism of action",
]


def generate_event(hcp_pool, rep_pool):
    """Generate a single realistic HCP engagement event."""
    hcp_id = random.choice(hcp_pool)
    rep_id = random.choice(rep_pool)
    event_type = random.choice(EVENT_TYPES)
    channel = random.choice(CHANNELS)
    drug_id = random.choice(DRUG_IDS)
    territory_id = random.randint(1, 20)

    # Duration varies by event type
    if event_type == "DETAIL_VISIT":
        duration = random.randint(300, 1800)
    elif event_type == "CONFERENCE":
        duration = random.randint(3600, 14400)
    elif event_type == "WEBINAR":
        duration = random.randint(1800, 5400)
    else:
        duration = random.randint(60, 900)

    sentiment = round(random.uniform(-1.0, 1.0), 3)
    note = random.choice(NOTES_TEMPLATES).format(drug_id)

    payload = {
        "specialty": random.choice(SPECIALTIES),
        "is_kol": random.random() < 0.15,
        "samples_count": random.randint(0, 10) if event_type == "SAMPLE_DROP" else 0,
        "notes": note,
        "source_system": "CRM_VEEVA",
        "geo": {"lat": round(random.uniform(25.0, 48.0), 4), "lng": round(random.uniform(-125.0, -70.0), 4)},
    }

    return {
        "EVENT_ID": str(uuid.uuid4()),
        "HCP_ID": hcp_id,
        "REP_ID": rep_id,
        "EVENT_TYPE": event_type,
        "CHANNEL": channel,
        "DRUG_ID": drug_id,
        "TERRITORY_ID": territory_id,
        "DURATION_SECONDS": duration,
        "SENTIMENT_SCORE": sentiment,
        "EVENT_PAYLOAD": payload,
        "EVENT_TIMESTAMP": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f"),
    }


def run_producer(profile_path, database, schema, table, rate, duration, partitions):
    """Run the streaming producer for the specified duration."""

    with open(profile_path, "r") as f:
        profile = json.load(f)

    logger.info(f"Starting producer: {rate} events/sec for {duration}s → {database}.{schema}.{table}")
    logger.info(f"Account: {profile['account']}, User: {profile['user']}, Partitions: {partitions}")

    service = StreamingService(
        account=profile["account"],
        user=profile["user"],
        private_key_path=profile.get("private_key_path", "keys/rsa_key.p8"),
        database=database,
        schema=schema,
        table=table,
        partition_count=partitions,
        instance_id="demo",
        role=profile.get("role"),
    )
    service.initialize()

    # Generate HCP and Rep pools
    hcp_pool = [f"HCP-{i:04d}" for i in range(1, 51)]
    rep_pool = [f"REP-{i:03d}" for i in range(1, 16)]

    start_time = time.time()
    interval = 1.0 / rate
    events_sent = 0
    last_report = start_time

    try:
        while time.time() - start_time < duration:
            event = generate_event(hcp_pool, rep_pool)
            service.stream_row(event, partition_key=event["HCP_ID"])
            events_sent += 1

            # Report every 5 seconds
            now = time.time()
            if now - last_report >= 5.0:
                elapsed = now - start_time
                throughput = events_sent / elapsed
                logger.info(f"  [{elapsed:.0f}s] Sent {events_sent} events ({throughput:.1f}/sec)")
                last_report = now

            # Throttle to target rate
            sleep_time = interval - (time.time() - now)
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        logger.info(f"Flushing remaining events...")
        service.flush_and_wait(timeout_seconds=30)
        service.shutdown()

    elapsed = time.time() - start_time
    logger.info(f"Complete: {events_sent} events in {elapsed:.1f}s ({events_sent/elapsed:.1f} events/sec)")
    return events_sent


def main():
    parser = argparse.ArgumentParser(description="Snowpipe Streaming Demo: HCP Event Producer")
    parser.add_argument("--profile", default="keys/profile.json", help="Path to profile.json")
    parser.add_argument("--database", default="DEMO", help="Target database")
    parser.add_argument("--schema", default="HEALTHCARE_DEMO", help="Target schema")
    parser.add_argument("--table", default="HCP_EVENTS_RT", help="Target table")
    parser.add_argument("--rate", type=int, default=50, help="Events per second")
    parser.add_argument("--duration", type=int, default=60, help="Duration in seconds")
    parser.add_argument("--partitions", type=int, default=4, help="Number of channels/partitions")
    args = parser.parse_args()

    run_producer(
        profile_path=args.profile,
        database=args.database,
        schema=args.schema,
        table=args.table,
        rate=args.rate,
        duration=args.duration,
        partitions=args.partitions,
    )


if __name__ == "__main__":
    main()

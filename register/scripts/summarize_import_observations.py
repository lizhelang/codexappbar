#!/usr/bin/env python3

import json
import os
import sys
from collections import Counter


def main() -> int:
    path = os.path.expanduser(
        os.environ.get(
            "IMPORT_OBSERVATION_LOG",
            "~/.codexbar/register-import-observations.jsonl",
        )
    )
    if not os.path.exists(path):
        print(f"no observation log found at {path}")
        return 1

    records = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    failures = [r for r in records if r.get("outcome") == "failure"]
    counts = Counter(r.get("category", "unknown") for r in failures)
    ordered_categories = [
        "phone_verification",
        "invalid_state",
        "cdp_race",
        "timeout",
    ]

    print(f"log_path={path}")
    print(f"failure_records={len(failures)}")
    for category in ordered_categories:
        print(f"{category}={counts.get(category, 0)}")

    extras = [name for name in counts if name not in ordered_categories]
    for category in sorted(extras):
        print(f"{category}={counts[category]}")

    print("--- recent_failures ---")
    for record in failures[-10:]:
        detail = (record.get("detail") or "").splitlines()[0]
        print(
            f"{record.get('timestamp','')}\t"
            f"{record.get('email','')}\t"
            f"{record.get('category','')}\t"
            f"{record.get('stop_reason','')}\t"
            f"{detail}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

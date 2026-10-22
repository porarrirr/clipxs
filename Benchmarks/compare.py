#!/usr/bin/env python3
"""Compare HISTORY_BENCHMARK lines emitted by HistoryPerformanceTests."""
import argparse
import json
from pathlib import Path


def read_result(path):
    for line in Path(path).read_text().splitlines():
        if "HISTORY_BENCHMARK " in line:
            return json.loads(line.split("HISTORY_BENCHMARK ", 1)[1])
    raise ValueError(f"No HISTORY_BENCHMARK result in {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    args = parser.parse_args()
    before, after = read_result(args.before), read_result(args.after)
    for field in ("entries", "rounds", "checksum"):
        if before[field] != after[field]:
            raise ValueError(f"Workloads differ: {field}")
    comparison = {}
    for metric in ("navigation_ms", "typing_ms", "image_filter_navigation_ms"):
        comparison[metric] = {
            "before": before[metric],
            "after": after[metric],
            "reduction_percent": 100 * (1 - after[metric] / before[metric]),
        }
    print(json.dumps({"before": before, "after": after, "comparison": comparison}, indent=2))
    if any(result["reduction_percent"] < 80 for result in comparison.values()):
        raise SystemExit("History interaction time reduction is below 80%")


if __name__ == "__main__":
    main()

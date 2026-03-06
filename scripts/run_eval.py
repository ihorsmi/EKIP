#!/usr/bin/env python3
"""Lightweight eval runner for EKIP.

Reads data/eval/qa_pairs.jsonl and calls POST /query.
PASS if all expected_answer_contains tokens appear in the answer (case-insensitive).
"""
import json
import os
import sys
import requests

API_BASE = os.getenv("API_BASE", "http://localhost:8000")
QA_PATH = os.getenv("QA_PATH", "data/eval/qa_pairs.jsonl")

def main() -> int:
    if not os.path.exists(QA_PATH):
        print(f"QA file not found: {QA_PATH}", file=sys.stderr)
        return 2

    with open(QA_PATH, "r", encoding="utf-8") as f:
        rows = [json.loads(line) for line in f if line.strip()]

    passed = 0
    for row in rows:
        qid = row.get("id", "unknown")
        question = row["question"]
        expected = row.get("expected_answer_contains", [])
        resp = requests.post(f"{API_BASE}/query", json={"question": question, "top_k": 5}, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        answer = (data.get("answer") or "").lower()

        ok = True
        for token in expected:
            if str(token).lower() not in answer:
                ok = False
                break

        print(f"[{'PASS' if ok else 'FAIL'}] {qid}: {question}")
        if not ok:
            print("  expected:", expected)
            print("  answer:", data.get("answer"))
        else:
            passed += 1

    print(f"\nResult: {passed}/{len(rows)} passed")
    return 0 if passed == len(rows) else 1

if __name__ == "__main__":
    raise SystemExit(main())

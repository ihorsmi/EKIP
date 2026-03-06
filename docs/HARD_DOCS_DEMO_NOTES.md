# HARD_DOCS_DEMO_NOTES

Use this guide when demonstrating EKIP with denser, policy-heavy documents.

## Dataset policy

- Only synthetic/sample content should be used in public demos.
- Keep uploads limited to files under `data/sample_docs/` unless new files are explicitly sanitized.

## Recommended demo flow

1. Upload 3-5 mixed-format docs (TXT, DOCX, PDF).
2. Wait for ingestion jobs to reach `completed`.
3. Ask one broad question, then one evidence-specific follow-up.
4. Highlight citations and suggested actions.
5. Show conversation history and agent event trail.

## High-signal questions

- "Which controls mention least-privilege access reviews?"
- "What incident response steps apply before escalation?"
- "What does the product FAQ say about supported integrations?"

## Demo checks

- Answers should reference source chunks.
- Actions should be concrete and operationally useful.
- Logs should contain correlation IDs and agent events.

## Failure handling

If you hit `DeploymentNotFound` during query:

- Call out AOAI quota limitation.
- Continue with architecture/ingestion/audit evidence walkthrough.
- Use the troubleshooting guide for mitigation: `docs/TROUBLESHOOTING.md`.

# EKIP - Data Pack Usage (Synthetic Docs + Eval + Queue Messages)

This pack provides synthetic sample documents, a lightweight eval set, and Service Bus message examples.

## Included paths

- `data/sample_docs/`
- `data/eval/`
- `data/queue_messages/`
- `scripts/`
- `tools/postman/`

## Demo-oriented usage

Upload sample docs from `data/sample_docs/`, then query via frontend or API.

Example query call:

```bash
curl -sS -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"question":"What are the core collaboration hours?","top_k":5}'
```

Queue schema examples are in:

- `data/queue_messages/ingest_document_message.schema.json`
- `data/queue_messages/ingest_document_message.example.json`
- `data/queue_messages/bulk_ingest_messages.jsonl`

Postman collection:

- `tools/postman/EKIP_API.postman_collection.json`

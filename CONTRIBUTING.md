# Contributing

Thanks for contributing to EKIP.

## Ground Rules

- Keep the Azure demo path working.
- Do not commit secrets or generated deployment outputs.
- Keep changes scoped and documented.

## Local validation

Backend:

```bash
cd backend
ruff check .
pytest -q
```

Frontend:

```bash
cd frontend
npm install
npm run lint
npm run build
```

## Pull request checklist

- Tests and lint checks pass
- No secrets introduced
- Docs updated when behavior/config changes
- Breaking changes are called out clearly

## Security issues

Use `SECURITY.md` for responsible disclosure.

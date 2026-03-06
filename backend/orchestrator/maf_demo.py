"""Minimal Microsoft Agent Framework demo (optional).

This file is here to prove that the repo is ready to integrate Agent Framework + Foundry.

Prereqs:
- Set env vars:
  - AZURE_AI_PROJECT_ENDPOINT
  - AZURE_OPENAI_RESPONSES_DEPLOYMENT_NAME
- Ensure your Foundry project has a Responses-compatible deployment.
- For local dev auth, run `az login` so DefaultAzureCredential can resolve identity.

Run:
  python -m orchestrator.maf_demo
"""

from __future__ import annotations

import asyncio
import os

from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

try:
    from agent_framework.azure import AzureOpenAIResponsesClient  # type: ignore
except ImportError as exc:  # pragma: no cover - import guard for optional dependency path
    raise SystemExit(
        "Optional dependency missing: install with "
        "`pip install -r requirements-agent-framework.txt` from backend/"
    ) from exc


async def main() -> None:
    load_dotenv()

    project_endpoint = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
    deployment_name = os.environ["AZURE_OPENAI_RESPONSES_DEPLOYMENT_NAME"]

    client = AzureOpenAIResponsesClient(
        project_endpoint=project_endpoint,
        deployment_name=deployment_name,
        credential=DefaultAzureCredential(),
    )

    agent = client.create_agent(
        name="HelloAgent",
        instructions="You are a friendly assistant. Keep your answers brief.",
    )

    result = await agent.run("Say hello in one short sentence.")
    print(result)


if __name__ == "__main__":
    asyncio.run(main())

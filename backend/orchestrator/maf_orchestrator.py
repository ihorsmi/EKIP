from __future__ import annotations

import asyncio
import json
import logging
from typing import List, Tuple

from openai import AzureOpenAI

from agents.advisor import advise
from agents.reasoner import ReasonerAgent
from agents.summarizer import summarize
from core.config import settings
from core.exceptions import require
from core.store import StateStore
from core.vector_store import RetrievedChunk
from orchestrator.mcp_tool_loop import format_mcp_context, run_mcp_tool_loop

logger = logging.getLogger(__name__)


class AgentFrameworkOrchestrator:
    """Optional Agent Framework orchestration path.

    Execution order:
    1) Always run MCP tool loop when enabled.
    2) Prefer Agent Framework + Foundry if fully configured and dependency is present.
    3) Fallback to Azure OpenAI chat completions with the same context + MCP grounding.
    4) Final safety fallback to deterministic summarize/advise if any upstream fails.
    """

    def __init__(self, store: StateStore) -> None:
        self.store = store
        self.reasoner = ReasonerAgent()

    def answer(self, *, question: str, conversation_id: str | None) -> Tuple[str, str, List[RetrievedChunk], List[str]]:
        if not conversation_id:
            conversation_id = self.store.create_conversation(title="EKIP Chat")
        else:
            existing = self.store.get_conversation(conversation_id)
            if not existing:
                self.store.upsert_conversation(conversation_id, title="EKIP Chat")

        self.store.add_message(conversation_id, role="user", content=question)
        chunks = self.reasoner.get_context(question, limit=6)
        self.store.log_agent_event(
            conversation_id=conversation_id,
            agent="maf_orchestrator",
            event="context_retrieved",
            payload_json=json.dumps({"chunks": len(chunks)}),
        )

        answer, actions = self._run_agent_framework_or_fallback(question, chunks, conversation_id)
        self.store.add_message(conversation_id, role="assistant", content=answer)
        return conversation_id, answer, chunks, actions

    def _run_agent_framework_or_fallback(
        self, question: str, chunks: List[RetrievedChunk], conversation_id: str
    ) -> tuple[str, list[str]]:
        try:
            answer, actions = asyncio.run(self._run_maf(question, chunks, conversation_id))
            self.store.log_agent_event(
                conversation_id=conversation_id,
                agent="maf_orchestrator",
                event="maf_success",
                payload_json=json.dumps({"actions": len(actions)}),
            )
            return answer, actions
        except Exception as exc:  # noqa: BLE001
            logger.exception("maf_orchestrator_fallback")
            self.store.log_agent_event(
                conversation_id=conversation_id,
                agent="maf_orchestrator",
                event="maf_fallback",
                payload_json=json.dumps({"reason": str(exc)}),
            )
            # Keep API availability even when optional dependencies are absent.
            answer = summarize(question, chunks)
            actions = advise(question, answer, chunks)
            return answer, actions

    async def _run_maf(
        self, question: str, chunks: List[RetrievedChunk], conversation_id: str
    ) -> tuple[str, list[str]]:
        context = "\n\n".join(
            f"[{i}] {c.filename}#{c.chunk_index} score={c.score:.4f}\n{c.text}" for i, c in enumerate(chunks, start=1)
        )

        mcp_calls = await run_mcp_tool_loop(question=question, conversation_id=conversation_id)
        mcp_context = format_mcp_context(mcp_calls)
        if mcp_calls:
            self.store.log_agent_event(
                conversation_id=conversation_id,
                agent="mcp_orchestrator",
                event="mcp_tools_invoked",
                payload_json=json.dumps(
                    [
                        {
                            "tool_name": call.tool_name,
                            "arguments": call.arguments,
                            "output_preview": (call.output[:500] if call.output else ""),
                        }
                        for call in mcp_calls
                    ]
                ),
            )

        foundry_result = await self._run_foundry_if_available(question=question, context=context, mcp_context=mcp_context)
        if foundry_result is not None:
            return foundry_result

        return self._run_with_azure_openai(question=question, context=context, mcp_context=mcp_context)

    async def _run_foundry_if_available(
        self, *, question: str, context: str, mcp_context: str
    ) -> tuple[str, list[str]] | None:
        if not settings.azure_ai_project_endpoint.strip() or not settings.azure_openai_responses_deployment_name.strip():
            return None

        try:
            from agent_framework.azure import AzureOpenAIResponsesClient  # type: ignore
            from azure.identity import DefaultAzureCredential
        except ImportError:
            logger.info("agent_framework_dependency_missing_using_openai_fallback")
            return None

        client = AzureOpenAIResponsesClient(
            project_endpoint=settings.azure_ai_project_endpoint,
            deployment_name=settings.azure_openai_responses_deployment_name,
            credential=DefaultAzureCredential(),
        )

        summarizer = client.create_agent(
            name="EKIP-Summarizer",
            instructions=(
                "You are EKIP Summarizer. Use only provided context. "
                "Return concise grounded answer and cite context block numbers like [1], [2]."
            ),
        )
        advisor = client.create_agent(
            name="EKIP-Advisor",
            instructions=(
                "You are EKIP Advisor. Propose concrete enterprise actions from the answer. "
                "Return 3-5 bullet lines, each starting with '- '."
            ),
        )

        answer_prompt = f"QUESTION:\n{question}\n\nCONTEXT:\n{context}"
        if mcp_context:
            answer_prompt = f"{answer_prompt}\n\n{mcp_context}"
        answer = await summarizer.run(answer_prompt)
        advice_raw = await advisor.run(f"QUESTION:\n{question}\n\nANSWER:\n{answer}")
        actions = [ln.strip("- ").strip() for ln in str(advice_raw).splitlines() if ln.strip()]
        actions = [a for a in actions if a]
        return str(answer).strip(), actions[:5]

    def _run_with_azure_openai(self, *, question: str, context: str, mcp_context: str) -> tuple[str, list[str]]:
        endpoint = require(settings.azure_openai_endpoint, "AZURE_OPENAI_ENDPOINT")
        key = require(settings.azure_openai_api_key, "AZURE_OPENAI_API_KEY")

        client = AzureOpenAI(
            azure_endpoint=endpoint,
            api_key=key,
            api_version=settings.azure_openai_api_version,
        )

        answer_prompt = f"QUESTION:\n{question}\n\nCONTEXT:\n{context}"
        if mcp_context:
            answer_prompt = f"{answer_prompt}\n\n{mcp_context}"

        answer_resp = client.chat.completions.create(
            model=settings.azure_openai_chat_deployment,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are EKIP Summarizer. Use only provided context and MCP tool results. "
                        "Be concise and cite context blocks like [1], [2] when relevant."
                    ),
                },
                {"role": "user", "content": answer_prompt},
            ],
            temperature=0.2,
        )
        answer = (answer_resp.choices[0].message.content or "").strip()

        advice_resp = client.chat.completions.create(
            model=settings.azure_openai_chat_deployment,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are EKIP Advisor. Return 3-5 concrete action items. "
                        "Respond as a JSON array of strings."
                    ),
                },
                {
                    "role": "user",
                    "content": f"QUESTION:\n{question}\n\nANSWER:\n{answer}",
                },
            ],
            temperature=0.1,
        )
        advice_raw = (advice_resp.choices[0].message.content or "").strip()
        actions = self._parse_actions(advice_raw)
        return answer, actions[:5]

    @staticmethod
    def _parse_actions(raw: str) -> list[str]:
        if not raw:
            return []

        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                values = [str(x).strip() for x in parsed if str(x).strip()]
                if values:
                    return values
        except json.JSONDecodeError:
            pass

        actions: list[str] = []
        for line in raw.splitlines():
            cleaned = line.strip()
            if not cleaned:
                continue
            cleaned = cleaned.lstrip("-*")
            cleaned = cleaned.lstrip("0123456789. ")
            cleaned = cleaned.strip()
            if cleaned:
                actions.append(cleaned)
        return actions

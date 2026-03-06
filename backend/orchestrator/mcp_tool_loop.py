from __future__ import annotations

import asyncio
import json
import os
from dataclasses import dataclass
from typing import Any

from core.config import settings


@dataclass(frozen=True)
class MCPToolInvocation:
    tool_name: str
    arguments: dict[str, Any]
    output: str


def _parse_server_args(raw: str) -> list[str]:
    value = raw.strip()
    if not value:
        return []
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return [p.strip() for p in value.split(" ") if p.strip()]
    if isinstance(parsed, list):
        return [str(x) for x in parsed]
    raise ValueError("AZURE_MCP_SERVER_ARGS must be a JSON array or space-delimited string")


def _parse_tool_overrides(raw: str) -> dict[str, dict[str, Any]]:
    value = raw.strip()
    if not value:
        return {}
    parsed = json.loads(value)
    if not isinstance(parsed, dict):
        raise ValueError("AZURE_MCP_TOOL_ARGUMENTS_JSON must be a JSON object")
    out: dict[str, dict[str, Any]] = {}
    for key, val in parsed.items():
        if isinstance(key, str) and isinstance(val, dict):
            out[key] = val
    return out


def _render_template_values(value: Any, *, question: str, conversation_id: str | None) -> Any:
    if isinstance(value, str):
        rendered = value.replace("{{question}}", question)
        rendered = rendered.replace("{{conversation_id}}", conversation_id or "")
        return rendered
    if isinstance(value, list):
        return [_render_template_values(v, question=question, conversation_id=conversation_id) for v in value]
    if isinstance(value, dict):
        return {
            k: _render_template_values(v, question=question, conversation_id=conversation_id)
            for k, v in value.items()
        }
    return value


def _extract_tools(list_tools_result: Any) -> list[Any]:
    if hasattr(list_tools_result, "tools"):
        tools = getattr(list_tools_result, "tools")
        return list(tools) if isinstance(tools, list) else []
    if isinstance(list_tools_result, dict):
        tools = list_tools_result.get("tools", [])
        return list(tools) if isinstance(tools, list) else []
    return []


def _tool_name(tool: Any) -> str:
    if hasattr(tool, "name"):
        name = getattr(tool, "name")
        return str(name) if name is not None else ""
    if isinstance(tool, dict):
        value = tool.get("name", "")
        return str(value) if value is not None else ""
    return ""


def _tool_schema(tool: Any) -> dict[str, Any]:
    if hasattr(tool, "inputSchema"):
        schema = getattr(tool, "inputSchema")
        return schema if isinstance(schema, dict) else {}
    if hasattr(tool, "input_schema"):
        schema = getattr(tool, "input_schema")
        return schema if isinstance(schema, dict) else {}
    if isinstance(tool, dict):
        schema = tool.get("inputSchema", tool.get("input_schema", {}))
        return schema if isinstance(schema, dict) else {}
    return {}


def _build_default_arguments(schema: dict[str, Any], *, question: str, conversation_id: str | None) -> dict[str, Any]:
    props = schema.get("properties", {})
    required = schema.get("required", [])
    if not isinstance(props, dict):
        props = {}
    if not isinstance(required, list):
        required = []

    args: dict[str, Any] = {}
    keys = {str(k).lower(): str(k) for k in props.keys()}

    for candidate in ("question", "query", "text", "input", "prompt"):
        if candidate in keys:
            args[keys[candidate]] = question
            break
    for candidate in ("conversation_id", "conversationid", "session_id", "sessionid"):
        if candidate in keys and conversation_id:
            args[keys[candidate]] = conversation_id
            break

    if not args and required:
        first_required = str(required[0])
        field_schema = props.get(first_required, {})
        if isinstance(field_schema, dict) and field_schema.get("type") == "string":
            args[first_required] = question

    return args


def _format_tool_output(tool_result: Any) -> str:
    content = getattr(tool_result, "content", None)
    if isinstance(tool_result, dict):
        content = tool_result.get("content", content)

    if isinstance(content, list):
        out: list[str] = []
        for item in content:
            if hasattr(item, "text"):
                out.append(str(getattr(item, "text")))
            elif isinstance(item, dict) and "text" in item:
                out.append(str(item["text"]))
            else:
                out.append(str(item))
        return "\n".join(x for x in out if x.strip())

    if hasattr(tool_result, "text"):
        return str(getattr(tool_result, "text"))
    if isinstance(tool_result, dict) and "text" in tool_result:
        return str(tool_result["text"])
    return str(tool_result)


def format_mcp_context(invocations: list[MCPToolInvocation]) -> str:
    if not invocations:
        return ""
    lines: list[str] = ["MCP TOOL RESULTS:"]
    for idx, call in enumerate(invocations, start=1):
        args_preview = json.dumps(call.arguments, ensure_ascii=True)
        lines.append(f"[tool-{idx}] {call.tool_name} args={args_preview}")
        lines.append(call.output.strip() or "(empty tool output)")
        lines.append("")
    return "\n".join(lines).strip()


async def run_mcp_tool_loop(*, question: str, conversation_id: str | None) -> list[MCPToolInvocation]:
    if not settings.azure_mcp_enabled:
        return []
    if not settings.azure_mcp_server_command.strip():
        raise RuntimeError("AZURE_MCP_ENABLED=true but AZURE_MCP_SERVER_COMMAND is not set")

    try:
        from mcp import ClientSession, StdioServerParameters  # type: ignore
        from mcp.client.stdio import stdio_client  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "MCP dependency missing. Install with: pip install -r requirements-agent-framework.txt"
        ) from exc

    tool_overrides = _parse_tool_overrides(settings.azure_mcp_tool_arguments_json)
    selected_names = {n.lower() for n in settings.mcp_tool_names_list}
    max_calls = max(1, settings.azure_mcp_tool_max_calls)
    call_timeout = max(1, settings.azure_mcp_tool_timeout_seconds)

    server_params = StdioServerParameters(
        command=settings.azure_mcp_server_command,
        args=_parse_server_args(settings.azure_mcp_server_args),
        env=dict(os.environ),
    )

    invocations: list[MCPToolInvocation] = []
    async with stdio_client(server_params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            listed = await session.list_tools()
            tools = _extract_tools(listed)
            if selected_names:
                tools = [t for t in tools if _tool_name(t).lower() in selected_names]

            for tool in tools[:max_calls]:
                name = _tool_name(tool)
                if not name:
                    continue
                arguments = dict(tool_overrides.get(name, {}))
                if not arguments:
                    arguments = _build_default_arguments(
                        _tool_schema(tool),
                        question=question,
                        conversation_id=conversation_id,
                    )
                else:
                    rendered = _render_template_values(
                        arguments, question=question, conversation_id=conversation_id
                    )
                    arguments = rendered if isinstance(rendered, dict) else {}
                try:
                    pending_call = session.call_tool(name=name, arguments=arguments)
                except TypeError:
                    pending_call = session.call_tool(name, arguments)
                tool_result = await asyncio.wait_for(pending_call, timeout=call_timeout)
                invocations.append(
                    MCPToolInvocation(
                        tool_name=name,
                        arguments=arguments,
                        output=_format_tool_output(tool_result),
                    )
                )
    return invocations

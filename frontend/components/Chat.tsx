"use client";

import { useMemo, useState } from "react";
import { apiBaseUrl, postJson } from "../lib/api";

type Citation = {
  doc_id: string;
  filename: string;
  chunk_index: number;
  score: number;
  text: string;
};

type QueryResponse = {
  conversation_id: string;
  answer: string;
  citations: Citation[];
  actions: string[];
};

type ChatMessage = { role: "user" | "assistant"; content: string };

export default function Chat() {
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [last, setLast] = useState<QueryResponse | null>(null);

  const canSend = useMemo(() => input.trim().length > 0 && !busy, [input, busy]);

  async function send() {
    if (!canSend) return;
    const question = input.trim();
    setInput("");
    setBusy(true);
    setLast(null);
    setMessages((m) => [...m, { role: "user", content: question }]);

    try {
      const res = await postJson<QueryResponse>(`${apiBaseUrl()}/query`, {
        question,
        conversation_id: conversationId ?? undefined,
      });
      setConversationId(res.conversation_id);
      setLast(res);
      setMessages((m) => [...m, { role: "assistant", content: res.answer }]);
    } catch (e: any) {
      setMessages((m) => [
        ...m,
        { role: "assistant", content: `Error: ${e?.message ?? "Request failed"}` },
      ]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-4">
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between">
          <div className="text-sm font-medium">Conversation</div>
          <div className="text-xs text-gray-500">
            {conversationId ? `id: ${conversationId}` : "new"}
          </div>
        </div>

        <div className="mt-4 space-y-3">
          {messages.length === 0 ? (
            <div className="text-sm text-gray-500">
              Upload a document, then ask a question. Example:{" "}
              <span className="font-mono">What does the policy say about ...?</span>
            </div>
          ) : null}

          {messages.map((m, idx) => (
            <div
              key={idx}
              className={
                m.role === "user"
                  ? "ml-auto max-w-[80%] rounded-2xl bg-black px-3 py-2 text-sm text-white"
                  : "mr-auto max-w-[80%] rounded-2xl bg-gray-100 px-3 py-2 text-sm"
              }
            >
              {m.content}
            </div>
          ))}
        </div>

        <div className="mt-4 flex gap-2">
          <input
            className="w-full rounded-xl border border-gray-200 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-black/10"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask a question..."
            onKeyDown={(e) => {
              if (e.key === "Enter") send();
            }}
            disabled={busy}
          />
          <button
            onClick={send}
            disabled={!canSend}
            className="rounded-xl bg-black px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
          >
            {busy ? "..." : "Send"}
          </button>
        </div>
      </div>

      {last ? (
        <div className="grid gap-4 md:grid-cols-2">
          <div className="rounded-2xl bg-white p-4 shadow-sm">
            <div className="text-sm font-medium">Citations</div>
            <div className="mt-3 space-y-2">
              {last.citations.length === 0 ? (
                <div className="text-sm text-gray-500">No citations returned.</div>
              ) : (
                last.citations.map((c, i) => (
                  <div key={i} className="rounded-xl border border-gray-200 p-3">
                    <div className="text-xs text-gray-500">
                      {c.filename} • chunk {c.chunk_index} • score {c.score.toFixed(3)}
                    </div>
                    <div className="mt-2 text-sm text-gray-800">{c.text}</div>
                  </div>
                ))
              )}
            </div>
          </div>

          <div className="rounded-2xl bg-white p-4 shadow-sm">
            <div className="text-sm font-medium">Suggested actions</div>
            <div className="mt-3 space-y-2">
              {last.actions.length === 0 ? (
                <div className="text-sm text-gray-500">No actions returned.</div>
              ) : (
                <ul className="list-disc pl-5 text-sm">
                  {last.actions.map((a, i) => (
                    <li key={i}>{a}</li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

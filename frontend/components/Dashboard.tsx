"use client";

import { useEffect, useState } from "react";
import { apiBaseUrl, authHeaders } from "../lib/api";

type Conversation = {
  conversation_id: string;
  created_at: string;
  title: string;
};

type Job = {
  job_id: string;
  filename: string;
  status: string;
  error?: string | null;
  chunks_indexed: number;
  created_at: string;
  updated_at: string;
};

export default function Dashboard() {
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [history, setHistory] = useState<any | null>(null);

  async function refresh() {
    const [cRes, jRes] = await Promise.all([
      fetch(`${apiBaseUrl()}/history?limit=20`, { headers: authHeaders() }),
      fetch(`${apiBaseUrl()}/upload?limit=20`, { headers: authHeaders() }),
    ]);
    if (cRes.ok) setConversations((await cRes.json()) as Conversation[]);
    if (jRes.ok) setJobs((await jRes.json()) as Job[]);
  }

  useEffect(() => {
    refresh();
    const t = setInterval(refresh, 5000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!selected) return;
    fetch(`${apiBaseUrl()}/history/${selected}`, { headers: authHeaders() })
      .then((r) => r.json())
      .then((d) => setHistory(d))
      .catch(() => setHistory(null));
  }, [selected]);

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="text-sm font-medium">Conversations</div>
        <div className="mt-3 space-y-2">
          {conversations.length === 0 ? (
            <div className="text-sm text-gray-500">No conversations yet.</div>
          ) : (
            conversations.map((c) => (
              <button
                key={c.conversation_id}
                onClick={() => setSelected(c.conversation_id)}
                className={
                  "w-full rounded-xl border px-3 py-2 text-left text-sm " +
                  (selected === c.conversation_id
                    ? "border-black bg-black/5"
                    : "border-gray-200 hover:bg-gray-50")
                }
              >
                <div className="font-medium">{c.title}</div>
                <div className="mt-1 text-xs text-gray-500">
                  {new Date(c.created_at).toLocaleString()} | {c.conversation_id}
                </div>
              </button>
            ))
          )}
        </div>

        {history ? (
          <div className="mt-4 rounded-xl border border-gray-200 p-3">
            <div className="text-xs text-gray-500">Messages</div>
            <div className="mt-2 max-h-[360px] space-y-2 overflow-auto">
              {history.messages?.map((m: any, i: number) => (
                <div
                  key={i}
                  className={
                    m.role === "user"
                      ? "rounded-xl bg-black px-3 py-2 text-sm text-white"
                      : "rounded-xl bg-gray-100 px-3 py-2 text-sm"
                  }
                >
                  {m.content}
                </div>
              ))}
            </div>
          </div>
        ) : null}
      </div>

      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="text-sm font-medium">Ingestion jobs</div>
        <div className="mt-3 overflow-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs text-gray-500">
              <tr>
                <th className="py-2">Filename</th>
                <th className="py-2">Status</th>
                <th className="py-2">Chunks</th>
                <th className="py-2">Updated</th>
              </tr>
            </thead>
            <tbody>
              {jobs.length === 0 ? (
                <tr>
                  <td className="py-2 text-gray-500" colSpan={4}>
                    No jobs yet.
                  </td>
                </tr>
              ) : (
                jobs.map((j) => (
                  <tr key={j.job_id} className="border-t border-gray-100">
                    <td className="py-2">
                      <div className="font-medium">{j.filename}</div>
                      {j.error ? <div className="text-xs text-red-600">{j.error}</div> : null}
                    </td>
                    <td className="py-2">{j.status}</td>
                    <td className="py-2">{j.chunks_indexed}</td>
                    <td className="py-2 text-xs text-gray-500">
                      {new Date(j.updated_at).toLocaleString()}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

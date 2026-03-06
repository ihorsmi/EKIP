"use client";

import { useEffect, useState } from "react";
import { apiBaseUrl, authHeaders } from "../lib/api";

type Job = {
  job_id: string;
  filename: string;
  status: string;
  error?: string | null;
  chunks_indexed: number;
  created_at: string;
  updated_at: string;
  metadata: Record<string, any>;
};

export default function UploadForm() {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [job, setJob] = useState<Job | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [error, setError] = useState<string | null>(null);

  async function refreshJobs() {
    try {
      const res = await fetch(`${apiBaseUrl()}/upload?limit=20`, { headers: authHeaders() });
      if (!res.ok) return;
      const data = (await res.json()) as Job[];
      setJobs(data);
    } catch {
      // ignore
    }
  }

  useEffect(() => {
    refreshJobs();
    const t = setInterval(refreshJobs, 4000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!job?.job_id) return;
    const t = setInterval(async () => {
      const res = await fetch(`${apiBaseUrl()}/upload/${job.job_id}`, { headers: authHeaders() });
      if (!res.ok) return;
      const data = (await res.json()) as Job;
      setJob(data);
    }, 2000);
    return () => clearInterval(t);
  }, [job?.job_id]);

  async function submit() {
    if (!file) return;
    setBusy(true);
    setError(null);
    setJob(null);

    try {
      const form = new FormData();
      form.append("file", file);

      const res = await fetch(`${apiBaseUrl()}/upload`, {
        method: "POST",
        body: form,
        headers: authHeaders(),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body?.detail ?? "Upload failed");
      }
      const data = await res.json();
      const jobId = data.job_id as string;

      // fetch full job details
      const statusRes = await fetch(`${apiBaseUrl()}/upload/${jobId}`, { headers: authHeaders() });
      const statusData = (await statusRes.json()) as Job;
      setJob(statusData);
      await refreshJobs();
      setFile(null);
    } catch (e: any) {
      setError(e?.message ?? "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-4">
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="text-sm font-medium">Upload a document</div>
        <p className="mt-1 text-xs text-gray-500">
          Supported: PDF, DOCX, TXT. Ingestion runs in the background worker.
        </p>

        <div className="mt-4 flex flex-col gap-2 md:flex-row md:items-center">
          <input
            type="file"
            accept=".pdf,.docx,.txt,.md"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            className="text-sm"
            disabled={busy}
          />
          <button
            onClick={submit}
            disabled={!file || busy}
            className="rounded-xl bg-black px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
          >
            {busy ? "Uploading..." : "Upload"}
          </button>
          {error ? <div className="text-sm text-red-600">{error}</div> : null}
        </div>

        {job ? (
          <div className="mt-4 rounded-xl border border-gray-200 p-3 text-sm">
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              <div>
                <span className="text-gray-500">Job</span> {job.job_id}
              </div>
              <div>
                <span className="text-gray-500">Status</span> {job.status}
              </div>
              <div>
                <span className="text-gray-500">Chunks</span> {job.chunks_indexed}
              </div>
            </div>
            {job.error ? (
              <div className="mt-2 text-red-600">
                <span className="font-medium">Error:</span> {job.error}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>

      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="text-sm font-medium">Recent ingestion jobs</div>
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
                    <td className="py-2">{j.filename}</td>
                    <td className="py-2">
                      <span
                        className={
                          j.status === "completed"
                            ? "rounded-full bg-green-50 px-2 py-1 text-xs text-green-700"
                            : j.status === "failed"
                              ? "rounded-full bg-red-50 px-2 py-1 text-xs text-red-700"
                              : "rounded-full bg-gray-50 px-2 py-1 text-xs text-gray-700"
                        }
                      >
                        {j.status}
                      </span>
                    </td>
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

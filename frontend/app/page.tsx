import Link from "next/link";

export default function Home() {
  return (
    <div className="rounded-2xl bg-white p-6 shadow-sm">
      <h1 className="text-2xl font-semibold">EKIP</h1>
      <p className="mt-2 text-sm text-gray-600">
        A multi-agent RAG system for enterprise knowledge.
      </p>

      <div className="mt-6 flex gap-3">
        <Link
          href="/chat"
          className="rounded-xl bg-black px-4 py-2 text-sm font-medium text-white"
        >
          Open Chat
        </Link>
        <Link
          href="/upload"
          className="rounded-xl border border-gray-200 px-4 py-2 text-sm font-medium"
        >
          Upload Documents
        </Link>
        <Link
          href="/dashboard"
          className="rounded-xl border border-gray-200 px-4 py-2 text-sm font-medium"
        >
          Dashboard
        </Link>
      </div>
    </div>
  );
}

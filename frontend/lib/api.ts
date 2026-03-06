function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, "");
}

function deriveApiBaseUrlFromWindow(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  const host = window.location.host;
  const protocol = window.location.protocol;

  if (host.startsWith("ekip-frontend-")) {
    return `${protocol}//${host.replace("ekip-frontend-", "ekip-backend-")}`;
  }

  return null;
}

export function apiBaseUrl(): string {
  const configured = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (configured && !configured.includes("localhost")) {
    return trimTrailingSlash(configured);
  }

  const derived = deriveApiBaseUrlFromWindow();
  if (derived) {
    return trimTrailingSlash(derived);
  }

  if (configured) {
    return trimTrailingSlash(configured);
  }

  return "http://localhost:8000";
}

export function authHeaders(): Record<string, string> {
  const token = process.env.NEXT_PUBLIC_DEV_AUTH_TOKEN;
  if (!token) {
    return {};
  }
  return { Authorization: `Bearer ${token}` };
}

export async function postJson<T>(url: string, body: any): Promise<T> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data?.detail ?? data?.error ?? "Request failed");
  }
  return (await res.json()) as T;
}

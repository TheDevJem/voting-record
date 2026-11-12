export class ApiError extends Error {
  constructor(message, { status = 0, code = "unknown" } = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
  }

  // Server-side and connectivity problems are worth retrying; a 404 is not.
  get retryable() {
    return this.status === 0 || this.status >= 500;
  }
}

const FALLBACK_MESSAGES = {
  400: "That request wasn't valid.",
  404: "We couldn't find what you were looking for.",
  503: "The service is temporarily unavailable. Please try again shortly.",
};

async function request(path, { method = "GET" } = {}) {
  let res;
  try {
    res = await fetch(`/api${path}`, { method, headers: { Accept: "application/json" } });
  } catch {
    throw new ApiError("Can't reach the server. Check your connection and try again.", { code: "network_error" });
  }

  // Parse defensively: error pages and proxies don't always return JSON.
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const message =
      body?.error?.message ||
      FALLBACK_MESSAGES[res.status] ||
      (res.status >= 500 ? "Something went wrong on our end. Please try again." : `Request failed (${res.status}).`);
    throw new ApiError(message, { status: res.status, code: body?.error?.code });
  }
  if (body === null) throw new ApiError("The server sent an unexpected response.", { status: res.status, code: "bad_response" });
  return body;
}

const get = (path) => request(path);

export const api = {
  members: (chamber) => get(`/members?chamber=${encodeURIComponent(chamber)}`),
  member: (id) => get(`/members/${encodeURIComponent(id)}`),
  votes: (id, page) => get(`/members/${encodeURIComponent(id)}/votes?page=${page}`),
  bills: (id, role, page) => get(`/members/${encodeURIComponent(id)}/bills?role=${role}&page=${page}`),
  representatives: (q) => get(`/representatives?q=${encodeURIComponent(q)}`),
  summary: (id) => get(`/members/${encodeURIComponent(id)}/summary`),
  regenerateSummary: (id) => request(`/members/${encodeURIComponent(id)}/summary`, { method: "POST" }),
};

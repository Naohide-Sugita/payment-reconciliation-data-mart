#!/usr/bin/env python3
"""Tiny transparent proxy that sits in front of goccy/bigquery-emulator so the
dbt-bigquery adapter can run the payment_reconciliation project end-to-end
locally, with no Google Cloud credentials.

dbt talks to this proxy (api_endpoint=http://localhost:9055); the proxy forwards
to the emulator on :9050. It applies three minimal, transparent shims that
smooth over gaps between what dbt-bigquery sends and what the emulator accepts:

1. routines.list -> the emulator returns HTTP 500 for this call, which dbt makes
   while building its relation cache. Return an empty list instead.
2. seed load jobs -> dbt omits `sourceFormat` and emits lowercase column types
   (e.g. `string`); the emulator then fails CSV analysis with TYPE_UNKNOWN.
   Inject `sourceFormat=CSV` and uppercase the schema field types.
3. query jobs -> the emulator returns a `statementType` but no destinationTable,
   so dbt calls get_table(None) and crashes. Drop `statementType` so dbt skips
   that row-count lookup (used only for a log message).

Everything else is proxied byte-for-byte.
"""
import http.server
import json
import re
import socketserver
import urllib.request
import urllib.error

UPSTREAM = "http://127.0.0.1:9050"
LISTEN_PORT = 9055
ROUTINES_RE = re.compile(r"/routines(\?|$)")
UPLOAD_START_RE = re.compile(r"/upload/bigquery/.*jobs")
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
}


def _normalize_load_config(load_cfg):
    """Make a dbt seed load job digestible by the emulator:
    - set sourceFormat=CSV (dbt omits it; emulator then can't parse the CSV);
    - uppercase schema field types (dbt emits lowercase like `string`, which
      the emulator's zetasql analyzer rejects as TYPE_UNKNOWN)."""
    changed = False
    if not load_cfg.get("sourceFormat"):
        load_cfg["sourceFormat"] = "CSV"
        changed = True
    fields = load_cfg.get("schema", {}).get("fields")
    if isinstance(fields, list):
        for field in fields:
            ftype = field.get("type")
            if isinstance(ftype, str) and ftype != ftype.upper():
                field["type"] = ftype.upper()
                changed = True
    return changed


def _inject_source_format(path, body):
    if not body or "upload_id=" in path or not UPLOAD_START_RE.search(path):
        return body
    try:
        payload = json.loads(body)
    except (ValueError, TypeError):
        return body
    load_cfg = payload.get("configuration", {}).get("load")
    if isinstance(load_cfg, dict) and _normalize_load_config(load_cfg):
        return json.dumps(payload).encode()
    return body


def _scrub_response(path, body):
    """Drop statementType from query job responses so dbt skips the
    get_table(destination) row-count lookup the emulator can't satisfy."""
    if not body or ("/jobs" not in path and "/queries" not in path):
        return body
    try:
        payload = json.loads(body)
    except (ValueError, TypeError):
        return body
    stats = payload.get("statistics")
    query_stats = stats.get("query") if isinstance(stats, dict) else None
    if isinstance(query_stats, dict) and "statementType" in query_stats:
        query_stats.pop("statementType", None)
        return json.dumps(payload).encode()
    return body


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _handle(self):
        if self.command == "GET" and ROUTINES_RE.search(self.path):
            body = b'{"routines": [], "totalItems": 0}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None
        body = _inject_source_format(self.path, body)

        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP or key.lower() in ("host", "content-length"):
                continue
            req.add_header(key, value)
        if body is not None:
            req.add_header("Content-Length", str(len(body)))

        try:
            with urllib.request.urlopen(req) as resp:
                self._relay(resp.status, resp.headers, _scrub_response(self.path, resp.read()))
        except urllib.error.HTTPError as exc:
            self._relay(exc.code, exc.headers, _scrub_response(self.path, exc.read()))
        except Exception as exc:  # pragma: no cover - connection failures
            msg = str(exc).encode()
            self.send_response(502)
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def _relay(self, status, headers, body):
        self.send_response(status)
        for key, value in headers.items():
            if key.lower() in HOP_BY_HOP or key.lower() == "content-length":
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = _handle

    def log_message(self, *args):
        pass


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    with ThreadingServer(("127.0.0.1", LISTEN_PORT), Handler) as httpd:
        print(f"bq-proxy listening on {LISTEN_PORT}, forwarding to {UPSTREAM}", flush=True)
        httpd.serve_forever()

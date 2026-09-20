#!/usr/bin/env python3
"""A loopback stand-in for the boards API, for testing board.py's client half.

It is deliberately NOT a second implementation of the app. The app's rules —
validation, the state machine, the rev-equality check, the revise refusals — are
tested in `fredabood/work`, against the vendored core that board.py itself is the
source of. Re-testing them here would mean writing them twice and would prove
only that the two copies agree with each other.

What this DOES test is everything board.py still owns once the rules moved out:

  * that `new` / `revise` / `mark-harvested` send the right method, path and body;
  * that `freeze` writes the four files, commits them, and reports the sha it got
    back to the app;
  * that an HTTP failure becomes a readable BoardError rather than a traceback;
  * that `harvest-apply`'s freeze gate refuses on each of never-frozen, drifted
    and wrong-files, which is three different fixes and so three messages.

State lives in a JSON file so a test can set up "this board is drifted" without
the stub needing any of the logic that would make it drift.

    python3 stub_api.py <state.json>      # prints the base URL, serves until killed

`state.json`:
    {"boards": {"<repo>/<id>": {"files": {...}, "content_hash": "...",
                                "frozen_sha": null, "drifted": false}},
     "fail": {"POST /boards": [400, "agenda is invalid"]},
     "log": "<path>"}            # every request is appended here as JSON
"""
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = sys.argv[1]
LOCK = threading.Lock()


def load():
    with open(STATE) as fh:
        return json.load(fh)


def save(state):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)
    os.replace(tmp, STATE)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def reply(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else None
        except ValueError:
            body = None
        with LOCK:
            state = load()
            key = "%s %s" % (method, self.path)
            if state.get("log"):
                with open(state["log"], "a") as fh:
                    fh.write(json.dumps({
                        "key": key,
                        "token": self.headers.get("X-Service-Token"),
                        "content_type": self.headers.get("Content-Type"),
                        "body": body,
                    }) + "\n")
            fail = (state.get("fail") or {}).get(key)
            if fail:
                return self.reply(fail[0], {"error": fail[1]})
            return self.route(method, state, body)

    def route(self, method, state, body):
        path = self.path
        boards = state.get("boards") or {}
        if method == "POST" and path == "/boards":
            bid = (body or {}).get("id")
            repo = ((body or {}).get("repo") or "").split("/")[-1]
            ref = "%s/%s" % (repo, bid)
            if ref in boards:
                return self.reply(409, {"error": "%s already exists" % ref})
            boards[ref] = {"files": {}, "content_hash": "0" * 16,
                           "frozen_sha": None, "drifted": False}
            state["boards"] = boards
            save(state)
            cards = sum(len(s.get("cards") or []) for s in (body or {}).get("sections") or [])
            return self.reply(201, {"ok": True, "repo": repo, "board_id": bid, "cards": cards})

        parts = path.strip("/").split("/")
        if len(parts) >= 3 and parts[0] == "boards":
            ref = "%s/%s" % (parts[1], parts[2])
            board = boards.get(ref)
            if board is None:
                return self.reply(404, {"error": "no such decision board"})
            tail = parts[3] if len(parts) > 3 else ""
            if method == "GET" and tail == "export":
                return self.reply(200, {
                    "repo": parts[1], "board_id": parts[2],
                    "files": board["files"], "content_hash": board["content_hash"],
                    "frozen_sha": board.get("frozen_sha"),
                    "drifted": bool(board.get("drifted")),
                })
            if method == "POST" and tail == "freeze":
                if (body or {}).get("content_hash") not in (None, board["content_hash"]):
                    return self.reply(409, {"error": "the board changed between export and commit",
                                            "content_hash": board["content_hash"]})
                board["frozen_sha"] = (body or {}).get("sha")
                board["drifted"] = False
                save(state)
                return self.reply(200, {"ok": True, "sha": board["frozen_sha"],
                                        "content_hash": board["content_hash"], "drifted": False})
            if method == "POST" and tail == "revise":
                return self.reply(200, {"ok": True,
                                        "bumped": sorted((body or {}).get("bump") or []),
                                        "kept": sorted((body or {}).get("keep") or []),
                                        "snapshot": {"states": board.get("states") or {}}})
            if method == "POST" and tail == "harvest":
                return self.reply(200, {"ok": True, "target": (body or {}).get("target"),
                                        "cards": sorted((body or {}).get("cards") or [])})
        return self.reply(404, {"error": "not found"})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PUT(self):
        self.handle_any("PUT")


srv = HTTPServer(("127.0.0.1", 0), Handler)
print("http://127.0.0.1:%d" % srv.server_address[1], flush=True)
try:
    srv.serve_forever()
except KeyboardInterrupt:
    pass

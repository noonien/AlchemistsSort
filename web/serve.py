# Serves the browser build for `nix run .#web`, telling the browser not to
# keep any of it: the files in the Nix store all carry the same date, so
# http.server's "not modified since" answers would hand back an old build.

import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

    def send_head(self):
        # Always the file itself, never a 304.
        for h in ("If-Modified-Since", "If-None-Match"):
            del self.headers[h]
        return super().send_head()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    directory, port = sys.argv[1], int(sys.argv[2])
    handler = lambda *a, **k: Handler(*a, directory=directory, **k)
    print(f"Alchemist's Sort: http://localhost:{port}", flush=True)
    http.server.ThreadingHTTPServer(("", port), handler).serve_forever()


if __name__ == "__main__":
    main()

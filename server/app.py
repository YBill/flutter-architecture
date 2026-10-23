"""Local book API. Uses Python's standard library; no installation required."""

from __future__ import annotations

import argparse
import json
import logging
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


DEFAULT_DATA_DIR = Path(__file__).resolve().parent / "data" / "books"
LOGGER = logging.getLogger("novelverse.api")


class AndroidPortReverse:
    """Restore the development API mapping after USB or adb reconnects."""

    def __init__(self, adb: str, port: int):
        self.adb = adb
        self.port = f"tcp:{port}"
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self._watch, daemon=True)

    def _run(self, *args):
        return subprocess.run(
            [self.adb, *args], capture_output=True, text=True, check=True, timeout=5
        ).stdout

    def restore(self):
        for line in self._run("devices").splitlines():
            device = line.split()
            if len(device) < 2 or device[1] != "device":
                continue
            serial = device[0]
            try:
                mappings = self._run("-s", serial, "reverse", "--list")
                if any(
                    line.split()[-2:] == [self.port, self.port]
                    for line in mappings.splitlines()
                ):
                    continue
                self._run("-s", serial, "reverse", self.port, self.port)
                LOGGER.info("Android API connection restored: %s %s", serial, self.port)
            except (OSError, subprocess.SubprocessError) as error:
                # A disconnect during a command must not prevent other devices connecting.
                LOGGER.debug("Android device temporarily unavailable: %s", error)

    def _watch(self):
        previous_error = None
        while not self.stopped.is_set():
            try:
                self.restore()
                previous_error = None
            except (OSError, subprocess.SubprocessError) as error:
                message = str(error)
                if message != previous_error:
                    LOGGER.warning("Android API connection check failed: %s", message)
                    previous_error = message
            self.stopped.wait(2)

    def start(self):
        self.thread.start()

    def stop(self):
        self.stopped.set()
        self.thread.join(timeout=1)


class ApiError(Exception):
    def __init__(self, status: HTTPStatus, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


class BookStore:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.books = {
            self.read_json(detail)["id"]: detail.parent
            for detail in self.root.glob("*/detail.json")
        }
        if not self.books:
            raise ValueError(f"No book data found in {self.root}")

    @staticmethod
    def read_json(path: Path):
        return json.loads(path.read_text(encoding="utf-8"))

    def directory(self, book_id: str) -> Path:
        try:
            return self.books[book_id]
        except KeyError:
            raise ApiError(HTTPStatus.NOT_FOUND, "book_not_found", "Book not found.") from None

    def catalog(self, book_id: str):
        return self.read_json(self.directory(book_id) / "catalog.json")

    def chapter(self, book_id: str, chapter_id: str):
        meta = next(
            (item for item in self.catalog(book_id)["chapters"] if item["id"] == chapter_id),
            None,
        )
        if meta is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "chapter_not_found", "Chapter not found.")
        # File names come from trusted catalog indexes, never from request paths.
        body = (self.directory(book_id) / "chapters" / f"{meta['index'] + 1}.txt").read_text(
            encoding="utf-8"
        )
        first, separator, remainder = body.partition("\n")
        if separator and first.strip() == meta["title"]:
            body = remainder
        return {**meta, "body": body.strip()}

    def detail(self, book_id: str):
        detail = self.read_json(self.directory(book_id) / "detail.json")
        chapters = self.catalog(book_id)["chapters"]
        if chapters:
            detail["firstChapter"] = self.chapter(book_id, chapters[0]["id"])
        return detail

    def recommendations(self, book_id: str):
        directory = self.directory(book_id)
        specific = directory / "recommendations.json"
        return self.read_json(specific if specific.exists() else self.root / "recommendations.json")


class BookServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, store: BookStore, delay_ms: int):
        self.store = store
        self.delay_ms = delay_ms
        super().__init__(address, BookHandler)


class BookHandler(BaseHTTPRequestHandler):
    server: BookServer
    server_version = "NovelverseLocalAPI/1.0"

    def log_message(self, message, *args):
        LOGGER.info("%s %s", self.client_address[0], message % args)

    def send_json(self, status: HTTPStatus, value, *, allow: str | None = None):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if allow:
            self.send_header("Allow", allow)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # The app may leave the page or cancel an in-flight request.

    def do_GET(self):
        try:
            parts = [unquote(part) for part in urlsplit(self.path).path.split("/") if part]
            if not parts:
                result = {
                    "service": "Novelverse local book API",
                    "health": "/health",
                    "books": "/api/v1/books",
                }
            elif parts == ["health"]:
                result = {"status": "ok", "bookCount": len(self.server.store.books)}
            elif parts[:3] == ["api", "v1", "books"]:
                if self.server.delay_ms:
                    time.sleep(self.server.delay_ms / 1000)
                result = self.book_route(parts[3:])
            else:
                raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "Endpoint not found.")
            self.send_json(HTTPStatus.OK, result)
        except ApiError as error:
            self.send_json(error.status, {"error": {"code": error.code, "message": str(error)}})
        except Exception:
            LOGGER.exception("Unable to serve book data")
            self.send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"error": {"code": "data_error", "message": "Local book data is unavailable."}},
            )

    def book_route(self, parts):
        store = self.server.store
        if not parts:
            return store.read_json(store.root / "books.json")
        book_id = parts[0]
        store.directory(book_id)
        if len(parts) == 1:
            return store.detail(book_id)
        if parts[1:] == ["recommendations"]:
            return store.recommendations(book_id)
        if parts[1:] == ["chapters"]:
            return store.catalog(book_id)
        if len(parts) == 3 and parts[1] == "chapters":
            return store.chapter(book_id, parts[2])
        raise ApiError(HTTPStatus.NOT_FOUND, "not_found", "Endpoint not found.")

    def do_POST(self):
        self.send_json(
            HTTPStatus.METHOD_NOT_ALLOWED,
            {"error": {"code": "method_not_allowed", "message": "Use GET for this API."}},
            allow="GET",
        )


def create_server(host="127.0.0.1", port=8787, data_dir=DEFAULT_DATA_DIR, delay_ms=150):
    if not 0 <= port <= 65535 or delay_ms < 0:
        raise ValueError("Port must be 0–65535 and delay must be nonnegative.")
    return BookServer((host, port), BookStore(Path(data_dir)), delay_ms)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8787, type=int)
    parser.add_argument("--delay-ms", default=150, type=int)
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR, type=Path)
    parser.add_argument("--adb", help="Automatically restore Android API port mappings using this adb executable")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    with create_server(args.host, args.port, args.data_dir, args.delay_ms) as server:
        base = f"http://{args.host}:{server.server_port}"
        print(f"Novelverse local API: {base}/api/v1/", flush=True)
        print(f"Health: {base}/health | Delay: {args.delay_ms} ms", flush=True)
        print(f"Data: {server.store.root}", flush=True)
        bridge = AndroidPortReverse(args.adb, server.server_port) if args.adb else None
        if bridge:
            bridge.start()
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.", flush=True)
        finally:
            if bridge:
                bridge.stop()


if __name__ == "__main__":
    main()

import json
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server.app import create_server


class BookApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = create_server(port=0, delay_ms=0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=3)

    def get(self, path):
        with urlopen(self.base + path, timeout=5) as response:
            self.assertEqual(response.status, 200)
            self.assertIn("application/json", response.headers["Content-Type"])
            return json.load(response)

    def book_id(self):
        return self.get("/api/v1/books")["items"][0]["id"]

    def test_detail_contains_first_chapter_and_recommendations_are_independent(self):
        self.assertEqual(self.get("/health")["status"], "ok")
        book_id = self.book_id()
        detail = self.get(f"/api/v1/books/{book_id}")
        catalog = self.get(f"/api/v1/books/{book_id}/chapters")
        first = self.get(f"/api/v1/books/{book_id}/chapters/{catalog['chapters'][0]['id']}")
        self.assertEqual(detail["firstChapter"], first)
        self.assertEqual(detail["chapterCount"], len(catalog["chapters"]))
        self.assertTrue(detail["coverUrl"].startswith("https://"))
        self.assertNotIn("body", catalog["chapters"][0])
        self.assertFalse(first["body"].startswith(first["title"] + "\n"))
        recommendations = self.get(f"/api/v1/books/{book_id}/recommendations")["items"]
        self.assertEqual(len(recommendations), 6)
        self.assertTrue(all(item["targetBookId"] == book_id for item in recommendations))

    def test_later_chapters_are_addressable_without_fetching_previous_bodies(self):
        book_id = self.book_id()
        catalog = self.get(f"/api/v1/books/{book_id}/chapters")
        metas = [catalog["chapters"][149], catalog["chapters"][-1]]
        with ThreadPoolExecutor(max_workers=2) as pool:
            bodies = list(pool.map(
                lambda meta: self.get(f"/api/v1/books/{book_id}/chapters/{meta['id']}"),
                metas,
            ))
        for meta, chapter in zip(metas, bodies):
            self.assertEqual(chapter["id"], meta["id"])
            self.assertEqual(chapter["version"], meta["version"])
            self.assertEqual(chapter["index"], meta["index"])
            self.assertGreater(len(chapter["body"]), 1000)

    def test_missing_and_traversal_paths_return_json_404(self):
        book_id = self.book_id()
        for path in [
            "/unknown",
            "/api/v1/books/missing",
            f"/api/v1/books/{book_id}/chapters/missing",
            "/api/v1/books/%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        ]:
            with self.subTest(path=path), self.assertRaises(HTTPError) as raised:
                self.get(path)
            with raised.exception as response:
                self.assertEqual(response.code, 404)
                self.assertIn("error", json.load(response))

    def test_post_cannot_mutate_fixture_data(self):
        request = Request(self.base + "/api/v1/books", data=b"{}", method="POST")
        with self.assertRaises(HTTPError) as raised:
            urlopen(request, timeout=5)
        with raised.exception as response:
            self.assertEqual(response.code, 405)
            self.assertEqual(response.headers["Allow"], "GET")


if __name__ == "__main__":
    unittest.main()

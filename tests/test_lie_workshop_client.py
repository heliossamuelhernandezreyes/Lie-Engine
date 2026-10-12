import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

from tools.lie_workshop_client import WorkshopBusy, WorkshopClient, WorkshopTimeout


class LiveClientTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.client = WorkshopClient(self.directory, timeout=1)

    def tearDown(self):
        self.temp.cleanup()

    def responder(self, result=None):
        consumed = []
        def work():
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                inbox = self.directory / "inbox.json"
                if inbox.exists():
                    request = json.loads(inbox.read_text())
                    consumed.append(request)
                    inbox.unlink()
                    temporary = self.directory / "outbox.tmp"
                    temporary.write_text(json.dumps({"request_id": request["request_id"],
                        "result": result or {"ok": True, "revision": 7}, "snapshot": {"revision": 7}}))
                    temporary.replace(self.directory / "outbox.json")
                    return
                time.sleep(.005)
        worker = threading.Thread(target=work)
        worker.start()
        self.addCleanup(worker.join)
        return consumed

    def test_stale_response_is_not_accepted(self):
        (self.directory / "outbox.json").write_text(json.dumps({"request_id": "old", "result": {"ok": True}, "snapshot": {}}))
        consumed = self.responder()
        response = self.client.request({"op": "set_time", "value": 1, "expected_revision": 6})
        self.assertEqual(response["request_id"], consumed[0]["request_id"])
        self.assertEqual(consumed[0]["request"]["expected_revision"], 6)
        self.assertFalse((self.directory / ".agent-client.lock").exists())

    def test_malformed_previous_response_is_ignored(self):
        (self.directory / "outbox.json").write_text("{")
        self.responder()
        self.assertTrue(self.client.request({"op": "snapshot"})["result"]["ok"])

    def test_revision_conflict_is_returned_without_retry(self):
        consumed = self.responder({"ok": False, "error": "revision_conflict", "revision": 7})
        response = self.client.request({"op": "undo", "expected_revision": 0})
        self.assertEqual(response["result"]["error"], "revision_conflict")
        self.assertEqual(len(consumed), 1)

    def test_pending_inbox_is_never_overwritten(self):
        inbox = self.directory / "inbox.json"
        inbox.write_text("keep")
        with self.assertRaises(WorkshopBusy):
            self.client.request({"op": "snapshot"})
        self.assertEqual(inbox.read_text(), "keep")
        self.assertEqual(list(self.directory.glob("*.tmp")), [])

    def test_client_lock_prevents_second_producer(self):
        (self.directory / ".agent-client.lock").write_text("owner")
        with self.assertRaises(WorkshopBusy):
            self.client.request({"op": "snapshot"})
        self.assertEqual((self.directory / ".agent-client.lock").read_text(), "owner")

    def test_timeout_does_not_delete_or_repeat_command(self):
        self.client.timeout = .08
        with self.assertRaises(WorkshopTimeout) as error:
            self.client.request({"op": "duplicate_piece", "id": "new", "source": "head"})
        pending = json.loads((self.directory / "inbox.json").read_text())
        self.assertEqual(pending["request_id"], error.exception.request_id)
        self.assertFalse((self.directory / ".agent-client.lock").exists())

    def test_invalid_and_oversized_commands_are_not_published(self):
        for request in [[], {}, {"op": "set_time", "value": float("nan")}, {"op": "snapshot", "padding": "a" * 1024 * 1024}]:
            with self.assertRaises(ValueError):
                self.client.request(request)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_timeout_must_be_finite_positive(self):
        for timeout in [0, -1, float("nan"), float("inf")]:
            with self.assertRaises(ValueError):
                WorkshopClient(self.directory, timeout)


if __name__ == "__main__":
    unittest.main()

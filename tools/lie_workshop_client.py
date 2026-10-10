"""Send validated JSON commands to an already running Lie Workshop.

The directory is the absolute inbox/outbox directory from agent_snapshot().
No socket, engine import, third-party dependency or arbitrary code evaluation.
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import sys
import time
import uuid

MAX_BYTES = 1024 * 1024


class WorkshopBusy(RuntimeError):
    pass


class WorkshopTimeout(TimeoutError):
    def __init__(self, request_id: str):
        self.request_id = request_id
        super().__init__(f"No matching response for {request_id}; the command may still execute. Do not retry blindly.")


class WorkshopClient:
    def __init__(self, directory: str | Path, timeout: float = 30):
        self.directory = Path(directory).resolve()
        if not self.directory.is_dir():
            raise ValueError("Use the existing absolute workshop directory returned by agent_snapshot().")
        if not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("timeout must be finite and positive")
        self.timeout = timeout

    def request(self, command: dict) -> dict:
        if not isinstance(command, dict) or not isinstance(command.get("op"), str):
            raise ValueError("A command requires a string op.")
        request_id = uuid.uuid4().hex
        payload = json.dumps({"request_id": request_id, "request": command}, allow_nan=False).encode("utf-8")
        if len(payload) > MAX_BYTES:
            raise ValueError("Command exceeds the workshop's 1 MiB inbox limit.")
        lock = self.directory / ".agent-client.lock"
        try:
            descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError as error:
            raise WorkshopBusy("Another client owns the workshop inbox; inspect a stale lock before removing it.") from error
        inbox = self.directory / "inbox.json"
        temporary = self.directory / f"inbox.{request_id}.tmp"
        try:
            os.write(descriptor, request_id.encode("ascii"))
            os.close(descriptor)
            descriptor = None
            with temporary.open("xb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                # Atomic publication without replacing an unconsumed command.
                os.link(temporary, inbox)
            except FileExistsError as error:
                raise WorkshopBusy("An unconsumed inbox command already exists.") from error
            temporary.unlink()
            deadline = time.monotonic() + self.timeout
            while time.monotonic() < deadline:
                try:
                    outbox = self.directory / "outbox.json"
                    if outbox.stat().st_size <= MAX_BYTES:
                        response = json.loads(outbox.read_text(encoding="utf-8"))
                        if (isinstance(response, dict) and response.get("request_id") == request_id
                                and isinstance(response.get("result"), dict)
                                and isinstance(response.get("snapshot"), dict)):
                            return response
                except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
                    pass
                time.sleep(min(.05, max(0, deadline - time.monotonic())))
            # Leave a pending command intact: timeout does not mean rejection.
            raise WorkshopTimeout(request_id)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            temporary.unlink(missing_ok=True)
            lock.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--timeout", type=float, default=30)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--command", help="JSON command; default is snapshot")
    source.add_argument("--file", type=Path, help="JSON command file")
    parser.add_argument("--expected-revision", type=int)
    parser.add_argument("--output", type=Path, help="Write the complete response atomically instead of printing it")
    args = parser.parse_args()
    try:
        command = json.loads(args.file.read_text(encoding="utf-8") if args.file else args.command or '{"op":"snapshot"}')
        if args.expected_revision is not None:
            if not isinstance(command, dict):
                raise ValueError("Expected a JSON object")
            if "expected_revision" in command and command["expected_revision"] != args.expected_revision:
                raise ValueError("Conflicting expected revisions")
            command["expected_revision"] = args.expected_revision
        response = WorkshopClient(args.directory, args.timeout).request(command)
        encoded = json.dumps(response, ensure_ascii=False, indent=2, allow_nan=False)
        if args.output:
            temporary = args.output.with_name(args.output.name + "." + uuid.uuid4().hex + ".tmp")
            try:
                temporary.write_text(encoded, encoding="utf-8")
                temporary.replace(args.output)
            finally:
                temporary.unlink(missing_ok=True)
        else:
            print(encoded)
        return 0 if response["result"].get("ok") else 1
    except (OSError, ValueError, RuntimeError, WorkshopTimeout) as error:
        print(json.dumps({"ok": False, "error": str(error), "request_id": getattr(error, "request_id", None)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

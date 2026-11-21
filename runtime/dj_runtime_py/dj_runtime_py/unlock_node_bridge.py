from __future__ import annotations

import json
import queue
import subprocess
import threading
import time
from pathlib import Path
from typing import Any


class UnlockNodeBridgeError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class UnlockNodeBridge:
    def __init__(
        self,
        node_executable: str,
        working_directory: str,
        entry_script: str,
    ) -> None:
        self._node_executable = node_executable
        self._working_directory = str(Path(working_directory).resolve())
        self._entry_script = str(Path(entry_script).resolve())
        self._process: subprocess.Popen[str] | None = None
        self._request_index = 0
        self._lock = threading.Lock()
        self._process_lock = threading.Lock()
        self._response_queue: queue.Queue[str | None] = queue.Queue()
        self._reader_thread: threading.Thread | None = None
        self._stderr_thread: threading.Thread | None = None
        self._stderr_lines: list[str] = []
        self._cancel_event = threading.Event()
        self._request_timeout_seconds = 300.0

    def _is_process_alive(self) -> bool:
        process = self._process
        return process is not None and process.poll() is None

    def ensure_started(self) -> None:
        with self._process_lock:
            if self._is_process_alive():
                return
            if self._process is not None:
                self._terminate_process_locked()
            try:
                entry_script = Path(self._entry_script)
                working_directory = Path(self._working_directory)
                if not entry_script.exists():
                    raise FileNotFoundError(str(entry_script))
                if not working_directory.exists():
                    raise FileNotFoundError(str(working_directory))
                self._stderr_lines = []
                self._process = subprocess.Popen(
                    [self._node_executable, str(entry_script)],
                    cwd=str(working_directory),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    bufsize=1,
                )
                process = self._process
                self._response_queue = queue.Queue()
                self._reader_thread = threading.Thread(
                    target=self._read_stdout,
                    args=(process, self._response_queue),
                    name="unlock-node-stdout",
                    daemon=True,
                )
                self._reader_thread.start()
                self._stderr_thread = threading.Thread(
                    target=self._read_stderr,
                    args=(process,),
                    name="unlock-node-stderr",
                    daemon=True,
                )
                self._stderr_thread.start()
            except OSError as exc:
                self._process = None
                raise UnlockNodeBridgeError(
                    "INTERNAL_ERROR",
                    f"无法启动 Node unlock worker: {exc}",
                ) from exc

    def _read_stdout(self, process: subprocess.Popen[str], response_queue: queue.Queue[str | None]) -> None:
        stdout = process.stdout
        if stdout is None:
            response_queue.put(None)
            return
        try:
            while True:
                line = stdout.readline()
                if not line:
                    break
                response_queue.put(line)
        except (OSError, ValueError):
            pass
        finally:
            response_queue.put(None)

    def _read_stderr(self, process: subprocess.Popen[str]) -> None:
        stderr = process.stderr
        if stderr is None:
            return
        try:
            for line in stderr:
                value = line.rstrip()
                if value:
                    self._stderr_lines.append(value)
                    if len(self._stderr_lines) > 30:
                        del self._stderr_lines[:-30]
        except (OSError, ValueError):
            return

    def _last_stderr_text(self) -> str:
        if not self._stderr_lines:
            return ""
        return "\n".join(self._stderr_lines[-8:])

    def _terminate_process_locked(self) -> None:
        process = self._process
        self._process = None
        if process is None:
            return
        try:
            if process.stdin is not None and not process.stdin.closed:
                process.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            try:
                process.kill()
                process.wait(timeout=1)
            except (OSError, subprocess.TimeoutExpired):
                pass
        for stream in (process.stdout, process.stderr):
            try:
                if stream is not None and not stream.closed:
                    stream.close()
            except (OSError, ValueError):
                pass
        self._response_queue.put(None)

    def cancel_current(self) -> None:
        self._cancel_event.set()

    def health_check(self) -> dict[str, Any]:
        return self.request("health_check", {})

    def unlock_file(
        self,
        input_path: str,
        output_dir: str,
        overwrite: bool,
        keep_source: bool,
    ) -> dict[str, Any]:
        return self.request(
            "unlock_file",
            {
                "input_path": str(Path(input_path).resolve()),
                "output_dir": str(Path(output_dir).resolve()),
                "overwrite": overwrite,
                "keep_source": keep_source,
            },
        )

    def request(self, action: str, payload: dict[str, Any]) -> dict[str, Any]:
        self._cancel_event.clear()
        self.ensure_started()
        process = self._process
        if process is None or process.stdin is None:
            raise UnlockNodeBridgeError("INTERNAL_ERROR", "Node unlock worker 未启动。")
        with self._lock:
            if not self._is_process_alive():
                self.ensure_started()
                process = self._process
            if process is None or process.stdin is None:
                raise UnlockNodeBridgeError("INTERNAL_ERROR", "Node unlock worker 未启动。")
            self._request_index += 1
            request_id = f"req_{self._request_index:03d}"
            request = {
                "id": request_id,
                "action": action,
                "payload": payload,
            }
            try:
                process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
                process.stdin.flush()
            except (OSError, ValueError) as exc:
                self._restart_after_failure_locked()
                raise UnlockNodeBridgeError(
                    "INTERNAL_ERROR",
                    f"Node unlock worker 已断开: {exc}",
                ) from exc
            deadline = time.monotonic() + self._request_timeout_seconds
            while True:
                if self._cancel_event.is_set():
                    self._restart_after_failure_locked()
                    raise UnlockNodeBridgeError("CANCELLED", "解锁任务已由用户取消。")
                try:
                    raw_response = self._response_queue.get(timeout=0.2)
                except queue.Empty:
                    if process.poll() is not None:
                        self._restart_after_failure_locked()
                        stderr_text = self._last_stderr_text()
                        message = "Node unlock worker 已退出。"
                        if stderr_text:
                            message += f"\n{stderr_text}"
                        raise UnlockNodeBridgeError("INTERNAL_ERROR", message)
                    if time.monotonic() >= deadline:
                        self._restart_after_failure_locked()
                        raise UnlockNodeBridgeError(
                            "TIMEOUT",
                            f"解锁处理超时（{int(self._request_timeout_seconds)} 秒），已停止当前任务。",
                        )
                    continue
                break
            if raw_response is None:
                self._restart_after_failure_locked()
                raise UnlockNodeBridgeError("INTERNAL_ERROR", "Node unlock worker 未返回响应。")
            try:
                response = json.loads(raw_response)
            except json.JSONDecodeError as exc:
                self._restart_after_failure_locked()
                raise UnlockNodeBridgeError("INTERNAL_ERROR", "Node unlock worker 返回了非法响应。") from exc
            if response.get("id") != request_id:
                self._restart_after_failure_locked()
                raise UnlockNodeBridgeError(
                    "INTERNAL_ERROR",
                    "Node unlock worker 响应 request_id 不匹配。",
                )
            if not response.get("ok"):
                error = response.get("error") or {}
                raise UnlockNodeBridgeError(
                    str(error.get("code") or "UNLOCK_FAILED"),
                    str(error.get("message") or "Node unlock worker 执行失败。"),
                )
            data = response.get("data")
            return data if isinstance(data, dict) else {}

    def _restart_after_failure_locked(self) -> None:
        with self._process_lock:
            self._terminate_process_locked()

    def close(self) -> None:
        with self._process_lock:
            self._terminate_process_locked()

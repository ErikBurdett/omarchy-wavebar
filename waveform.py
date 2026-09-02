#!/usr/bin/python3
"""Stream a selected PipeWire node as normalized waveform frames.

The helper never invokes a shell and never opens the network. It asks the
PipeWire CLI already shipped by Omarchy to tap one explicitly selected node,
then emits semicolon-delimited frames for Quickshell's SplitParser.
"""

from __future__ import annotations

import argparse
import array
import math
import os
import signal
import stat
import subprocess
import sys
from collections.abc import Iterable


SAMPLE_RATE = 12_000
FPS = 24
PYTHON_PATH = "/usr/bin/python3"
PW_RECORD_PATH = "/usr/bin/pw-record"
SETPRIV_PATH = "/usr/bin/setpriv"
MAX_TARGET_BYTES = 256
MAX_FRAME_BYTES = 384
TERM_TIMEOUT = 1.0


def trusted_executable(path: str) -> str:
    """Accept only root-controlled executables rooted in /usr/bin."""
    if not path.startswith("/usr/bin/") or os.path.dirname(path) != "/usr/bin":
        raise RuntimeError("untrusted executable path")

    directory = os.stat("/usr/bin", follow_symlinks=False)
    link = os.lstat(path)
    target_path = os.path.realpath(path)
    target = os.stat(target_path, follow_symlinks=False)
    if (
        directory.st_uid != 0
        or directory.st_mode & 0o022
        or link.st_uid != 0
        or not target_path.startswith("/usr/bin/")
        or not stat.S_ISREG(target.st_mode)
        or target.st_uid != 0
        or target.st_mode & 0o022
        or not target.st_mode & 0o111
    ):
        raise RuntimeError("untrusted executable ownership or mode")
    return path


def recorder_environment() -> dict[str, str]:
    """Build the complete child environment without inheriting user values."""
    runtime_dir = f"/run/user/{os.getuid()}"
    runtime = os.stat(runtime_dir, follow_symlinks=False)
    if (
        not stat.S_ISDIR(runtime.st_mode)
        or runtime.st_uid != os.getuid()
        or runtime.st_mode & 0o077
    ):
        raise RuntimeError("unsafe runtime directory")
    return {
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PATH": "/usr/bin",
        "XDG_RUNTIME_DIR": runtime_dir,
    }


def checked_target(value: str) -> str:
    encoded = value.encode("utf-8", errors="strict")
    if not encoded or len(encoded) > MAX_TARGET_BYTES:
        raise ValueError("invalid target length")
    if any(byte < 0x20 or byte == 0x7F for byte in encoded):
        raise ValueError("invalid target characters")
    return value


def waveform_frame(samples: Iterable[int], bars: int, previous: list[float]) -> list[float]:
    values = list(samples)
    if bars < 1:
        raise ValueError("bars must be positive")
    if not values:
        return [value * 0.72 for value in previous]

    block_size = max(1, math.ceil(len(values) / bars))
    result: list[float] = []
    for index in range(bars):
        block = values[index * block_size : (index + 1) * block_size]
        peak = max((abs(value) for value in block), default=0) / 32768.0
        # Suppress converter noise, then emphasize quiet music without making
        # loud frames permanently pin the visualizer.
        normalized = 0.0 if peak < 0.004 else min(1.0, peak ** 0.55)
        prior = previous[index] if index < len(previous) else 0.0
        result.append(max(normalized, prior * 0.72))
    return result


def emit(frame: list[float]) -> None:
    payload = ";".join(f"{value:.3f}" for value in frame).encode("ascii")
    if len(payload) > MAX_FRAME_BYTES:
        raise RuntimeError("waveform frame exceeded protocol limit")
    sys.stdout.buffer.write(payload + b"\n")
    sys.stdout.buffer.flush()


def read_exact(stream: object, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining > 0:
        chunk = stream.read(remaining)  # type: ignore[attr-defined]
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def signal_process_group(process: subprocess.Popen[bytes], signum: int) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass


def reap_process_group(process: subprocess.Popen[bytes]) -> int:
    """Terminate the recorder group, escalate to KILL, and always reap it."""
    if process.poll() is None:
        signal_process_group(process, signal.SIGTERM)
    try:
        return process.wait(timeout=TERM_TIMEOUT)
    except subprocess.TimeoutExpired:
        signal_process_group(process, signal.SIGKILL)
        return process.wait()


def run(target: str, bars: int) -> int:
    trusted_executable(PYTHON_PATH)
    recorder = trusted_executable(PW_RECORD_PATH)
    setpriv = trusted_executable(SETPRIV_PATH)
    target = checked_target(target)

    command = [
        setpriv,
        "--pdeathsig",
        "KILL",
        "--",
        recorder,
        "--raw",
        "--rate",
        str(SAMPLE_RATE),
        "--channels",
        "1",
        "--format",
        "s16",
        "--latency",
        "50ms",
        "--target",
        target,
        "-",
    ]
    process = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=recorder_environment(),
        close_fds=True,
        start_new_session=True,
        bufsize=0,
    )

    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True
        signal_process_group(process, signal.SIGTERM)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    previous = [0.0] * bars
    samples_per_frame = max(bars, SAMPLE_RATE // FPS)
    byte_count = samples_per_frame * 2

    exit_code = 0
    try:
        assert process.stdout is not None
        while not stopping:
            payload = read_exact(process.stdout, byte_count)
            if len(payload) < 2:
                break
            if len(payload) % 2:
                payload = payload[:-1]
            pcm = array.array("h")
            pcm.frombytes(payload)
            if sys.byteorder != "little":
                pcm.byteswap()
            previous = waveform_frame(pcm, bars, previous)
            emit(previous)
    finally:
        exit_code = reap_process_group(process)
    return exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="PipeWire node name or serial")
    parser.add_argument("--bars", type=int, default=24)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 4 <= args.bars <= 96:
        print("waveform helper rejected an invalid bar count", file=sys.stderr)
        return 2
    try:
        return run(args.target, args.bars)
    except (OSError, RuntimeError, UnicodeError, ValueError):
        print("waveform helper safety check failed", file=sys.stderr)
        return 126


if __name__ == "__main__":
    raise SystemExit(main())

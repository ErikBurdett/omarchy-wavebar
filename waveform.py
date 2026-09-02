#!/usr/bin/env python3
"""Stream a selected PipeWire node as normalized waveform frames.

The helper never invokes a shell and never opens the network. It asks the
PipeWire CLI already shipped by Omarchy to tap one explicitly selected node,
then emits semicolon-delimited frames for Quickshell's SplitParser.
"""

from __future__ import annotations

import argparse
import array
import math
import shutil
import signal
import subprocess
import sys
from collections.abc import Iterable


SAMPLE_RATE = 12_000
FPS = 24


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
    print(";".join(f"{value:.3f}" for value in frame), flush=True)


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


def run(target: str, bars: int) -> int:
    recorder = shutil.which("pw-record")
    if not recorder:
        print("pw-record is required (package: pipewire-audio)", file=sys.stderr, flush=True)
        return 127

    command = [
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
    process = subprocess.Popen(command, stdout=subprocess.PIPE)

    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True
        if process.poll() is None:
            process.terminate()

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
        if process.poll() is None:
            process.terminate()
        try:
            exit_code = process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            process.kill()
            exit_code = process.wait()
    return exit_code


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="PipeWire node name or serial")
    parser.add_argument("--bars", type=int, default=24)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 4 <= args.bars <= 96:
        print("--bars must be between 4 and 96", file=sys.stderr)
        return 2
    return run(args.target, args.bars)


if __name__ == "__main__":
    raise SystemExit(main())

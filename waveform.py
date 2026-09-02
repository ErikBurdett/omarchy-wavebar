#!/usr/bin/python3
"""Stream a selected PipeWire node as bounded waveform frames.

The helper never invokes a shell or opens the network. A small internal
supervisor keeps a stable process-group identity around pw-record, closes the
Linux parent-death setup race, and guarantees TERM-to-KILL descendant cleanup.
"""

from __future__ import annotations

import argparse
import array
import ctypes
import errno
import math
import os
import selectors
import signal
import stat
import subprocess
import sys
import time
from collections.abc import Callable, Iterable


SAMPLE_RATE = 12_000
FPS = 24
PYTHON_PATH = "/usr/bin/python3"
PW_RECORD_PATH = "/usr/bin/pw-record"
MAX_TARGET_BYTES = 256
MAX_FRAME_BYTES = 384
TERM_TIMEOUT = 1.0
PARENT_GONE_EXIT = 125
PR_SET_PDEATHSIG = 1
PR_SET_CHILD_SUBREAPER = 36
INTERNAL_SUPERVISE = "supervise"
INTERNAL_RECORD = "record"

LIBC = ctypes.CDLL(None, use_errno=True)
LIBC.prctl.restype = ctypes.c_int


def _prctl(option: int, value: int) -> None:
    if LIBC.prctl(option, value, 0, 0, 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def arm_parent_death(expected_parent: int, signum: int) -> None:
    """Arm PDEATHSIG, then close its non-retroactive parent-exit race."""
    _prctl(PR_SET_PDEATHSIG, signum)
    if os.getppid() != expected_parent:
        os._exit(PARENT_GONE_EXIT)


def enable_subreaper() -> None:
    """Adopt orphaned descendants so this helper can reap the whole tree."""
    _prctl(PR_SET_CHILD_SUBREAPER, 1)


def unblock_signals(*signals: signal.Signals) -> None:
    """Do not trust a GUI parent's inherited signal mask."""
    signal.pthread_sigmask(signal.SIG_UNBLOCK, set(signals))


def trusted_executable(path: str) -> str:
    """Accept only root-controlled, ordinary executables rooted in /usr/bin."""
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
        or target.st_mode & (stat.S_ISUID | stat.S_ISGID)
        or not target.st_mode & 0o111
    ):
        raise RuntimeError("untrusted executable ownership or mode")

    # Linux clears PDEATHSIG when execing a file with capabilities, just as it
    # does for setuid/setgid files. Reject that case explicitly.
    try:
        capabilities = os.getxattr(target_path, "security.capability", follow_symlinks=False)
    except OSError as error:
        no_attribute = {errno.ENODATA, getattr(errno, "ENOATTR", errno.ENODATA)}
        if error.errno not in no_attribute:
            raise
    else:
        if capabilities:
            raise RuntimeError("executable capabilities are not allowed")
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


def drain_wakeup(wakeup_fd: int) -> None:
    """Discard queued signal bytes without ever blocking."""
    while True:
        try:
            if not os.read(wakeup_fd, 128):
                return
        except BlockingIOError:
            return


def read_exact_wakeable(
    selector: selectors.BaseSelector,
    stream_fd: int,
    wakeup_fd: int,
    size: int,
    should_stop: Callable[[], bool],
) -> tuple[bytes, bool]:
    """Read one frame while remaining immediately wakeable for teardown.

    CPython transparently retries interrupted reads (PEP 475), so a plain
    blocking read cannot be the helper's shutdown boundary. The signal wakeup
    pipe gives the selector an explicit event even when a hostile recorder
    descendant ignores TERM and keeps the audio pipe open.
    """
    chunks = bytearray()
    eof = False
    while len(chunks) < size and not should_stop():
        for key, _mask in selector.select(timeout=0.25):
            if key.fd == wakeup_fd:
                drain_wakeup(wakeup_fd)
                if should_stop():
                    return bytes(chunks), False
                continue

            chunk = os.read(stream_fd, size - len(chunks))
            if not chunk:
                eof = True
                return bytes(chunks), eof
            chunks.extend(chunk)
    return bytes(chunks), eof


def signal_process_group(process_group: int, signum: int) -> None:
    """Signal the dedicated group without a racy liveness pre-check."""
    if process_group <= 1:
        raise RuntimeError("refusing unsafe process group")
    try:
        os.killpg(process_group, signum)
    except ProcessLookupError:
        pass


def wait_term_window() -> None:
    deadline = time.monotonic() + TERM_TIMEOUT
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        time.sleep(min(0.05, remaining))


def reap_adopted_children() -> None:
    """Wait until every descendant adopted through subreaper ownership exits."""
    while True:
        try:
            os.waitpid(-1, 0)
        except ChildProcessError:
            return
        except InterruptedError:
            continue


def reap_process_group(process: subprocess.Popen[bytes]) -> int:
    """TERM, KILL, and reap a supervisor-pinned process group."""
    process_group = process.pid
    # Never poll or reap the group leader before the last group signal. The
    # live (or unreaped) supervisor pins its PID/PGID, preventing reuse.
    signal_process_group(process_group, signal.SIGTERM)
    wait_term_window()
    signal_process_group(process_group, signal.SIGKILL)
    exit_code = process.wait()
    reap_adopted_children()
    return exit_code


def recorder_command(target: str) -> list[str]:
    return [
        PW_RECORD_PATH,
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


def exec_recorder(target: str, expected_parent: int) -> int:
    """Race-safely arm parent death before replacing this process."""
    arm_parent_death(expected_parent, signal.SIGKILL)
    recorder = trusted_executable(PW_RECORD_PATH)
    target = checked_target(target)
    command = recorder_command(target)
    command[0] = recorder
    os.execve(recorder, command, recorder_environment())
    return 126


def supervise_recorder(target: str, expected_parent: int, helper_path: str) -> int:
    """Stay as the dedicated group leader until every member is terminated."""
    arm_parent_death(expected_parent, signal.SIGUSR1)
    enable_subreaper()
    trusted_executable(PYTHON_PATH)
    target = checked_target(target)

    tearing_down = False

    def ignore_stop(_signum: int, _frame: object) -> None:
        # The outer helper owns normal teardown. Remaining alive here keeps the
        # group identity pinned until the final group-wide SIGKILL.
        return

    def parent_gone(_signum: int, _frame: object) -> None:
        nonlocal tearing_down
        if tearing_down:
            return
        tearing_down = True
        process_group = os.getpgrp()
        signal_process_group(process_group, signal.SIGTERM)
        wait_term_window()
        signal_process_group(process_group, signal.SIGKILL)

    signal.signal(signal.SIGTERM, ignore_stop)
    signal.signal(signal.SIGINT, ignore_stop)
    signal.signal(signal.SIGUSR1, parent_gone)
    unblock_signals(signal.SIGTERM, signal.SIGINT, signal.SIGUSR1)

    command = [
        PYTHON_PATH,
        "-I",
        "-S",
        helper_path,
        "--internal-mode",
        INTERNAL_RECORD,
        "--expected-parent",
        str(os.getpid()),
        "--target",
        target,
    ]
    recorder = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=None,
        stderr=subprocess.DEVNULL,
        env=recorder_environment(),
        close_fds=True,
        start_new_session=False,
        bufsize=0,
    )

    # The recorder inherited fd 1. Closing the supervisor's copy lets the
    # outer helper observe EOF even though this stable group leader stays up.
    os.close(sys.stdout.fileno())
    recorder.wait()

    # A recorder that exits first may leave descendants. Keep the supervisor
    # alive while terminating the entire still-pinned group atomically.
    parent_gone(signal.SIGCHLD, None)
    return 0


def run(target: str, bars: int, helper_path: str) -> int:
    trusted_executable(PYTHON_PATH)
    trusted_executable(PW_RECORD_PATH)
    target = checked_target(target)
    enable_subreaper()

    stopping = False
    supervisor: subprocess.Popen[bytes] | None = None
    stream_selector: selectors.BaseSelector | None = None
    wakeup_read = -1
    wakeup_write = -1
    previous_wakeup = -1

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True
        if supervisor is not None:
            signal_process_group(supervisor.pid, signal.SIGTERM)

    unexpected_eof = False
    try:
        # Install handlers and the nonblocking signal wakeup fd before
        # forking. If a stop arrives while Popen is returning, the state and
        # wake byte are both retained and applied as soon as setup resumes.
        wakeup_read, wakeup_write = os.pipe2(os.O_CLOEXEC | os.O_NONBLOCK)
        previous_wakeup = signal.set_wakeup_fd(wakeup_write)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        unblock_signals(signal.SIGTERM, signal.SIGINT)

        command = [
            PYTHON_PATH,
            "-I",
            "-S",
            helper_path,
            "--internal-mode",
            INTERNAL_SUPERVISE,
            "--expected-parent",
            str(os.getpid()),
            "--target",
            target,
        ]
        supervisor = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=recorder_environment(),
            close_fds=True,
            start_new_session=True,
            bufsize=0,
        )
        if stopping:
            signal_process_group(supervisor.pid, signal.SIGTERM)

        previous = [0.0] * bars
        samples_per_frame = max(bars, SAMPLE_RATE // FPS)
        byte_count = samples_per_frame * 2
        assert supervisor.stdout is not None
        stream_fd = supervisor.stdout.fileno()
        stream_selector = selectors.DefaultSelector()
        stream_selector.register(stream_fd, selectors.EVENT_READ)
        stream_selector.register(wakeup_read, selectors.EVENT_READ)
        while not stopping:
            payload, eof = read_exact_wakeable(
                stream_selector,
                stream_fd,
                wakeup_read,
                byte_count,
                lambda: stopping,
            )
            if stopping:
                break
            if eof and len(payload) < byte_count:
                unexpected_eof = True
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
        # Remove the group from the async signal handler before reaping its
        # pinned leader. A later signal can no longer address that numeric
        # PGID after wait() makes it reusable.
        managed_supervisor = supervisor
        supervisor = None
        try:
            if managed_supervisor is not None:
                reap_process_group(managed_supervisor)
        finally:
            if stream_selector is not None:
                stream_selector.close()
            if managed_supervisor is not None and managed_supervisor.stdout is not None:
                managed_supervisor.stdout.close()
            if wakeup_write >= 0:
                signal.set_wakeup_fd(previous_wakeup)
                os.close(wakeup_write)
            if wakeup_read >= 0:
                os.close(wakeup_read)
    return 1 if unexpected_eof and not stopping else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="PipeWire node name or serial")
    parser.add_argument("--bars", type=int, default=24)
    parser.add_argument(
        "--internal-mode",
        choices=(INTERNAL_SUPERVISE, INTERNAL_RECORD),
        help=argparse.SUPPRESS,
    )
    parser.add_argument("--expected-parent", type=int, default=0, help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not 4 <= args.bars <= 96:
        print("waveform helper rejected an invalid bar count", file=sys.stderr)
        return 2

    helper_path = os.path.realpath(__file__)
    try:
        if args.internal_mode:
            if args.expected_parent <= 1:
                raise ValueError("invalid expected parent")
            if args.internal_mode == INTERNAL_RECORD:
                return exec_recorder(args.target, args.expected_parent)
            return supervise_recorder(args.target, args.expected_parent, helper_path)
        return run(args.target, args.bars, helper_path)
    except FileNotFoundError:
        print("waveform helper dependency is unavailable", file=sys.stderr)
        return 127
    except (OSError, RuntimeError, UnicodeError, ValueError):
        print("waveform helper safety check failed", file=sys.stderr)
        return 126


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""tests/lib/pty_run.py - run a command on a pseudo-terminal and answer its prompts (R1-04).

The updater asks its questions only in a terminal (from R1-05 on, a run without one changes
nothing), so the interactive cases of tests/test_update_merge.sh drive it through a real pty.
Standard library only. Run it isolated:

  python3 -I tests/lib/pty_run.py [--cwd DIR] [--timeout SECONDS] [--log FILE]
                                  [--expect REGEX (--send TEXT | --eof)]... -- COMMAND [ARG...]

Each --expect/--send pair waits until the output written since the previous answer matches
REGEX (Python re.search, MULTILINE, over the bytes read as Latin-1), then types TEXT and Enter.
--eof instead of --send types Ctrl-D: the next read of the command sees the end of input.
After the last pair it reads until the command closes the terminal. The transcript, with ANSI
escapes removed and CR LF turned into LF, goes to --log (else stdout). The command runs with
TERM=dumb, so it prints no colour codes.

Exit: the command's exit status (128+N when signal N ended it); 124 the timeout passed or the
command ended while an --expect still waited (the transcript names it); 125 usage; 126 no pty
on this platform (Windows).
"""
import os
import re
import select
import signal
import sys
import time

USAGE = ("usage: python3 -I tests/lib/pty_run.py [--cwd DIR] [--timeout SECONDS] [--log FILE] "
         "[--expect REGEX (--send TEXT | --eof)]... -- COMMAND [ARG...]")
ANSI = re.compile(rb"\x1b(\[[0-9;?]*[ -/]*[@-~]|\][^\x07]*\x07|[()][A-Za-z0-9]|[=>])")


def parse(argv):
    """Return (cwd, timeout, log, pairs, command) or raise ValueError."""
    cwd, timeout, log, pairs, pending = None, 120.0, None, [], None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--":
            command = argv[i + 1:]
            if not command:
                raise ValueError("no command after --")
            if pending is not None:
                raise ValueError("--expect %r has no --send" % pending)
            return cwd, timeout, log, pairs, command
        if arg == "--eof":
            if pending is None:
                raise ValueError("--eof has no --expect before it")
            pairs.append((re.compile(pending.encode("latin-1"), re.M), None))
            pending = None
            i += 1
            continue
        if i + 1 >= len(argv):
            raise ValueError("%s needs a value" % arg)
        value = argv[i + 1]
        if arg == "--cwd":
            cwd = value
        elif arg == "--timeout":
            timeout = float(value)
        elif arg == "--log":
            log = value
        elif arg == "--expect":
            if pending is not None:
                raise ValueError("--expect %r has no --send" % pending)
            pending = value
        elif arg == "--send":
            if pending is None:
                raise ValueError("--send %r has no --expect before it" % value)
            pairs.append((re.compile(pending.encode("latin-1"), re.M), value))
            pending = None
        else:
            raise ValueError("unknown argument %r" % arg)
        i += 2
    raise ValueError("no -- before the command")


def main(argv):
    try:
        cwd, timeout, log, pairs, command = parse(argv)
    except (ValueError, re.error, UnicodeEncodeError) as exc:
        sys.stderr.write("pty_run: %s\n%s\n" % (exc, USAGE))
        return 125
    try:
        import pty
    except ImportError:
        sys.stderr.write("pty_run: no pty on this platform\n")
        return 126

    pid, fd = pty.fork()
    if pid == 0:  # the child: the terminal is its stdin, stdout and stderr
        try:
            if cwd:
                os.chdir(cwd)
            os.environ["TERM"] = "dumb"
            os.execvp(command[0], command)
        except OSError as exc:
            os.write(2, ("pty_run: cannot run %s: %s\n" % (command[0], exc)).encode())
        os._exit(127)

    transcript = bytearray()
    since = 0          # where the next --expect starts looking
    note = ""
    deadline = time.monotonic() + timeout
    while True:
        left = deadline - time.monotonic()
        if left <= 0:
            note = "pty_run: timed out after %ss" % timeout
            if pairs:
                note += " waiting for %r" % pairs[0][0].pattern.decode("latin-1")
            os.kill(pid, signal.SIGKILL)
            break
        ready, _, _ = select.select([fd], [], [], min(left, 0.2))
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:   # EIO: the command closed the terminal
                data = b""
            if not data:
                break
            transcript += data
        while pairs:
            match = pairs[0][0].search(bytes(transcript[since:]))
            if not match:
                break
            since += match.end()
            if pairs[0][1] is None:
                os.write(fd, b"\x04")         # Ctrl-D at the start of a line: end of input
            else:
                os.write(fd, (pairs[0][1] + "\n").encode())
            pairs.pop(0)
    os.close(fd)
    _, status = os.waitpid(pid, 0)
    if os.WIFEXITED(status):
        code = os.WEXITSTATUS(status)
    elif os.WIFSIGNALED(status):
        code = 128 + os.WTERMSIG(status)
    else:
        code = 1
    if pairs and not note:
        note = "pty_run: the command ended while waiting for %r" % pairs[0][0].pattern.decode("latin-1")
    if note:
        code = 124

    text = ANSI.sub(b"", bytes(transcript)).replace(b"\r\n", b"\n").decode("utf-8", "replace")
    if note:
        text += "\n" + note + "\n"
    if log:
        with open(log, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

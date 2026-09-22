#!/usr/bin/env python3
"""Put the time in front of every line, and say how long since the last one.

A receiver log without times cannot be read back against what somebody did. The
gap matters as much as the clock: the operator pauses between steps, so a line
that arrives several seconds after the one before it is the start of the next
step, and everything until the next gap belongs to that one.

Reads standard input and writes standard output, a line at a time and without
buffering, so the time on a line is when it happened rather than when the buffer
happened to flush.

`readline` rather than iterating over the stream, because the iterator reads
ahead by a block and holds every line until that block is full. Against a
receiver that writes a dozen lines and then waits for somebody to press a
button, that is the whole log sitting in a buffer with nothing to read.
"""

import sys
import time


def main() -> None:
    previous = None

    while True:
        line = sys.stdin.readline()
        if not line:
            return

        now = time.time()
        gap = 0.0 if previous is None else now - previous
        previous = now

        stamp = time.strftime("%H:%M:%S", time.localtime(now))
        sys.stdout.write(f"{stamp} +{gap:6.2f}  {line}")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

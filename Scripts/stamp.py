#!/usr/bin/env python3
"""Put the time in front of every line, and say how long since the last one.

A receiver log without times cannot be read back against what somebody did. The
gap matters as much as the clock: the operator pauses between steps, so a line
that arrives several seconds after the one before it is the start of the next
step, and everything until the next gap belongs to that one.

Reads standard input and writes standard output, a line at a time and without
buffering, so the time on a line is when it happened rather than when the buffer
happened to flush.
"""

import sys
import time


def main() -> None:
    previous = None

    for line in sys.stdin:
        now = time.time()
        gap = 0.0 if previous is None else now - previous
        previous = now

        stamp = time.strftime("%H:%M:%S", time.localtime(now))
        sys.stdout.write(f"{stamp} +{gap:6.2f}  {line}")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

# What is kept here

Raw material behind the findings in `../test-log.md`.

## `airplay2-receiver-local.patch`

Applies to `openairplay/airplay2-receiver` at commit `6c343d3`. It carries every correction the measurements here needed, and each one exists because a run failed without it:

1. `do_SETRATEANCHORTIME` caught an error and then formatted a name that was never bound, so a `NameError` escaped and took the connection with it. See F-063.
2. Every reply was sent as `RTSP/1.0`, including the answer to a plain HTTP `GET /info`. The reply now speaks whichever protocol was asked in. See F-079.
3. Handlers echoed `CSeq` back even when the request carried none, producing a header reading `None`. An absent value now sends no header at all. See F-079.
4. `/info` ignored the `?txtAirPlay&txtRAOP` a macOS sender asks with, and the receiver's own description named no audio formats. It now answers both service records, built from the one set of properties it keeps, and names what it supports. See F-070 and F-072.

Apply it with `git apply` inside a fresh clone.

## `session-setup-ptp-research.md`

What the published record says a receiver must answer to the session level SETUP under PTP timing, gathered whilst F-077 was open.

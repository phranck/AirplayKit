# Ubuntu 26.04 receiver validation, 2026-09-25

## Subject

The published `v0.1.0` tag at `17f1cb61db84e337bec2282ae21fd76de721a881` was checked in a clean Ubuntu 26.04 aarch64 VirtualBuddy guest. The guest used the official Swift 6.4.0 Ubuntu 26.04 toolchain. This is separate from the Swift 6.2.4 Linux CI run. The release checkout was not edited; the discovery fix was developed in a separate clone of the renamed package at `0521f5b`.

## Build and tests

- `swiftly` 1.1.2 refused initialization with `Unsupported Linux platform` on this guest. The Swift 6.4.0 release tarball from swift.org was extracted locally; `swift --version` reported `aarch64-unknown-linux-gnu`.
- The first `swift build --jobs 2` could not link the package manifest because the clean guest lacked `crtbeginS.o`, `-lgcc` and `-lgcc_s`. After installing `build-essential`, the same build completed with exit code 0.
- `swift test --jobs 2` completed 170 XCTest cases with zero failures and exit code 0. The tests that write files use unique temporary directories and remove only their own directories.

## Shared-network probe

- `avahi-daemon` was active. `Demo list` exited successfully after its five-second browse but reported no receiver. The guest had `192.168.64.7/24` behind VirtualBuddy's shared network; the Mac's active LAN interface had `10.0.0.193`. This observation alone did not distinguish a discovery implementation problem from multicast not crossing the VM network boundary.
- The guest could ping the authorized receiver Büro at `10.0.0.125`. `Demo pair 10.0.0.125 7000` completed encrypted pairing, `/info`, the event channel and buffered stream setup, then failed to open PTP UDP port 319. A separate unprivileged Python socket bind to port 319 returned `EACCES`; `net.ipv4.ip_unprivileged_port_start` was 1024, and `ss` showed no listener on ports 319 or 320. The port permission is therefore a confirmed local blocker.
- `sudo setcap cap_net_bind_service=+ep .build/debug/Demo` granted that one executable the required bind capability. A second `Demo pair` then reached accepted `SETPEERS`, but received no PTP clock announcement within its 12-second wait. `Demo play` ended during session setup. Audio was not established on the shared network.

## Bridged-network playback

- After changing VirtualBuddy to bridged networking, the guest received `10.0.0.143` on the Mac's LAN. With the bind capability still on the release Demo, `Demo pair` with Büro received a PTP clock announcement and accepted the audio anchor. This establishes the bridged route worked; it does not by itself prove why the shared-network route failed.
- A 12-second, stereo 44.1 kHz, 16-bit WAVE test at 50% receiver volume played through the release Demo's `wave` command to Büro. The command exited successfully, and the listener reported hearing it. The temporary WAVE file was removed after the test. This establishes audible playback to one receiver, not synchronization or group playback on Linux.

## Discovery defect and verification

- On the bridged guest, Avahi's D-Bus browser saw eight `_airplay._tcp` services. Before the fix, `Demo list` from the released checkout and from the renamed package at `0521f5b` both returned no receivers. This ruled out the shared-network boundary as the only cause of empty discovery.
- A direct `DNSServiceResolve` probe for Büro showed that Avahi's DNS-SD compatibility layer can require three `DNSServiceProcessResult` calls before invoking the resolve callback. The package called it once per browse result and immediately deallocated the resolver. This discarded incomplete resolutions before `onResolved` could announce a receiver.
- The fix keeps processing a resolver until its callback arrives, discovery stops, or the existing two-second deadline expires. It retains the wake pipe, so stopping still interrupts a pending resolve. In the same bridged guest after `swift build --jobs 2`, `Demo list` reported seven receivers, including Büro, Esszimmer and Emma. `swift test --jobs 2 --filter DiscoveryStoppingTests` passed three tests.
- Avahi saw one additional service that the Demo did not list. This probe does not establish why that service was absent from the Demo result; no claim of complete discovery coverage follows from the seven listed receivers.

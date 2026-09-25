# C and Objective-C API

Use the `CAirplayKit` product and include `AirplayKit.h`. The header defines the signatures, ownership rules and parameter contracts. This page lists every public C entry point and the objects they use.

## Discovery

`PAReceiver` holds a receiver's stable ID, speaker name, host, port, model, manufacturer, published group ID and reported capabilities and playback state. `PADiscovery` is an opaque browse handle. `PADiscoveryHandler` receives the full current receiver array, valid only during the callback. `PADiscoveryProblem` describes why browsing could not continue.

- `pa_discovery_start`: Start browsing and receive changes through a `PADiscoveryHandler`.
- `pa_discovery_stop`: Stop browsing and release the handle.
- `pa_discovery_problem`: Read the current browse problem.
- `pa_discovery_problem_for_error`: Classify an mDNS responder error.

## Device names and symbols

These functions write UTF-8 into a caller-owned buffer and return the complete byte count, excluding the terminator. Pass `NULL` for the output buffer to measure the required capacity.

- `pa_product_name`: Resolve a manufacturer's model or an Apple model identifier to a product name.
- `pa_resolve_product_name`: Asynchronously read the receiver's root UPnP `modelName` where available, then AirPlay `/info`, and fall back to `pa_product_name`. Its `PAProductNameHandler` runs once on a background thread; copy the borrowed name before returning.
- `pa_symbol_name`: Choose a symbol for a device.
- `pa_pair_symbol_name`: Choose a symbol for a known pair.

## Playback and volume

`PASession` is an opaque connection to one receiver. `PAResult` reports opening failures. Audio is interleaved signed 16-bit stereo at `PA_SAMPLE_RATE` (44100 Hz). `PASessionReport` retains the final underrun counters when the session closes.

- `pa_session_open`: Pair and open a session.
- `pa_session_open_with_volume_memory`: Pair and open with volume restoration keyed by stable `PAReceiver.id`.
- `pa_session_write`: Queue audio frames without blocking.
- `pa_session_is_running`: Distinguish a full buffer from an ended session.
- `pa_session_discard_held_audio`: Drop audio that has not yet been sent.
- `pa_session_held_frames`: Read the queued frame count.
- `pa_session_set_volume`: Set the receiver's own level.
- `pa_session_get_volume`: Read the last known receiver level, if available.
- `pa_session_set_volume_handler`: Receive volume changes through a `PAVolumeHandler` while the session is open.
- `pa_session_set_event_handler`: Receive receiver-pushed requests through a `PAEventHandler`.
- `pa_session_close`: Close and release the session, optionally returning a `PASessionReport`.

## Groups

`PAGroup` is an opaque group handle. Its members use one PTP clock and media timeline. Each member is identified by the stable ID supplied by discovery. A group has its own bounded audio buffer and accepts the same PCM format as a session. `PAGroupChange` names creation, joining, leaving, connection loss, dissolution and unexpected group ending; `PAGroupMembershipHandler` receives those changes. `PAGroupVolumeHandler` receives each member's changed level, and `PAGroupEventHandler` receives the original receiver-pushed request and member ID.

- `pa_group_open`: Open a group from matching ID, host and port arrays with one or more receivers.
- `pa_group_open_with_volume_memory`: Open a group with per-member volume restoration before playback.
- `pa_group_add`: Add a receiver to a running group.
- `pa_group_remove`: Remove a receiver from a running group.
- `pa_group_member_count`: Read the current membership size.
- `pa_group_member_id`: Copy a member's stable ID to a caller-owned UTF-8 buffer.
- `pa_group_write`: Queue interleaved signed 16-bit stereo frames.
- `pa_group_is_running`: Check whether the group still accepts audio.
- `pa_group_held_frames`: Read the number of frames waiting in the group buffer.
- `pa_group_discard_held_audio`: Drop frames still buffered for the group when the audio source changes.
- `pa_group_get_volume`: Read one member's last known level.
- `pa_group_set_volume`: Set one member's own level.
- `pa_group_set_volume_all`: Set every current member's own level.
- `pa_group_get_average_volume`: Read the mean member level when every level is known.
- `pa_group_set_average_volume`: Move the mean member level while preserving differences until a member reaches its limit.
- `pa_group_set_membership_handler`: Receive membership changes, starting with the current set.
- `pa_group_set_volume_handler`: Receive changed member levels.
- `pa_group_set_event_handler`: Receive receiver-pushed requests with their member ID.
- `pa_group_dissolve`: Stop playback and emit a dissolution event while retaining the handle.
- `pa_group_close`: Stop playback and release the handle.

Group membership callbacks describe operations through this handle. They do not report groups created by another AirPlay controller. Volume callbacks can report changes made at a receiver while it is connected. The return codes of operations that can fail are `PAResult` values. `pa_group_write` returns a boolean, so check `pa_group_is_running` to distinguish a full buffer from a stopped group.

## Optional volume memory

`PAVolumeMemory` is an application-owned opaque JSON store. Its file path belongs to the application. A corrupt or unreadable existing file is rejected without replacement. Open sessions and groups retain the store after the caller releases its handle. When enabled, confirmed volume changes are stored by stable receiver ID and restored on reconnect or group join before audio starts. Changes made while disconnected may be overwritten. Disabling stops writes and restores but keeps the saved file.

- `pa_volume_memory_open`: Open the store at an application-chosen path.
- `pa_volume_memory_set_enabled`: Enable or disable it for existing and future connections.
- `pa_volume_memory_is_enabled`: Read the current setting.
- `pa_volume_memory_last_error`: Copy the latest persistence write error to a caller-owned UTF-8 buffer.
- `pa_volume_memory_close`: Release the caller's handle.

## Session diagnostics

- `pa_session_invented_packets`: Count silence packets sent when the source had no audio ready.
- `pa_session_invented_seconds`: Read that count as audio duration.
- `pa_session_fell_behind`: Count timeline slips beyond the anchor's lead.
- `pa_session_waited_seconds`: Read the cumulative wait for source audio.
- `pa_result_description`: Describe a `PAResult` in English. Pairing refusals include a conditional hint for HomePod users to check **Home Settings > Speakers & TV** in the Home app.

> Important: `pa_session_close` releases the `PASession`. Read diagnostics before closing or use the returned `PASessionReport` afterwards.

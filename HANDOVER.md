# Handover

For whoever picks this up next. Written on 2026-09-24 at the end of a long session, covering PlayableAirplay and the application that uses it.

Read this once, then work from the issues. **The issues are the plan**, this file is only what is not in them.

## What the library is for

[#113](https://github.com/phranck/PlayableAirplay/issues/113) states it and is the reference the work is measured against. In short: working AirPlay 2 on macOS, iOS and Linux, so that a program can find receivers, stream to one, group several and dissolve the group, set the volume of one speaker and of a group, read each speaker's model and name, and be told when any of that changes elsewhere on the network.

Two rules on that, both stated by phranck and both non-negotiable:

**AirPlay 2 only.** No manufacturer's own services, however convenient. A feature that works on one make of speaker and nowhere else is not a feature of this library. A module that spoke Sonos's own services was removed on 2026-09-24 for exactly that reason, and the reasoning is in [#120](https://github.com/phranck/PlayableAirplay/issues/120) and in the documentation page `What-AirPlay-Does-Not-Say`.

**Everything those functions need goes into the API, and nothing else does.** That is [#66](https://github.com/phranck/PlayableAirplay/issues/66), which carries the decision already: a caller sees a discovery, a receiver and a session, and the whole protocol machinery becomes internal.

## Where things stand

Both repositories are on `develop` with everything merged, and `main` carries the same tree as of this session. No open pull requests. No local branches left except one, below.

**PlayableAirplay**: 224 tests, Linux builds, the site builds and publishes from `main`, and the Objective-C caller builds. The Swift sender is complete and plays cleanly to a Sonos and a HomePod. Two independent audits were run and all seventeen resulting issues are fixed.

**Podlive**: 25 tests, and it plays to AirPlay speakers from the player row. It has a test target for the first time, `PodliveTests`, run with `Scripts/run-tests.sh`.

## What to do next, in order

1. [#114](https://github.com/phranck/PlayableAirplay/issues/114) Read the receiver's volume with `GET_PARAMETER` rather than only setting it. Small, and it fixes a visible fault: a fresh session shows the wrong number because it imposes a level instead of adopting the one the speaker is at. Apple's own sender reads it between the session SETUP and RECORD.
2. [#18](https://github.com/phranck/PlayableAirplay/issues/18) The measurement multi-room rests on: whether every member of a group is given the identical anchor, and what a leaving member is told. Needs two receivers under your own control, so it is bench work rather than typing.
3. [#15](https://github.com/phranck/PlayableAirplay/issues/15) Multi-room itself. Its first half is done; grouping is its second.
4. [#119](https://github.com/phranck/PlayableAirplay/issues/119) Read what the event channel already delivers. The package opens that channel and answers it, because a receiver ends the session otherwise, and throws the content away without looking.

[#66](https://github.com/phranck/PlayableAirplay/issues/66) can be done at any point and makes everything after it easier.

## Traps on this machine

Each of these cost time in this session.

**Three files carry `skip-worktree` in Podlive**, including `App/Podlive/Application/LWApplicationDelegate.m`, which holds a local screenshot-driving version that must never be committed. **A search and replace over the working tree does not reach any of them**, and a branch switch will refuse or destroy them. To change what is committed in such a file without touching the working copy, write the new blob with `git hash-object -w` and set it with `git update-index --cacheinfo`; that clears the flag, so set it again afterwards and check the working file's hash either side.

**Podlive builds against this package by relative path**, not by version. Every change here is live for it immediately, and a signature change in `PlayableAirplay.h` breaks it at compile time. `Scripts/check-callers.sh` is the gate that catches that and it is part of the pre-push set.

**Merges go to `develop`, not to the default branch**, so `Closes #<n>` in a commit never fires. Close every issue by hand with a comment saying what was verified.

**The GitHub API's rate limit is shared with every agent you spawn.** Two background agents running `gh pr checks --watch` exhausted GraphQL for an hour whilst `gh api rate_limit` still reported it as untouched. REST kept working throughout, so `gh api repos/.../issues/...` is the way round it. The Projects API is GraphQL only and has no way round.

**There are three project boards**: Playable is 14 and is the product plan, Podlive is 13, PlayableAirplay is 15 and was created on 2026-09-24. Each has one Kanban view, columns Backlog, Ready, In progress, In review and Done, and a Priority field P0 to P3.

**One branch is still standing**: `issue/25-linux-gate` in PlayableAirplay. Both its commits are superseded on `develop`, `git branch -d` refuses because there is no merge commit, and a hook refuses `-D`. Its SHA is `d78d048` and the reflog holds it for ninety days. Leave it or ask phranck.

## How phranck wants the work done

The rules in `~/.claude` govern, and these are the ones this session got wrong often enough to be worth repeating.

**Every claim must be provable, and the evidence must be real.** State the command that produced a figure so he can run it himself. A number is several runs and a range, not one run reported as a constant. A claim about cause names the line that settles it, or says what was not checked. Three times in this session a confident explanation turned out to be wrong, and each time one more file read or one more run would have prevented it.

**Decide, do not ask.** How something is built is yours. What the product should do is his. He has said this repeatedly and it is the thing he loses patience with fastest. Filing an issue that asks him to choose is the same delegation with a longer delay.

**Delegate to subagents, and stop them the moment they have reported and you have verified their claims.** That rule is in `rules/code-quality.md`.

**Prose**: British Oxford English, complete sentences, no em-dashes or en-dashes anywhere and no substituting a colon for one. German in chat, English in every artefact. Comments say why, in the present tense, never what changed. No effort or time estimates, ever.

**Gates before every push**: `swift build`, `swift test`, `Scripts/check-linux.sh`, `Scripts/build-site.sh`, `Scripts/check-callers.sh`. All of them, read to the end, before the commit rather than after it.

## What this session got wrong, so you do not repeat it

**I planned grouping over a manufacturer's services** because that module was to hand. It looks like an answer until you ask what a HomePod does with it. Two issues were written and closed again.

**I told him a defect was a stale build** on one observation. It was intermittent behaviour in the package, which a second run would have shown.

**I wrote "the window is two seconds" into an issue** having read the wrong function for the lifetime. It is microseconds, and the two seconds is the period during which the object is alive and a call is safe.

The pattern in all three is the same: one observation, an explanation built on it, and the explanation stated as fact. Measure twice, and say plainly what you have not checked.

## Where the knowledge lives

`Documentation/Research/test-log.md` carries every measurement with a finding number, and the `.docc` pages carry the protocol with each statement marked as measured here or reported by a source. Neither is decoration: when something does not work, the answer is usually already in one of them.

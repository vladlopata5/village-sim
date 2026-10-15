# Ordinary AI decision queue — P3.2

Canonical Main3D binds every resident DecisionController to the existing
AiDecisionDispatcher. There is one ordinary queue, including the former Porter
queue. An isolated controller without a dispatcher retains its synchronous domain
API; this is not a second canonical planner.

## Immediate operations

Pickup, delivery, reserve/release, paid meal consumption, construction completion,
intent completion, slot cleanup, assignment validation and committed-job protection
remain in their existing synchronous lifecycle. GameTime emits every minute and
phase normally. Critical hunger/fatigue retain the existing forced-intent reactions
and priorities; they do not wait for ordinary queue service. Those reactions may
still perform expensive searches synchronously. A budget is not a cap on all AI.

## Queued operations

Choosing the next ordinary action after completion, idle timeout, phase change,
work availability or ordinary food availability waits for service. Cheap eligibility
guards run at enqueue; ordinary availability/path probes run when serviced. The
phase state changes immediately, but selecting the new phase action may wait.
Night uses the existing schedule submit/pending-intent rules, including protection
of noninterruptible operations. Recovery of an already accepted sleep action and
the bool-returning prepare_for_work contract remain synchronous.

## Pending state and validation

One pending entry per resident ID holds a weak receiver, a set of request reasons,
latest context keys, maximum requested priority, original real/game enqueue time
and stable sequence. Duplicates merge reasons/context without resetting age. A new
runtime with the same ID replaces the old receiver. Cancellation, unregister and
tree exit remove entries; no pending entry owns a job or resource.

At execution the controller checks live role, workplace, assignment revision and
phase; existing world validation checks registration and committed HaulJobs. It
also checks current intent, schedule agreement, forced/player state and critical
needs. A stale context cannot claim work; an eligible fresh request waits for a
later frame. Actual selection/reservation always uses current world state.

## Priority and fairness

Service priority is separate from action utility: background availability/idle
requests use 0, normal completion/phase requests 1, hunger or fatigue >=90 promotes
ordinary service to 2. Critical thresholds remain unchanged. Aging is 250 ms per
priority level. Sort by priority*250000-enqueue_usec descending, then original
sequence. Thus an old background request outranks newly arriving urgent work
after 500 ms. Existing older higher-priority work still has to finish; this is not
a hard latency guarantee. Duplicates cannot postpone a resident forever.

## Budget and reentrancy

Default budget is 1000 microseconds (1 ms); exported range is 100..20000 us. It was
selected from 1/2/3/4 ms trials to favor frame smoothness with short measured waits.
Time.get_ticks_usec measures monotonic elapsed service time, including nested
callbacks and OS preemption, not native thread-only CPU time. At least one entry
is attempted to ensure progress. A GDScript decision is atomic and cannot be
preempted: a single expensive decision can exceed the budget substantially.

Drain at most once per process frame, with pause/reentrancy guards. Service only
the snapshot eligible at slice start. Requests emitted during a decision can
create one future pending entry, never recursive immediate draining. Invalid or
cancelled entries are skipped. There is no per-frame resident-count limit.

## Diagnostics and remaining limits

statistics() exposes pending/peak, last-slice count/time, budget, oldest pending,
merges/discards/cancellations, executions, overruns and native maximum real/game
wait. decision_serviced allows external buffered observations. Production retains
scalar aggregates only. F10 AI tab refreshes at most four times per second while
visible; the ordinary HUD is unchanged. Counters describe the last serviced slice
when paused. Setup debug time jumps must be separated from real queue latency.

The queue changes ordinary action timing and claim order intentionally. Real-wall
budget results are not deterministic across machines; fixed-service test replays
are reproducible. P1 raw route hints, P2 invalidation, P3.1 bool-only reachability,
movement smoothing, resources, GameTime, UI geometry and camera are unchanged.
Monolithic PLANT searches, construction notification fan-out, critical searches,
physics and other synchronous callbacks remain possible heavy work. Do not infer
a hard frame cap or elimination of all freezes from this change.


## P3.3 — randomized ordinary idle retry (2026-10-15)

An empty ordinary action selection starts a uniform integer idle period of 10–30
game minutes inclusive. BalanceConfig.IDLE_RETRY_MIN_MINUTES/MAX_MINUTES hold the
bounds. DecisionController._start_idle_period uses the existing resident-owned rng
(seeded by resident ID) once per new period, including empty startup. This consumes
one extra resident RNG draw intentionally; old action traces need not match.
Unrelated residents and global RNG calls do not drive this duration.

IDLE is empty current intent plus activity IDLE, not a new named action. The deadline
uses actual GameTime.total_minutes. At expiry request_decision("idle_completed")
enters the unchanged P3.2 queue. While ordinary service is pending, minute ticks do
not repeat this timer request or roll another period. After service, a genuinely
empty selection starts a fresh period. Rejected availability-only notifications
preserve the previous period rather than rerolling it at enqueue or rejection.

Accepted intents, intent changes and phase changes cancel the old deadline. After
cancellation without a completion signal, a new empty idle period may start at the
next minute tick. Critical needs, player commands, schedule/assignment and existing
food/work/resource notifications keep their current rules. No new world_changed or
work_available broadcast was added. Existing notifications can still end idle early.
Named stationary actions, handling, portal/slot waiting, paid meals, rest, sleep and
committed work cycles do not acquire this random duration. Their own timers remain.

Expected mean timer is now 20 rather than 10 game minutes. Without an existing
external notification, newly available work can be discovered up to 20 minutes later
than the former maximum; this is the agreed behavior change. This is not a claim
that idle retries explain every heavy frame. Queue budget/priority/aging, GameTime,
critical thresholds, resource lifecycle, P1/P2/P3.1, PLANT and building fan-out are
unchanged. Measurements: external performance-optimization-p3-3/REPORT.md.

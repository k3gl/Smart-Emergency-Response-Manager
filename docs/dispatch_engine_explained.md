# Dispatch Engine — Explained (study notes)

A plain-language reference for the trigger-driven dispatch engine
(PostgreSQL / Supabase). File: supabase/migrations/20260623_dispatch_queue.sql

---

## 1. The pieces of the engine (what each part is)

| Part | Type | In plain English |
|---|---|---|
| `dispatch_queue` | Table | The waiting list. When no unit is free, the incident's need (e.g. "needs 1 AMBULANCE") is parked here until a unit frees up. |
| `severity_rank()` | Function | Turns a word into a number so the DB can sort: CRITICAL=3, URGENT=2, LOW=1, FAKE=0. Higher = served first. |
| `haversine_km()` | Function | Calculates the straight-line distance between two GPS points, so the engine can find the nearest unit. |
| `request_dispatch()` | Function | The "new incident arrived" entry point. Tries to dispatch a unit now; if none free, adds it to the queue. |
| `dispatch_available_unit()` | Function | The "a unit just freed up" entry point. Pulls the most urgent waiting incident and sends the unit to it. |
| `_perform_dispatch()` | Function | The commit step. Actually writes the records: marks the unit Assigned, the incident Assigned, and links them. |
| `units_dispatch_after_available` | Trigger | The automatic wiring. Watches the units table; fires the engine the moment a unit becomes Available. |

---

## 2. The two ways dispatch starts

| Scenario | Function that runs | What happens |
|---|---|---|
| A new incident comes in needing a unit | `request_dispatch()` | Find nearest free unit of the right type. Found -> dispatch it. None free -> add to the queue, mark incident Queued. |
| A unit becomes free (finished a job) | `dispatch_available_unit()` (fired by the trigger) | Look at the queue. Pick the highest severity waiting for this unit's type, then the nearest one. Dispatch and remove it from the queue. |

---

## 3. How the queue decides "who's next"

| Priority order | Rule | Why |
|---|---|---|
| 1st | Highest severity first (CRITICAL -> URGENT -> LOW) | A life-threatening case beats a minor one, even if older. |
| 2nd | Among equal severity, the nearest incident | Faster help, lower ETA. |
| 3rd | If distances are nearly tied, the oldest waiting | Fairness — first come, first served on ties. |

---

## 4. The two "scary-sounding" technical terms, explained simply

| Term | What it literally does | Why your project needs it |
|---|---|---|
| `SECURITY DEFINER` | Makes the function run with the OWNER's permissions, not the caller's. | A Unit is only allowed to edit its own row (RLS rule). But dispatching requires editing other tables (incident_dispatches, other units). SECURITY DEFINER lets the trusted function do that safely, while the user still can't. |
| `FOR UPDATE SKIP LOCKED` | When selecting a row, it LOCKS it so no one else can take it, and if a row is already locked, it SKIPS to the next one instead of waiting. | Stops two dispatches happening at the same instant from grabbing the same unit or the same incident. No double-booking. |

---

## 5. RLS (Row-Level Security) — the bigger context

| Concept | Meaning |
|---|---|
| RLS | Database rules that decide which rows each user can see/edit. E.g. "a Citizen can only see their own incidents; only Admins can manage the queue." |
| Why it matters here | It's the security backbone — even if someone bypassed the app, the DB still blocks them. The engine uses SECURITY DEFINER to do its job without weakening these rules for normal users. |

---

## Quick flow summary (the whole story in 4 lines)

1. New incident -> `request_dispatch()` tries to send the nearest free unit; if none, it joins the `dispatch_queue`.
2. A unit finishes -> its status flips to Available -> the `units_dispatch_after_available` trigger fires.
3. The trigger runs `dispatch_available_unit()`, which takes the most urgent + nearest waiting incident from the queue.
4. `_perform_dispatch()` commits it: unit = Assigned, incident = Assigned, link row written. Locks (`FOR UPDATE SKIP LOCKED`) make sure no one is double-booked.

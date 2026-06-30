# Emergency Incident Detection & Dispatch System
## Graduation Project — Full Technical & Theoretical Documentation

> **Document status:** complete draft generated from the live source code.
> Sections marked **⚠️ VERIFY** are inferred from code usage and should be
> reconciled against the actual Supabase schema dump (see Appendix C for how to
> export it).

---

## Table of Contents

**PART I — TECHNICAL DOCUMENTATION**
1. System Overview
2. Technology Stack
3. High-Level Architecture
4. Project Structure (file-by-file)
5. Database Schema (Supabase / PostgreSQL)
6. Data Models (Dart)
7. Service Layer
8. Presentation Layer (Screens)
9. The AI / Machine-Learning Microservice
10. The Dispatch Engine & Global Queue *(today's work)*
11. Idle-Unit Return-to-Station *(today's work)*
12. Distance & ETA Model
13. Concurrency, Polling Intervals & Realtime
14. Security Model (Authentication & Row-Level Security)
15. Changelog of Today's Modifications
16. Setup, Configuration & Deployment
17. Testing & Verification Procedures

**PART II — THEORETICAL DOCUMENTATION**
1. Problem Domain & Motivation
2. Emergency Dispatch Theory
3. Priority Scheduling Theory
4. Spatial Assignment & the Haversine Model
5. Queueing Theory Foundations
6. Event-Driven Architecture & Database Triggers
7. Concurrency & Race Conditions
8. Clean Architecture & Separation of Concerns
9. Natural-Language Processing & Machine-Learning Theory
10. Scalability Analysis
11. Limitations & Future Work

**PART III — SESSION 2 ADDITIONS**
1. Duplicate Incident Detection
2. Citizen UI Refinements
3. Feedback / Rating System
4. Persistent Login (AuthGate)
5. Push Notifications (Firebase Cloud Messaging)
6. Changelog — Session 2

**APPENDICES**
- A. Glossary of Terms
- B. Full State & Status Reference
- C. How to Export the Supabase Schema
- D. End-to-End Worked Example

---
---

# PART I — TECHNICAL DOCUMENTATION

## 1. System Overview

This project is a **smart emergency-response platform** for a metropolitan area
(modelled on Cairo / Giza, Egypt). It connects three classes of users —
**Citizens**, **Response Units**, and **Administrators** — around a single goal:
when a citizen reports an emergency, the system must **understand** the report,
**classify** it, and **dispatch the most appropriate response unit as quickly as
possible**, while gracefully handling the case where every suitable unit is
already busy.

The platform is composed of three cooperating subsystems:

1. **A Flutter mobile/desktop application** — the user-facing client for all
   three roles (citizen reporting, unit operations, admin management).
2. **A Supabase backend** (PostgreSQL + Auth + Storage + Realtime) — the single
   source of truth for all data, security, and — as of today's work — the
   **dispatch decision logic itself** (queue, matching, priority).
3. **A Python AI microservice** (`emergency_ai/`) — an always-on worker that
   transcribes voice reports (OpenAI Whisper), detects fake reports, classifies
   **severity**, and determines **which unit types** are required, then asks the
   database to dispatch them.

The four physical stations modelled in the system are:
**Masr El Gedida, Madinat Nasr, Al Haram, and Sheikh Zayed.** Each station owns
multiple **units**, and each unit has a type (`POLICE`, `AMBULANCE`, `FIRE`), a
live location, and an operational status.

### 1.1 The core idea in one sentence
> A citizen presses **SOS** → the AI reads/listens and decides *what* is needed →
> the database finds the *nearest free unit of each needed type* and dispatches
> it, or **queues** the request if none is free → the moment a unit frees up, the
> database **automatically** pulls the highest-priority waiting incident and
> sends that unit to it.

---

## 2. Technology Stack

| Layer | Technology | Version (from `pubspec.yaml` / code) | Role |
|---|---|---|---|
| Client framework | **Flutter** (Dart) | SDK `^3.10.4` | Cross-platform UI (Android, iOS, Web, Windows, macOS, Linux) |
| Backend-as-a-Service | **Supabase** | `supabase_flutter ^2.8.1` | PostgreSQL DB, Auth, Storage, Realtime |
| Database | **PostgreSQL** | (Supabase-managed) | Relational store + dispatch engine (PL/pgSQL) |
| Maps | **Google Maps** | `google_maps_flutter ^2.5.3` | Incident & route visualization |
| Geolocation | **Geolocator** | `geolocator ^11.0.0` | Device GPS for citizens & units |
| Audio capture | **record** | `record ^6.2.0` | Citizen voice SOS recording |
| File system | **path_provider** | `^2.1.2` | Temp audio file storage |
| Permissions | **permission_handler** | `^11.3.0` | Runtime location/mic permissions |
| HTTP | **http** | `^1.2.1` | Misc network calls |
| Push notifications | **Firebase Cloud Messaging** | `firebase_core`, `firebase_messaging` | Push to citizens/units *(today)* |
| Notification sender | **Supabase Edge Function** (Deno/TypeScript) + **Database Webhooks** | — | Server-side FCM dispatch *(today)* |
| Duplicate detection | **geopy** + Sentence-Transformers cosine similarity | — | De-duplicate nearby/similar reports *(today)* |
| AI worker runtime | **Python 3.10 / 3.13** | — | Background processing service |
| Speech-to-text | **OpenAI Whisper** (`base` model) | — | Voice → text transcription |
| Sentence embeddings | **Sentence-Transformers** `all-mpnet-base-v2` | — | Text → 768-dim semantic vectors |
| Classical ML | **scikit-learn** (LogisticRegression, TF-IDF, MultiOutputClassifier) | — | Severity, unit-type & fake classification |
| Model persistence | **joblib** (`.pkl`) | — | Saved trained models |
| Scheduled jobs | **pg_cron** (Postgres extension) | — | Periodic idle-unit reset *(today's work)* |

---

## 3. High-Level Architecture

```
        ┌──────────────────────────────────────────────────────────────┐
        │                        FLUTTER CLIENT                          │
        │                                                                │
        │   Citizen UI        Unit UI            Admin UI                │
        │   (SOS, voice,      (assignment,       (stations, units,       │
        │    live tracking)    status, report)    live queue, override)  │
        └───────┬───────────────────┬───────────────────┬───────────────┘
                │  insert/read       │ status/location   │ manage/read
                ▼                    ▼                    ▼
        ┌──────────────────────────────────────────────────────────────┐
        │                  SUPABASE  (single source of truth)            │
        │                                                                │
        │   Auth (auth.users)     Storage (voice_incidents bucket)       │
        │                                                                │
        │   PostgreSQL                                                   │
        │   ├── Tables: profiles, stations, units, incidents,            │
        │   │           incident_dispatches, incident_reports,           │
        │   │           dispatch_queue  ◄── (today)                      │
        │   ├── RLS policies (per-role access control)                   │
        │   ├── Functions: severity_rank, haversine_km,                  │
        │   │              request_dispatch, dispatch_available_unit,    │
        │   │              _perform_dispatch, return_idle_units...       │
        │   ├── Triggers: units_auto_resolve,                            │
        │   │             units_dispatch_after_available  ◄── (today)    │
        │   │             units_track_available_since      ◄── (today)   │
        │   └── pg_cron job: return-idle-units             ◄── (today)   │
        └───────▲────────────────────────────────────────────▲──────────┘
                │ polls status='Processing'                   │ rpc('request_dispatch')
                │ writes severity / type                      │
        ┌───────┴────────────────────────────────────────────┴──────────┐
        │                   PYTHON AI MICROSERVICE                        │
        │   Whisper (STT) → fake detector → severity → unit-type models   │
        │   then calls request_dispatch() per required unit type          │
        └────────────────────────────────────────────────────────────────┘
```

**Key architectural decision (made today):** the *dispatch decision* — which unit
serves which incident, in what priority order — was moved **out of** the Python
worker and **into** the database. This gives a single, race-free source of truth
shared by the worker and the app. See §10.

---

## 4. Project Structure (file-by-file)

```
gp/
├── lib/                              # Flutter application source
│   ├── main.dart                     # Entry: Firebase+Supabase init, AuthGate, FCM wiring
│   ├── models/                       # Plain data classes (entities)
│   │   ├── user_model.dart           # UserModel (Citizen/Admin profile)
│   │   ├── station_model.dart        # Station
│   │   ├── unit_model.dart           # Unit (response vehicle/team)
│   │   ├── incident_model.dart       # Incident  (+ severity)
│   │   └── dispatch_queue_entry.dart # DispatchQueueEntry
│   ├── services/                     # Business/data-access layer
│   │   ├── auth_service.dart         # Sign-up, login, role routing
│   │   ├── dispatch_service.dart     # All dispatch/units/queue operations
│   │   ├── feedback_service.dart     # Ratings: submit + unrated lookup (NEW today)
│   │   └── notification_service.dart # FCM token register/handlers (NEW today)
│   └── screens/                      # Presentation layer (UI)
│       ├── auth/
│       │   ├── auth_gate.dart           # Persistent-login router (NEW today)
│       │   ├── login_screen.dart
│       │   └── register_screen.dart
│       ├── citizen/
│       │   ├── citizen_dashboard.dart   # SOS + live tracking + feedback prompt
│       │   └── incident_rating_sheet.dart # 1–5 star + comment sheet (NEW today)
│       ├── unit/
│       │   ├── unit_dashboard.dart     # Assignment + status + GPS loop
│       │   └── incident_report_screen.dart  # Post-incident report + resolve
│       └── admin/
│           ├── admin_dashboard.dart    # Overview + live queue
│           ├── stations_screen.dart    # Stations + their units
│           ├── units_screen.dart       # Unit CRUD + account provisioning
│           └── incident_detail_screen.dart  # Map, dispatched units, override
│
├── supabase/
│   ├── migrations/
│   │   ├── 20260617_unit_accounts.sql          # Units-as-accounts refactor
│   │   ├── 20260617_citizen_active_response.sql# Citizen read policies
│   │   ├── 20260623_dispatch_queue.sql         # Queue + dispatch engine
│   │   ├── 20260623_unit_idle_return.sql       # Idle → station reset
│   │   ├── 20260624_incident_feedback.sql      # Feedback table + RLS (NEW today)
│   │   └── 20260624_device_tokens.sql          # FCM tokens + RPCs (NEW today)
│   └── functions/
│       └── send-notification/
│           └── index.ts                        # Edge Function: FCM sender (NEW today)
│
├── android/app/google-services.json # Firebase config (NEW today)
│
├── emergency_ai/                     # Python AI microservice
│   ├── app.py                        # Worker: poll → STT → AI → duplicate check → dispatch RPC
│   ├── emergency_response_manager.py # Model loading + predict_incident()
│   └── models/                       # Trained .pkl models
│       ├── fake_detector.pkl
│       ├── severity_model.pkl
│       ├── severity_vectorizor.pkl
│       ├── amb_model.pkl
│       ├── fire_model.pkl
│       └── pol_model.pkl
│
├── train_and_test.py                 # ML training script (offline)
├── gp_update.ipynb                   # ML experimentation notebook
├── pubspec.yaml                      # Flutter dependencies
└── docs/
    └── GP_Documentation.md           # ← this document
```

---

## 5. Database Schema (Supabase / PostgreSQL)

> **✓ Verified** against the live `information_schema` dump. Column names,
> types, nullability and defaults below are authoritative.

### 5.1 Entity-Relationship overview

```
auth.users (Supabase Auth)
    │ 1                         │ 1
    │                           │
    ▼ 1                         ▼ 0..1
profiles                      units ───────────┐ station_id (N..1)
(Citizen / Admin)               │              ▼
                                │            stations
                                │ current_incident_id (0..1)
                                ▼
incidents ◄──────── incident_dispatches ───────► units   (N..N junction)
    │ 1                                            
    ├──► incident_reports (1..N)                   
    └──► dispatch_queue   (1..N demands)   ◄── NEW today
```

### 5.2 `profiles`
Holds Citizen and Admin identities (Units were removed from here in the
`20260617_unit_accounts` migration).

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | equals `auth.users.id` |
| `name` | `text` | display name |
| `email` | `text` | login email |
| `role` | `text` | `'Citizen'` or `'Admin'` |
| `emergency_contact_name` | `text` nullable | citizen only |
| `emergency_contact_phone` | `text` nullable | citizen only |
| `location_enabled` | `boolean` | consent flag |

### 5.3 `stations`
The four physical response stations.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | `gen_random_uuid()` |
| `name` | `text` NOT NULL | e.g. "Madinat Nasr" |
| `address` | `text` nullable | |
| `latitude` | `double precision` NOT NULL | station location |
| `longitude` | `double precision` NOT NULL | station location |
| `created_at` | `timestamptz` | default `now()` |

### 5.4 `units`
A response vehicle/team. Account-backed (each unit can log in).

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `auth_user_id` | `uuid` FK → `auth.users` | nullable until provisioned |
| `station_id` | `uuid` FK → `stations` | home base |
| `unit_code` | `text` | e.g. "POL-009" |
| `name` | `text` | e.g. "Officer Adel" |
| `email` | `text` unique (lower) | login id |
| `unit_type` | `text` | `POLICE` \| `AMBULANCE` \| `FIRE` |
| `status` | `text` | see §B; CHECK constraint enforces the 6 values |
| `current_incident_id` | `uuid` FK → `incidents` | nullable; set on dispatch |
| `current_latitude` | `double precision` | last reported GPS |
| `current_longitude` | `double precision` | last reported GPS |
| `last_location_at` | `timestamptz` | when GPS was last pushed |
| `is_active` | `boolean` NOT NULL default `true` | disabled units never dispatched |
| `available_since` | `timestamptz` nullable | idle clock *(Session 1)* |
| `created_at` | `timestamptz` | default `now()` |

> `units.status` defaults to `'Available'` and is NOT NULL.

### 5.5 `incidents`
A reported emergency.

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | `uuid` PK | NO | `gen_random_uuid()` | |
| `reporter_id` | `uuid` | YES | | the citizen (→ `auth.users`) |
| `latitude` | `double precision` | YES | | incident location |
| `longitude` | `double precision` | YES | | incident location |
| `description` | `text` | YES | | typed text and/or Whisper transcript |
| `voice_url` | `text` | YES | | public URL of the voice clip |
| `severity` | `text` | YES | | `LOW` \| `URGENT` \| `CRITICAL` \| `FAKE` |
| `incident_type` | `text` | YES | | AI dispatch summary, e.g. "FIRE, AMBULANCE" |
| `status` | `text` | YES | `'Processing'` | `Processing` → `Pending`/`Queued` → `Assigned` → `Resolved` |
| `created_at` | `timestamptz` | YES | `now()` | report time |
| `case_id` | `text` | YES | | groups a master + its duplicates *(Session 2)* |
| `has_duplicate` | `boolean` | NO | `false` | linked as a duplicate of another *(Session 2)* |
| `assigned_at` | `timestamptz` | YES | | first dispatch time |
| `resolved_at` | `timestamptz` | YES | | closure time |
| `eta_minutes` | `integer` | YES | | primary unit ETA |
| `distance_km` | `double precision` | YES | | primary unit distance |
| `assigned_unit_id` | `uuid` | YES | | the primary (first-arriving) unit (→ `units`) |

> **Correction (verified):** there is **no `type` column** and **no `address`
> column** on `incidents` — only `incident_type`. The Dart `Incident` model has
> `type` and `address` fields, but they read keys that don't exist in the table,
> so they are always empty strings. (Harmless, but worth cleaning up: drop those
> two fields from the model, or add the columns if an address is ever needed —
> the citizen SOS flow currently does not store a reverse-geocoded address.)

### 5.6 `incident_dispatches` (junction table)
One row per (incident, unit) dispatch. Supports **multi-unit** response (e.g. a
crash needs POLICE + AMBULANCE).

| Column | Type | Null | Notes |
|---|---|---|---|
| `id` | `uuid` PK | NO | `gen_random_uuid()` |
| `incident_id` | `uuid` → `incidents` | YES | |
| `unit_id` | `uuid` → `units` | YES | |
| `distance_km` | `double precision` | YES | computed at dispatch |
| `eta_minutes` | `integer` | YES | computed at dispatch |
| `dispatched_at` | `timestamptz` | YES | default `now()` (note: **`dispatched_at`**, not `created_at`) |

### 5.7 `incident_reports`
Post-incident report written by the responding unit.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `incident_id` | `uuid` FK | |
| `reporter_id` | `uuid` | the unit's auth user |
| `incident_type` | `text` | Fire/Medical/Crime/Other |
| `actions_taken` | `text` | free text |
| `outcome` | `text` | free text |
| `created_at` | `timestamptz` | |

### 5.8 `dispatch_queue` — **NEW (today)**
The single global queue of **unmet dispatch demands**. See §10 for full detail.

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK default `gen_random_uuid()` | |
| `incident_id` | `uuid` FK → `incidents` ON DELETE CASCADE | |
| `required_unit_type` | `text` CHECK in (POLICE, AMBULANCE, FIRE) | the unmet need |
| `severity_rank` | `integer` | 3=Critical, 2=Urgent, 1=Low (denormalized) |
| `enqueued_at` | `timestamptz` default `now()` | for the "oldest first" tiebreak |
| **Unique** | `(incident_id, required_unit_type)` | idempotent enqueue |
| **Index** | `(required_unit_type, severity_rank DESC, enqueued_at ASC)` | the priority index |

### 5.8b `dashboard_incidents` (reporting view)
A read-only **view** (all columns nullable, no defaults — the signature of a
view) exposing a reporting slice of incidents: `id, incident_date, created_at,
severity, status, incident_type, eta_minutes`. Used for analytics/dashboards;
not written to by the app.

### 5.9 Functions (PL/pgSQL)

| Function | Added | Purpose |
|---|---|---|
| `unit_status_after_resolve()` | 20260617 | On a unit reaching a terminal status, close its incident and free sibling units |
| `severity_rank(text) → int` | **today** | Map severity label to a numeric priority |
| `haversine_km(lat1,lng1,lat2,lng2) → double` | **today** | Great-circle distance in SQL |
| `_perform_dispatch(unit, incident)` | **today** | Commit a dispatch (write rows, flip statuses) |
| `request_dispatch(incident, type) → bool` | **today** | Incident-driven: dispatch nearest free unit, else enqueue |
| `dispatch_available_unit(unit) → bool` | **today** | Unit-driven: pull highest-priority queued incident |
| `units_dispatch_on_available()` | **today** | Trigger fn: run engine when a unit becomes Available |
| `units_track_available_since()` | **today** | Trigger fn: maintain the `available_since` idle clock |
| `return_idle_units_to_station() → int` | **today** | Reset long-idle units' location to their station |
| `register_device_token(token, platform)` | **Session 2** | Claim an FCM token for `auth.uid()` (replaces prior owner) |
| `unregister_device_token(token)` | **Session 2** | Remove an FCM token on logout |

> **Session 2 tables** (full detail in Part III): **`incident_feedback`**
> (1–5 rating + comment per incident, §III.3) and **`device_tokens`** (FCM
> device tokens per user, §III.5).

### 5.10 Triggers

| Trigger | Timing | Table | Fires |
|---|---|---|---|
| `units_auto_resolve` | BEFORE UPDATE OF status | `units` | `unit_status_after_resolve()` |
| `units_dispatch_after_available` | AFTER INSERT/UPDATE OF status | `units` | `units_dispatch_on_available()` **(today)** |
| `units_track_available_since` | BEFORE INSERT/UPDATE OF status | `units` | `units_track_available_since()` **(today)** |

### 5.11 Scheduled jobs (pg_cron)

| Job | Schedule | Calls |
|---|---|---|
| `return-idle-units` | `* * * * *` (every minute) | `return_idle_units_to_station()` **(today)** |

---

## 6. Data Models (Dart)

The `lib/models/` classes are **plain entities**: immutable data holders with a
`fromMap` factory (deserialize Supabase JSON) and sometimes a `toMap`
(serialize). They contain **no business logic** — that lives in services and the
database. This is a deliberate separation-of-concerns choice (see Part II §8).

### 6.1 `UserModel` (`user_model.dart`)
Fields: `uid, name, email, role, emergencyContactName?, emergencyContactPhone?,
locationEnabled`. Role is `'Admin'` or `'Citizen'`. Includes both `toMap()` and
`fromMap()`.

### 6.2 `Station` (`station_model.dart`)
Fields: `id, name, address?, latitude, longitude`. `fromMap` coerces lat/lng via
`(num).toDouble()`.

### 6.3 `Unit` (`unit_model.dart`)
Fields: `id, authUserId?, stationId?, unitCode, name, email, unitType, status,
currentIncidentId?, currentLatitude?, currentLongitude?, lastLocationAt?,
isActive, stationName?`. The `stationName` is populated from a joined
`stations(name, …)` sub-select when present.

### 6.4 `Incident` (`incident_model.dart`)
Fields: `id, reporterId, type, description, voiceUrl?, latitude, longitude,
address, status, severity?, assignedUnitId?, timestamp`.
- Added the `severity` field (read from `data['severity']`) so the UI can
  rank/colour incidents.
- `timestamp` is parsed from `created_at`.
- **Verified gotcha:** the `type` and `address` fields read DB keys that **do
  not exist** on the `incidents` table (only `incident_type` exists; no address
  is stored). They therefore always resolve to empty strings — harmless, but
  candidates for cleanup.

### 6.5 `DispatchQueueEntry` (`dispatch_queue_entry.dart`) — **NEW today**
A read-model for one row of the global queue, used by the admin queue view.
Fields: `id, incidentId, requiredUnitType, severityRank, enqueuedAt,
incident?`. The optional `incident` is a nested `Incident` parsed from a joined
`incidents(...)` select. The class documents explicitly that it is **read-only**:
ordering and matching live in the DB, never in the app.

---

## 7. Service Layer

### 7.1 `AuthService` (`auth_service.dart`)
Encapsulates all authentication and role-routing.

- **`signUp(...)`** — creates an `auth.users` record then inserts a `profiles`
  row. Hard `assert(role != 'Unit')`: **units can never self-register**; they are
  provisioned by an admin.
- **`login(email, password)`** — `signInWithPassword`.
- **`resolveDestination(authUserId) → LoginDestination`** — the routing brain.
  Order matters: it **first** checks for a `units` row matching `auth_user_id`
  (→ `/unit`, unless `is_active == false` → `none`); only then falls back to
  `profiles.role` (`Admin` → `/admin`, `Citizen` → `/citizen`). This guarantees a
  unit account can never land on the admin console and vice-versa.
- **`getUserData(uid)`** — fetch a `profiles` row as `UserModel`.
- **`signOut()`**.

`LoginDestination` is an enum: `{ unit, admin, citizen, none }`.

### 7.2 `DispatchService` (`dispatch_service.dart`)
The central data-access service for everything dispatch-related. ~430 lines.
Grouped responsibilities:

**Constants & status vocabulary**
- `kRoadFactor = 1.3`, `kAvgCitySpeedKmh = 30.0` — kept in sync with the Python
  worker so ETAs match.
- `UnitStatus` class: string constants `available, assigned, enroute, onScene,
  resolved, offline`, plus `operationalSequence`, `terminal`, and `all`.

**Stations & Units (reads)**
- `getStations()`, `getAllUnits()`, `getUnitsForStation(stationId)` — all join
  `stations(name, latitude, longitude)` for display.

**Admin Unit CRUD & provisioning**
- `createUnitRow(...)` — inserts a `units` row (no auth yet), returns its id.
- `provisionUnitAccount(unitId, email, password)` — calls `auth.signUp` for the
  unit's credentials and links the new `auth.users.id` back into the row.
  **Important side effect:** because Supabase Flutter keeps a single session,
  this *replaces the admin's session with the new unit's*; the UI handles it by
  signing out and routing back to `/login`.
- `updateUnit(...)`, `setUnitActive(...)` (also forces `status=Offline` when
  disabling), `moveUnitToStation(...)`, `deleteUnit(...)`.

**Unit self-service**
- `getMyUnit()` — the `units` row for the signed-in auth user.
- `updateMyLocation(unitId, lat, lng)` — pushes live GPS + `last_location_at`.
- `setMyStatus(unitId, status)` — the unit owns its operational state; the DB
  trigger handles cleanup on terminal statuses.

**Distance / ETA (pure functions)**
- `haversineKm(...)`, `estimateDistanceAndEta(...)` — straight-line × 1.3 road
  factor, ÷ 30 km/h → minutes. Static; used by the admin manual-dispatch sheet.

**Dispatch reads**
- `getDispatchesForIncident(incidentId)` — junction rows + joined unit/station.
- `getActiveIncidentsForUnit(unitId)`.

**Global dispatch queue (NEW today)** — see §10/§15
- `getDispatchQueue()` — the whole queue in priority order (severity desc,
  enqueued asc), joining each incident.
- `watchDispatchQueue()` — a realtime `Stream` of the queue, re-sorted
  client-side (because `.stream()` can't order by a joined column).
- `requestDispatch(incidentId, unitType)` — RPC wrapper over `request_dispatch`.
- `removeFromQueue(incidentId, requiredUnitType)` — admin drop of a demand.

**Manual override (admin)**
- `addDispatch(...)` — manually attach a unit to an incident, compute its
  distance/ETA, set it `Assigned`, **and clear any matching queued demand**
  (added today, so the engine doesn't later send a duplicate unit).
- `removeDispatch(...)` — detach a unit, free it, and recompute the incident's
  primary unit (`_recomputePrimary`).
- `resolveIncident(...)` — admin-side close (frees all dispatched units).

---

## 8. Presentation Layer (Screens)

### 8.1 Entry & routing — `main.dart`
Initializes Supabase with the project URL + anon key, then runs
`IncidentDetectionApp`, a `MaterialApp` (Material 3, blue seed colour) with named
routes: `/` (Login), `/register`, `/admin`, `/citizen`, `/unit`.

### 8.2 Authentication screens
- **`login_screen.dart`** — email/password form. On success, calls
  `resolveDestination` and `pushReplacementNamed` to the right dashboard, or
  signs out with an error if the account is unprovisioned/disabled.
- **`register_screen.dart`** — Citizen/Admin only (dropdown). Citizens get
  emergency-contact fields and must toggle **Enable Location Access** to submit.
  Explicit notice that response units cannot self-register.

### 8.3 Citizen — `citizen_dashboard.dart`
The most feature-rich screen. Responsibilities:
- **Location:** `_determinePosition()` obtains GPS + reverse-geocoded address.
- **Voice SOS:** records an `.m4a` via `AudioRecorder`, uploads to the
  `voice_incidents` storage bucket, stores the public URL.
- **Send SOS (`_sendSos`)** — inserts an `incidents` row with `status:
  'Processing'`, the GPS, optional description and `voice_url`. (The AI worker
  takes over from here.)
- **Quick-dial** emergency numbers (Police 122 / Ambulance 123 / Fire 118).
- **Active-response tracking** (`_refreshActiveResponse`, polled every 5 s):
  finds the citizen's most recent non-resolved incident and the units dispatched
  to it, then shows a status card.
  - **Modified today:** the card now also shows while the incident is
    pre-dispatch (`Processing`/`Pending`/`Queued`), and a **`Queued`** incident
    displays *"Waiting for the next available unit."* Previously such an incident
    showed no card at all.

### 8.4 Unit — `unit_dashboard.dart`
Two-section layout: **current assignment** (top) and **status controls** (bottom).
- **GPS loop (`_startLocationLoop`)** — pushes device GPS every **30 s**.
  - **Modified today:** `_pushLocationOnce()` now reads the unit's **live status**
    first and **skips reporting while `Available`/`Offline`**, so the server's
    "park at station" reset (see §11) is not overwritten.
- **`_loadAll()`** — loads the unit, its current incident (via
  `current_incident_id`, with a fallback scan of `incident_dispatches`), and the
  matching dispatch row (distance/ETA).
- **Status state-machine (`_nextStatusesFrom`)**:
  `Available→Offline`, `Offline→Available`, `Assigned→{Enroute,Resolved}`,
  `Enroute→{OnScene,Resolved}`, `OnScene→Resolved`. The unit **owns** these
  transitions; the system only ever sets `Assigned`.
- **Assignment card** — severity chip, a Google Map preview with an incident
  marker, the dispatch report (ID, distance, ETA), description, and a button to
  write the post-incident report.

### 8.5 Unit — `incident_report_screen.dart`
Post-incident report form (type, actions taken, outcome). On submit: inserts an
`incident_reports` row, **then closes the incident by setting the unit's own
status to `Resolved`** (the trigger does the rest). Falls back to the admin
resolve path if no unit row is found.

### 8.6 Admin — `admin_dashboard.dart`
- A **Realtime `StreamBuilder`** over `incidents` (live).
- Top **stat cards**: counts of Assigned / Pending / Resolved.
- **Unit-management** buttons → Stations / Units screens.
- **Live Queue** — every non-resolved, non-processing incident, sorted by
  severity (`CRITICAL=3, URGENT=2, LOW=1`) then by age. (This is a UI *view* of
  incident records; it is conceptually related to but distinct from the DB-level
  `dispatch_queue` table — see §15 note.) Each tile opens the incident detail.

### 8.7 Admin — `stations_screen.dart`
Expandable cards: one per station, showing its units and an "N available" count.

### 8.8 Admin — `units_screen.dart`
Full **Unit lifecycle management**: list (with status colour + live location),
**create** (row + auth account in one flow, with the documented admin-logout side
effect), **edit**, **provision credentials** (for rows without an account),
**disable/enable**, **delete** (hard-deletes the row, leaves the auth user for
audit).

### 8.9 Admin — `incident_detail_screen.dart`
- A **Google Map** with the incident marker plus a marker + dashed polyline for
  **every** dispatched unit's station→incident route.
- Description + voice link.
- **Dispatched-units** list with per-unit distance/ETA and a remove (✕) button.
- **Add Unit** bottom sheet — lists available units sorted by computed ETA;
  tapping one calls `addDispatch`. **Resolve** closes the incident and frees all
  units.

---

## 9. The AI / Machine-Learning Microservice

Located in `emergency_ai/`. It runs as a standalone always-on Python process
using the Supabase **service-role** key (and therefore **bypasses RLS**).

### 9.1 `emergency_response_manager.py` — the "AI Brain"
- **`load_models()`** loads six artefacts plus the sentence encoder:
  - `st_encoder` = Sentence-Transformer `all-mpnet-base-v2` (768-dim embeddings).
  - `fake_detector` — classifies a report as genuine vs fake (on embeddings).
  - `severity_model` + `severity_vectorizer` — **TF-IDF + LogisticRegression**
    predicting severity, mapped via `SEVERITY_MAP = {0:LOW, 1:URGENT, 2:CRITICAL}`.
  - `amb_model`, `fire_model`, `pol_model` — three independent binary
    classifiers (on embeddings) deciding whether each unit type is required.
- **`predict_incident(text, models)`** pipeline:
  1. `clean_text` (lowercase, strip punctuation/whitespace).
  2. **Fake detection** — if `P(fake) ≥ 0.5` → return `{Fake:true, severity:FAKE,
     dispatch:[NONE]}` (short-circuit; never dispatched).
  3. **Severity** — TF-IDF vector → `severity_model` → arg-max → label.
  4. **Dispatch types** — embedding → each of amb/fire/pol model; any with
     `P ≥ 0.5` is appended. Empty → `["NONE"]`.

### 9.2 `app.py` — the worker loop
- **`start_polling()`** — every **3 s**, selects `incidents` where
  `status='Processing'` and processes each.
- **`process_incident(record)`**:
  1. If `voice_url` present → download → **Whisper `base`** transcribes →
     `final_text`. Otherwise use the typed `description`.
  2. `predict_incident(final_text)` → severity + dispatch list.
  3. Update the incident: `description=final_text, severity, incident_type,
     status='Pending'`.
  4. If not fake and units are needed → `dispatch_units_to_incident(...)`.
- **`dispatch_units_to_incident(...)` — REWRITTEN today.** Previously this
  function itself searched for the nearest available unit per type and wrote the
  dispatch rows (~95 lines). It now simply calls the **`request_dispatch` RPC**
  once per required type and logs whether the unit was dispatched or queued. All
  matching/queueing logic moved to the database (§10). The old helper
  `find_closest_unit_of_type` was removed.

### 9.3 `train_and_test.py` — offline training
Loads a labelled Excel dataset (`description`, `severity`, boolean
`fire/ambulance/police`), encodes descriptions with `all-mpnet-base-v2`, splits
80/20, trains a `LogisticRegression` severity model and a
`MultiOutputClassifier(LogisticRegression)` for the three unit flags, and
includes a `test_sos()` demo. (This is the conceptual origin of the `.pkl`
models; the served models also add a fake detector and a TF-IDF severity path.)

---

## 10. The Dispatch Engine & Global Queue (today's work)

This is the heart of today's redesign, implemented entirely in
`supabase/migrations/20260623_dispatch_queue.sql`.

### 10.1 Design goals (from the requirement)
1. **One global queue** shared by all stations (not per-station).
2. Queue **ordered by severity (desc) then creation/age (asc)**.
3. **On incident creation:** dispatch the nearest available unit if one exists;
   otherwise enqueue.
4. **On a unit becoming available:** look at the queue, take the **highest
   severity** waiting, among those pick the **nearest** incident, break near-ties
   by **oldest**, dispatch, and remove from the queue.
5. **Separation of concerns:** the *queue* answers "which incident first?"; the
   *dispatch engine* answers "which unit serves which incident?".

### 10.2 The unit-type reconciliation (important design note)
The written requirement speaks of "incidents" in the queue, but the system can
only send a **matching unit type** (you cannot send an ambulance to a fire). The
queue therefore stores **demands** — one row per *(incident, required unit
type)*. An incident needing POLICE **and** FIRE can have one demand filled
immediately and the other queued. Every rule in the requirement maps cleanly onto
demands; this also keeps the model correct and scalable as stations/units grow.

### 10.3 Priority: `severity_rank()`
```sql
CRITICAL → 3,  URGENT → 2,  LOW → 1,  (FAKE/unknown) → 0
```
Aligned today to the AI's exact 3-level output. The absolute numbers are
arbitrary; only their **order** matters. The value is denormalized into
`dispatch_queue.severity_rank` at enqueue time so the priority index can sort
without a join.

### 10.4 Distance in SQL: `haversine_km()`
A pure, `IMMUTABLE` SQL function computing great-circle distance, so the engine
can rank candidates inside the database. Road distance and ETA apply the same
constants as the app/worker (×1.3, ÷30 km/h) at commit time.

### 10.5 Commit step: `_perform_dispatch(unit, incident)`
The single place that *writes* a dispatch:
1. Reads incident coords and the unit's location — **preferring live GPS**
   (`current_latitude/longitude`), falling back to the unit's **station**.
2. Computes `distance_km` (×1.3) and `eta_minutes` (÷30 km/h).
3. Inserts an `incident_dispatches` row (idempotent via `ON CONFLICT DO NOTHING`).
4. Sets the unit `Assigned` + `current_incident_id`.
5. Promotes the incident to `Assigned`, keeping the **primary** unit's ETA via
   `coalesce` (first unit wins).
Declared `SECURITY DEFINER` (see §10.9).

### 10.6 Incident-driven entry: `request_dispatch(incident, type) → bool`
Used by the **Python worker** (and the app's `requestDispatch`). For one
required type:
1. Find the **nearest** `Available`, `is_active` unit of that type across **all**
   stations (ordered by `haversine_km`), locking it with `FOR UPDATE … SKIP
   LOCKED` so two concurrent dispatches can't grab the same unit.
2. If found → `_perform_dispatch` → return `true` (dispatched immediately, **not**
   queued).
3. If none → insert a `dispatch_queue` demand (idempotent) and set the incident
   `Queued`; return `false`.

### 10.7 Unit-driven entry: `dispatch_available_unit(unit) → bool`
The engine that runs when a unit frees up. Implements the requirement's steps
1–7 exactly:
1. Read the unit's type + location (live GPS, else station); bail if it isn't a
   genuinely dispatchable `Available`/`is_active` unit.
2. **`SELECT max(severity_rank)`** among queued demands of that type — the
   highest severity currently waiting (ignore everything below).
3–6. Among **only** that top severity, order by `round(haversine,1) ASC` then
   `enqueued_at ASC` → **nearest, ties→oldest** — `LIMIT 1 FOR UPDATE SKIP
   LOCKED` (two freeing units can't grab the same incident).
7. `_perform_dispatch` then `DELETE` the satisfied demand from the queue.

### 10.8 Event wiring: the `units_dispatch_after_available` trigger
An **AFTER INSERT/UPDATE OF status** trigger on `units`. When a row transitions
**into** `Available` (and `is_active`), it calls `dispatch_available_unit(new.id)`.
- It fires **after** the existing `units_auto_resolve` BEFORE-trigger has flipped
  a resolving unit back to `Available`, so a single "Resolved" update both frees
  the unit *and* immediately pulls its next job — **no app code, no polling.**
- The guard (`old.status IS DISTINCT FROM 'Available'`) prevents recursion: the
  dispatch sets the unit to `Assigned`, never back to `Available`, so it can't
  re-trigger itself.

### 10.9 Why `SECURITY DEFINER`
The trigger fires while a **Unit** is updating *its own* row, but the engine must
insert `incident_dispatches`, update *other* units, and delete queue rows — all
forbidden by the Unit's RLS. Declaring the engine functions `SECURITY DEFINER`
(running as the function owner) lets the fixed, audited logic perform these
writes without granting Units any broad privileges. `search_path` is pinned for
safety.

### 10.10 RLS for `dispatch_queue`
RLS enabled; an **admin-only** policy (`queue_admin_all`) governs app access. The
worker uses the service-role key (bypasses RLS), and the engine functions are
`SECURITY DEFINER`, so the trigger path needs no Unit-facing grants.

### 10.11 Responsibility map (separation of concerns)
| Question | Owned by |
|---|---|
| "Which incident first?" | `dispatch_queue` table + priority index + `severity_rank()` |
| "Which unit serves which incident?" | `request_dispatch()` / `dispatch_available_unit()` |
| "Commit the dispatch" | `_perform_dispatch()` |
| "When to run the engine" | `units_dispatch_after_available` trigger |

---

## 11. Idle-Unit Return-to-Station (today's work)

Implemented in `supabase/migrations/20260623_unit_idle_return.sql`. Problem: a
unit that finished a job (and whose app may have stopped reporting GPS) would
otherwise keep being measured from the **last incident's coordinates forever**.

### 11.1 The idle clock: `available_since` + `units_track_available_since`
A `BEFORE INSERT/UPDATE OF status` trigger stamps `available_since = now()` when a
unit **enters** `Available`, and clears it (`NULL`) when it leaves. Trigger name
ordering guarantees it runs *after* `units_auto_resolve`, so a resolve correctly
stamps the clock. Existing idle units are backfilled.

### 11.2 The reset: `return_idle_units_to_station() → int`
Moves a unit's `current_latitude/longitude` to its station **only if** it is
`Available`, `is_active`, has `current_incident_id IS NULL`, has been idle
> 5 minutes (`available_since < now() - interval '5 minutes'`), and is **not
already** at its station. Returns the number moved. `SECURITY DEFINER`.

### 11.3 The schedule: pg_cron `return-idle-units`
`CREATE EXTENSION pg_cron` + a job running **every minute** that calls the reset.
So any unit crossing the 5-minute idle mark is sent home within ~1 minute,
automatically, regardless of who is online.

### 11.4 Interaction with the app's GPS loop
Because the unit app pushed GPS every 30 s **even while idle**, it would overwrite
the reset. Today's `unit_dashboard.dart` change makes the app **stop reporting
while `Available`/`Offline`**, so the station reset sticks. (Net effect: a unit's
stored location is live device GPS *only during an active job*; after resolving it
freezes, then within ~5 min returns to its station.)

---

## 12. Distance & ETA Model

A deliberately simple, explainable model (no external routing API), implemented
identically in three places (Dart, Python, SQL):

```
straight_km = haversine(p1, p2)              # great-circle distance
road_km     = straight_km × ROAD_FACTOR      # ROAD_FACTOR = 1.3
eta_minutes = (road_km / AVG_CITY_SPEED) × 60 # AVG_CITY_SPEED = 30 km/h
```

- **ROAD_FACTOR 1.3** — roads aren't straight; urban driven distance is ~1.3× the
  crow-flies distance (a standard heuristic).
- **AVG_CITY_SPEED 30 km/h** — average arterial speed incl. traffic in Cairo/Giza.

The three implementations are kept in sync intentionally so an ETA computed by the
worker, the app, or the DB engine all match.

---

## 13. Concurrency, Polling Intervals & Realtime

Everything is **interval-driven or event-driven** — nothing is truly real-time
except Supabase Realtime streams.

| Mechanism | Cadence | Where |
|---|---|---|
| Unit GPS push | every **30 s** (only while on a job) | `unit_dashboard.dart` |
| Citizen active-response poll | every **5 s** | `citizen_dashboard.dart` |
| AI worker scan for new incidents | every **3 s** | `app.py` |
| Idle → station reset | every **1 min** (cron) | DB |
| Admin incidents list | push (Realtime stream) | `admin_dashboard.dart` |
| Admin queue (optional) | push (`watchDispatchQueue` stream) | `dispatch_service.dart` |

**Race safety:** the dispatch engine uses `FOR UPDATE … SKIP LOCKED` on both unit
selection (incident-driven) and incident selection (unit-driven), so concurrent
dispatches — e.g. two units freeing simultaneously, or the worker dispatching
while a unit frees up — never double-assign the same unit or incident.

---

## 14. Security Model

### 14.1 Authentication
Supabase Auth (`auth.users`). Citizens/Admins self-register; **Units are
provisioned by an admin** and linked via `units.auth_user_id`. Login routing is
deterministic and unit-first (§7.1).

### 14.2 Row-Level Security (RLS)
Enforced per role (from the migrations):
- **Admins** — full access to `units`, `incidents`, `incident_dispatches`,
  `dispatch_queue` via `profiles.role = 'Admin'` policies.
- **Units** — may read/update **only their own** `units` row; may read incidents
  and dispatches **assigned to them**.
- **Citizens** — may read **their own** incidents, and (via the
  `20260617_citizen_active_response` migration) the unit + dispatch rows for the
  incident **they reported** (so they can track the responder).
- **Service role** (Python worker) — bypasses RLS entirely.
- **Engine functions** — `SECURITY DEFINER`, so trigger-driven dispatch works
  without widening Unit privileges.

### 14.3 Note on secrets
`main.dart` and `app.py` contain the Supabase URL and keys inline. The **anon
key** in the client is expected to be public; however the **service-role key in
`app.py` is highly sensitive** and must never ship in a client or public repo —
for production it should be an environment variable. *(Flag for the report.)*

---

## 15. Changelog of Today's Modifications

**New files**
- `supabase/migrations/20260623_dispatch_queue.sql` — global queue table,
  `severity_rank`, `haversine_km`, `_perform_dispatch`, `request_dispatch`,
  `dispatch_available_unit`, the `units_dispatch_after_available` trigger, and
  RLS for the queue.
- `supabase/migrations/20260623_unit_idle_return.sql` — `available_since` column,
  `units_track_available_since` trigger, `return_idle_units_to_station`, and the
  `return-idle-units` pg_cron job.
- `lib/models/dispatch_queue_entry.dart` — `DispatchQueueEntry` read-model.

**Modified files**
- `lib/models/incident_model.dart` — added the `severity` field.
- `lib/services/dispatch_service.dart` — imports the new model; added
  `getDispatchQueue`, `watchDispatchQueue`, `requestDispatch`, `removeFromQueue`;
  `addDispatch` now also clears the matching queued demand.
- `emergency_ai/app.py` — `dispatch_units_to_incident` rewritten to call
  `request_dispatch`; removed `find_closest_unit_of_type` (~95 lines of
  matching logic deleted).
- `lib/screens/citizen/citizen_dashboard.dart` — shows the response card for
  pre-dispatch states and a "Waiting for the next available unit" headline for
  `Queued` incidents.
- `lib/screens/unit/unit_dashboard.dart` — `_pushLocationOnce` now skips GPS
  reporting while the unit is `Available`/`Offline`.

**Severity alignment** — `severity_rank()` was set to exactly three levels
(`CRITICAL=3, URGENT=2, LOW=1`) to match the AI's `SEVERITY_MAP`.

> **Note — two "queues":** the admin dashboard's *Live Queue* is a UI sort of
> incident records and predates today's work. The new `dispatch_queue` **table**
> is the authoritative engine-level queue of unmet demands. They can coexist; a
> future cleanup could point the admin view at `dispatch_queue` via
> `watchDispatchQueue()`.

---

## 16. Setup, Configuration & Deployment

### 16.1 Flutter client
```bash
flutter pub get
flutter run            # choose a device/emulator
```
Supabase URL + anon key are set in `lib/main.dart`. Google Maps requires a valid
API key configured per platform (Android/iOS/web manifests).

### 16.2 Database migrations
Apply the SQL in `supabase/migrations/` (in date order) via the Supabase **SQL
Editor** or `supabase db push`. Today's two migrations are idempotent
(`create or replace`, `if not exists`, `drop … if exists`). The idle-return
migration needs **pg_cron** enabled (Database → Extensions, or the included
`create extension`).

### 16.3 AI worker
```bash
cd emergency_ai
pip install supabase requests openai-whisper sentence-transformers scikit-learn joblib numpy
# ffmpeg must be installed and on PATH (Whisper dependency)
python app.py
```
The worker needs the **service-role** key (currently inline in `app.py`).

---

## 17. Testing & Verification Procedures

### 17.1 Immediate dispatch (units free)
Report an incident with at least one matching `Available` unit → worker sets
severity/type → `request_dispatch` assigns the nearest unit → incident becomes
`Assigned`, an `incident_dispatches` row appears, the unit goes `Assigned`.

### 17.2 Queueing (no units free)
Make all matching units busy/offline → report an incident → a `dispatch_queue`
row appears, incident becomes `Queued`, citizen sees "Waiting for the next
available unit."

### 17.3 Auto-dispatch on unit free
With a queued incident waiting, have a busy unit mark **Resolved** → the
`units_auto_resolve` trigger frees it → `units_dispatch_after_available` fires →
the highest-priority queued incident is dispatched and its queue row deleted —
all within the same transaction.

### 17.4 Idle return
Resolve an incident, leave the unit idle → within ~5–6 min the
`return-idle-units` cron resets its location to its station. Manual check:
`select public.return_idle_units_to_station();` (returns count moved).

### 17.5 Priority ordering
Queue a `LOW` and a `CRITICAL` of the same type; free one unit → it must take the
`CRITICAL` first. Queue two `CRITICAL`s; the **nearest** wins, ties → **older**.

---
---

# PART II — THEORETICAL DOCUMENTATION

## 1. Problem Domain & Motivation

Emergency response is a **time-critical resource-allocation** problem. The core
tension: a finite pool of mobile resources (units) must serve a stochastic,
spatially-distributed stream of demands (incidents), where **response time
correlates with outcomes** (survival, damage limitation). A naïve "assign the
nearest free unit, else give up" policy fails under load — exactly when
emergencies cluster. This project addresses that failure mode with a **priority
queue + automatic re-dispatch** architecture, plus **AI triage** to classify
urgency and resource needs from natural-language (typed or spoken) reports.

The system embodies three classical sub-problems:
1. **Triage/classification** — what kind of emergency, how severe? (ML/NLP)
2. **Scheduling** — in what order should waiting incidents be served? (priority)
3. **Assignment** — which unit serves which incident? (spatial matching)

## 2. Emergency Dispatch Theory

Real-world Computer-Aided Dispatch (CAD) systems balance several objectives:
- **Minimize response time** (dispatch the closest capable unit).
- **Respect priority** (life-threatening calls pre-empt minor ones).
- **Maintain coverage** (don't strip an area of all units).
- **Match capability** (send the right *type* of resource).

This project implements the first three explicitly and the fourth via
**type-scoped demands** (§I.10.2). It deliberately separates **priority** (a
temporal/severity question) from **assignment** (a spatial question), mirroring
how human dispatchers think: *first* decide whose call matters most, *then* decide
who to send. This is also why the queue does not pick units and the engine does
not decide priority — a clean factoring that generalizes as the system scales.

## 3. Priority Scheduling Theory

The queue is a **non-preemptive priority queue** with a **tie-breaking on
arrival time**:

- **Primary key — severity (descending).** A higher-severity incident always
  pre-empts a lower one for the *next* available unit. This is *static priority
  scheduling*: classes are `CRITICAL > URGENT > LOW`.
- **Secondary key — age (ascending, FIFO within a class).** Among equal
  severity, the oldest waits least longer — *First-Come-First-Served* within a
  priority band. This bounds the worst-case wait within a class and provides a
  fairness guarantee.

**Non-preemptive** means a unit already dispatched to a `LOW` incident is *not*
recalled when a `CRITICAL` arrives; only **the allocation of newly-free units**
is prioritized. This avoids thrashing (units abandoning scenes) at the cost of
some theoretical optimality — the standard trade-off in real dispatch.

**Starvation consideration.** Pure static priority can starve `LOW` incidents
under sustained `CRITICAL` load. The age tiebreak mitigates *within* a class but
not *across* classes. A future refinement (Part II §11) is **aging** — gradually
raising an incident's effective priority the longer it waits — converting static
priority into a dynamic one.

The implementation realizes this ordering as a **database index**
`(required_unit_type, severity_rank DESC, enqueued_at ASC)`, so "pick the most
important waiting demand" is an index scan, not a sort — O(log n) to locate, and
naturally scalable.

## 4. Spatial Assignment & the Haversine Model

Once priority selects *which* incident, assignment selects *which* unit by
**proximity**. Two directions exist:

- **Incident-driven** (new incident, search units): nearest free unit of the
  required type — a *1-to-many nearest-neighbour* query.
- **Unit-driven** (freed unit, search incidents): among the top-severity queued
  demands, the nearest incident — *nearest-neighbour with a priority filter*.

Distance uses the **Haversine formula** for great-circle distance on a sphere:

```
a = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)
d = 2R · asin(√a),   R ≈ 6371 km
```

where φ is latitude, λ is longitude (in radians). Haversine is chosen over
planar (Euclidean) distance because lat/long are angular; over short urban
distances the error of Euclidean is small, but Haversine is correct and cheap.

**From distance to ETA.** Real travel time depends on the road network, traffic,
and turn penalties. Rather than a routing engine, the project uses a transparent
**affine model**: `road ≈ 1.3 × straight`, `time = road / 30 km/h`. This is
*explainable* (every term defensible) and *deterministic* (reproducible for a
demo), at the cost of ignoring live conditions — an acceptable trade for a
graduation prototype, and a clean seam to later swap in Google/Mapbox routing.

**Tie-breaking near-equal distances.** Floating distances rarely tie exactly, so
"very similar distance" is operationalized by **rounding to 0.1 km** before the
age tiebreak — incidents within ~100 m are treated as equidistant and decided by
age. The rounding granularity is a tunable fairness/optimality knob.

## 5. Queueing Theory Foundations

The system is, formally, a **multi-server priority queue** (M/M/c-like, with
priorities and heterogeneous servers). Relevant concepts:

- **Servers (c)** = available units of a given type. **Arrivals (λ)** = incidents
  of that type. **Service time (μ⁻¹)** = on-scene + travel time until the unit
  frees.
- When λ approaches cμ, the queue length grows — precisely the overload regime
  where a priority discipline matters most.
- **Little's Law** (L = λW) tells us average queue length L relates mean arrival
  rate λ and mean wait W; reducing W (faster dispatch/turnaround) directly
  reduces backlog.
- The **automatic re-dispatch on unit-free** event minimizes idle server time —
  a freed server immediately pulls the highest-priority waiting job, maximizing
  utilization and minimizing W for high-priority classes.

The per-type scoping means the system is really **three parallel priority queues**
(POLICE/AMBULANCE/FIRE), each with its own server pool — a correct model since a
fire engine cannot serve a medical call.

## 6. Event-Driven Architecture & Database Triggers

The redesign favours **event-driven** over **poll-driven** dispatch for the
unit-free case. The state change *"a unit became Available"* is an **event**; a
database **trigger** is an event handler co-located with the data. Benefits:

- **Atomicity** — freeing the unit and assigning its next job happen in **one
  transaction**; there is no window where the unit is idle-but-unconsidered.
- **No polling latency or cost** — versus a worker that would have to repeatedly
  scan for newly-free units.
- **Single source of truth** — the rule lives next to the data it governs, so the
  app and the worker cannot implement divergent policies.

The trade-off is that complex logic in triggers can be harder to test and can add
latency to the triggering write; here the logic is bounded (indexed lookups over a
small queue) and the clarity/correctness benefits dominate.

## 7. Concurrency & Race Conditions

Multiple actors mutate shared state concurrently: the worker dispatches new
incidents while units independently resolve and free up. Two classic hazards:

1. **Double-assignment of a unit** — two dispatches selecting the same free unit.
2. **Double-service of an incident** — two freed units grabbing the same queued
   demand.

Both are prevented with **pessimistic row locking**: `SELECT … FOR UPDATE SKIP
LOCKED`. The first transaction locks the chosen row; a concurrent transaction
**skips** the locked row and selects the next candidate instead of blocking or
colliding. This yields high concurrency *and* correctness — the standard pattern
for safe work-queue consumption in PostgreSQL. The `ON CONFLICT DO NOTHING` on
inserts and the `coalesce`-based "primary unit" promotion provide idempotency as a
second line of defence.

## 8. Clean Architecture & Separation of Concerns

The codebase is layered:

```
Presentation (screens)  →  Service (DispatchService/AuthService)  →  Data (Supabase)
        ▲                                                                  │
        └────────────── Entities (models, pure data) ─────────────────────┘
```

- **Entities** (`models/`) are anaemic by design — pure data, trivially testable,
  reusable across layers.
- **Services** centralize data access and business operations; screens never
  embed SQL or RPC details inline (mostly).
- **The database** owns *invariants and decisions* that must hold regardless of
  client — dispatch policy, status transitions, security. Putting policy here
  (rather than in one of several clients) is the key SoC win of today's work: a
  closed app, an offline admin, or a second client cannot violate or duplicate
  dispatch logic.

Within the dispatch engine itself, responsibilities are further factored: the
**queue/index** owns *priority*, the **engine functions** own *matching*, the
**commit helper** owns *persistence*, the **trigger** owns *timing*. Each can be
reasoned about and changed independently — the litmus test of good SoC.

## 9. Natural-Language Processing & Machine-Learning Theory

The AI microservice is a small but complete **NLP triage pipeline**.

### 9.1 Speech-to-text — OpenAI Whisper
Whisper is a transformer-based **encoder-decoder** trained on large multilingual
audio. The `base` model converts a citizen's voice clip into text, enabling
hands-free reporting (critical when a caller cannot type). It is robust to accents
and noise relative to classical ASR.

### 9.2 Text representation — two complementary schemes
- **Sentence embeddings (`all-mpnet-base-v2`)** map text to a 768-dim vector
  capturing **semantic** meaning; "my house is on fire" and "flames in the
  kitchen" land near each other. Used for fake-detection and unit-type models.
- **TF-IDF** represents text by **term importance** (frequency × inverse document
  frequency), a sparse lexical signal. Used for the severity model. Combining a
  semantic and a lexical view is a pragmatic ensemble of representations.

### 9.3 Classifiers — Logistic Regression
A **linear, probabilistic** classifier: it models `P(class | features)` via the
logistic/softmax function over a weighted sum of features. Chosen because it is
**fast, interpretable, well-calibrated**, and strong on top of good embeddings —
ideal for a real-time worker. Two heads:
- **Severity** (multi-class): `LOW / URGENT / CRITICAL` via arg-max.
- **Unit type** (multi-label): three independent binary classifiers
  (amb/fire/pol), since an incident may need several types. This is the
  **binary-relevance** approach to multi-label classification; the training
  script uses scikit-learn's `MultiOutputClassifier` to the same end.

### 9.4 Fake-report detection
A binary classifier on embeddings gates the pipeline: `P(fake) ≥ 0.5` →
short-circuit to `severity=FAKE, dispatch=[NONE]`. This protects scarce resources
from prank/erroneous reports — a simple but important **trust** layer. The 0.5
threshold trades false-positives (ignoring a real call) against false-negatives
(dispatching to a fake); in a safety system this threshold deserves careful tuning
and a human-review fallback.

### 9.5 Decision thresholds & probabilities
Every model emits **probabilities**, thresholded at 0.5. Exposing probabilities
(rather than hard labels) leaves room for future **confidence-aware** behaviour —
e.g. auto-dispatch only above a high confidence, otherwise route to a human
dispatcher.

## 10. Scalability Analysis

- **More stations/units:** the engine never enumerates stations; it queries units
  by type/availability with distance ordering. Adding stations/units is pure data
  — no code change. The nearest-unit and nearest-incident queries scale with
  proper indexing (spatial indexes such as PostGIS GiST could replace the inline
  haversine sort at large scale).
- **More incidents:** the priority index makes "next best demand" an index scan;
  queue operations are O(log n). `SKIP LOCKED` keeps throughput high under
  concurrency.
- **More clients:** because policy lives in the DB, additional clients (a web
  dashboard, a second app) inherit correct behaviour for free.
- **AI throughput:** the worker is single-threaded polling every 3 s; at scale it
  would become multi-worker (the `Processing` flag + row claiming generalizes to
  multiple consumers) or move to Supabase Edge Functions / a queue.

## 11. Limitations & Future Work

1. **Static priority → aging.** Add time-based priority escalation to prevent
   `LOW` starvation under sustained high-severity load.
2. **Distance model → real routing.** Swap the ×1.3 / 30 km/h heuristic for a
   live routing API (the DB cannot call out; this would live in the worker or an
   edge function).
3. **Coverage-aware dispatch.** Consider not sending the *last* unit in an area,
   to preserve response capacity (a multi-objective extension).
4. **Confidence-aware AI + human-in-the-loop** for low-confidence or
   borderline-fake reports.
5. **Severity granularity.** The AI emits three levels; a four-level
   (Critical/High/Medium/Low) scale would need retraining (the `severity_rank`
   function already tolerates it).
6. **Secrets management.** Move the service-role key out of `app.py` into
   environment configuration.
7. **Observability.** Add dispatch metrics (mean time-to-dispatch per severity,
   queue depth over time) to validate the theory against live data.
8. **Two-queue cleanup.** Point the admin "Live Queue" view at the authoritative
   `dispatch_queue` table.

---
---

# PART III — SESSION 2 ADDITIONS

This part documents the features added after the original draft: **duplicate
incident detection**, **citizen UI refinements**, the **feedback/rating
system**, **persistent login**, and **push notifications**. Together they bring
the app to its current state.

## III.1 Duplicate Incident Detection (Python worker)

To stop several reports of the *same* emergency from each consuming separate
units, `emergency_ai/app.py` now runs a **three-stage duplicate filter** inside
`process_incident`, *before* dispatching.

### Schema additions on `incidents`
| Column | Type | Purpose |
|---|---|---|
| `has_duplicate` | `boolean` default `false` | `true` once an incident is linked to another as a duplicate (so it isn't itself matched against) |
| `case_id` | `text` | groups a master incident and all its duplicates under one case (e.g. `CASE-1719…`) |

### The detection pipeline (`check_duplicate_incident`)
For a new incident, it considers all incidents with `has_duplicate = false` and
filters in three increasingly expensive stages:
1. **Location filter** — keep incidents within **500 m** (`geopy.geodesic`).
2. **Time filter** — of those, keep ones created within the last **30 minutes**
   (`parse_created_at` normalizes the timestamp).
3. **Semantic similarity** — embed both descriptions with the Sentence-
   Transformer and compute **cosine similarity** (`util.cos_sim`); a score
   ≥ **0.5** is a duplicate.

### Linking (`handle_duplicate_incident`)
When a duplicate is found: the new incident is tagged `has_duplicate = true`,
given the master's `case_id` (created if absent), and **NOT dispatched** (the
worker `return`s early). If the duplicate is *more severe* than the master, the
master's severity is upgraded. Net effect: **a case is dispatched/queued once**
(through the master); later reports of the same event are linked, not
re-dispatched.

> Design note (documented for the defence): duplicate matching currently
> includes `Resolved` incidents and does not propagate a severity upgrade to a
> master that is already sitting in `dispatch_queue` — both are acceptable for
> the prototype and noted as future hardening.

## III.2 Citizen UI Refinements

- **Pre-dispatch state hidden.** While an incident has no unit yet, the citizen
  now sees only a neutral **hourglass + "Please wait…"** card — the severity,
  internal status, and "locating a unit" wording were removed. The real
  response info (unit type, ETA, "Help is on the way / has arrived") appears
  **only once a unit is actually assigned**.
- **Quick-Assistance removed.** The direct-dial emergency-numbers dropdown
  (Police/Ambulance/Fire) was deleted from the citizen dashboard.

## III.3 Feedback / Rating System

After an incident the citizen reported is **Resolved**, they can rate the
experience **1–5 stars** with an optional comment.

### Schema — `incident_feedback`
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `incident_id` | `uuid` FK → `incidents`, **unique** | one rating per incident |
| `reporter_id` | `uuid` | the citizen (`auth.uid()`) |
| `rating` | `int` CHECK 1–5 | required |
| `comment` | `text` nullable | optional |
| `created_at` | `timestamptz` | |
**RLS:** a citizen may read/insert feedback only for incidents **they reported**;
admins may read all (for quality review).

### Flow
- **`FeedbackService`** — `submitFeedback()` (stamps `reporter_id = auth.uid()`)
  and `getUnratedResolvedIncidents()` (their resolved incidents with no rating).
- **`incident_rating_sheet.dart`** — a reusable bottom sheet (stars + comment;
  stars required to submit, comment optional, freely skippable).
- **`citizen_dashboard.dart`** — every ~5 s it checks for resolved-but-unrated
  incidents and (a) **auto-prompts** the sheet once per incident, and (b) lists
  any unrated ones under **"Rate Your Past Incidents"** with a Rate button.

The rating is linked to the user by **`reporter_id`** and to the event by
**`incident_id`**, both written automatically at submit time and enforced by RLS.

## III.4 Persistent Login (AuthGate)

Previously the app always opened on the Login screen even though Supabase
persists the session. `lib/screens/auth/auth_gate.dart` is now the `/` route:
on startup it reads `Supabase.auth.currentSession` and, if present, routes
straight to the correct dashboard via `resolveDestination` (Unit/Admin/Citizen);
otherwise it shows Login. Logging out returns to `/`, which re-runs the check
and lands on Login. This keeps a signed-in user logged in across app restarts
and is a prerequisite for notifications (the app must know who is logged in to
register their device token).

## III.5 Push Notifications (Firebase Cloud Messaging)

The app delivers **server-initiated push notifications** that reach the user even
when the app is closed.

### Architecture
```
 DB row changes  →  Supabase Database Webhook  →  Edge Function  →  FCM  →  device
 (incident/dispatch)   (the "WHEN")               (the "WHO+WHAT")          (notification)
```
- A **device token** identifies one app-install. It is stored against the
  **currently logged-in user**, so a device only receives notifications for its
  current user (important because roles are switched on one device).
- The **webhook** is a dumb trigger (table + event). The **Edge Function** holds
  all the rules (who to notify, what message) and sends via FCM HTTP v1.

### Schema — `device_tokens` + RPCs
| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | |
| `user_id` | `uuid` | the logged-in user |
| `token` | `text` **unique** | the FCM device token |
| `platform` | `text` | e.g. `android` |
| `updated_at` | `timestamptz` | |

Two `SECURITY DEFINER` RPCs manage it: **`register_device_token`** (deletes any
prior owner of that token, then assigns it to `auth.uid()` — handles account
switching) and **`unregister_device_token`** (deletes the token on logout).

### Flutter side — `notification_service.dart`
Requests notification permission, fetches the FCM token, and registers it.
Wired in `main.dart` via `Supabase.auth.onAuthStateChange`: **register on
login / session-restore, unregister on logout**. Handles foreground messages
(in-app banner), background/terminated messages, and taps (routes to the right
dashboard). `AndroidManifest.xml` gained `POST_NOTIFICATIONS` (Android 13+).

### Firebase / Android wiring
`google-services.json` lives in `android/app/`; the **Google Services Gradle
plugin** is declared in `settings.gradle.kts` and applied in
`app/build.gradle.kts`. `firebase_core`/`firebase_messaging` pull the native
SDKs automatically (no manual BoM needed). `Firebase.initializeApp()` runs at
startup.

### The sender — `supabase/functions/send-notification/index.ts`
A Deno Edge Function triggered by **Database Webhooks**. It mints an OAuth token
from the Firebase **service-account key** (stored as the `FCM_SERVICE_ACCOUNT`
secret), looks up the recipient's tokens, and calls FCM HTTP v1. Events handled:

| Recipient | Trigger (webhook) | Message |
|---|---|---|
| Citizen | `incidents` UPDATE → status `Assigned` | "Help is on the way 🚑" |
| Citizen | `incidents` UPDATE → status `Resolved` | "How was your experience? ⭐" |
| Unit | `incident_dispatches` INSERT | "New assignment 🚨" |

Dead tokens (FCM 404) are auto-deleted. Adding a new notification = add an `if`
branch in the function (+ a webhook if it's a new table) and redeploy.

### Why server-side (not the worker/app)
Some events have no worker involved (trigger-driven auto-dispatch; unit-driven
resolve). A **webhook on the table change** catches every path uniformly, so the
notification logic lives in one place regardless of who caused the change.

## III.6 Changelog — Session 2

**New tables/columns:** `incident_feedback`; `device_tokens`; `incidents.has_duplicate`, `incidents.case_id`.
**New DB functions:** `register_device_token`, `unregister_device_token`.
**New Edge Function:** `send-notification` (+ 2 Database Webhooks).
**New Flutter files:** `auth_gate.dart`, `feedback_service.dart`, `notification_service.dart`, `incident_rating_sheet.dart`.
**Modified:** `main.dart` (Firebase + FCM + AuthGate routing), `citizen_dashboard.dart` (waiting card, removed quick-assist, feedback prompt), `emergency_ai/app.py` (duplicate detection), Android Gradle/manifest (Firebase + POST_NOTIFICATIONS).
**New dependencies:** `firebase_core`, `firebase_messaging` (Flutter); `geopy` (Python).

---
---

# APPENDICES

## Appendix A — Glossary

- **Incident** — a reported emergency.
- **Unit** — a deployable response resource (POLICE/AMBULANCE/FIRE), account-backed.
- **Station** — a physical base; a unit's home/fallback location.
- **Demand** — a queued *(incident, required unit type)* pair; the queue's unit.
- **Dispatch** — assigning a unit to an incident (`incident_dispatches` row).
- **Severity** — AI urgency class: `LOW / URGENT / CRITICAL` (or `FAKE`).
- **Primary unit** — the first-arriving (lowest-ETA) unit on a multi-unit incident.
- **RLS** — Row-Level Security; per-row access rules in PostgreSQL.
- **SECURITY DEFINER** — a function running with its owner's privileges.
- **SKIP LOCKED** — lock mode that skips rows locked by other transactions.
- **pg_cron** — PostgreSQL extension for scheduled SQL jobs.

## Appendix B — State & Status Reference

**Unit status** (CHECK-constrained): `Available, Assigned, Enroute, OnScene,
Resolved, Offline`.
Transitions (UI-enforced): `Available↔Offline`, `Assigned→{Enroute,Resolved}`,
`Enroute→{OnScene,Resolved}`, `OnScene→Resolved`. The system sets only
`Assigned`; the unit drives the rest; the trigger maps any terminal status back to
`Available`.

**Incident status**: `Processing` (AI working) → `Pending`/`Queued` (awaiting
dispatch) → `Assigned` (unit(s) en route) → `Resolved` (closed).

**Severity → rank**: `CRITICAL=3, URGENT=2, LOW=1, FAKE/unknown=0`.

## Appendix C — How to Export the Supabase Schema

> **Done:** §I.5 has already been reconciled against a live
> `information_schema` dump (column names/types/nullability/defaults are
> authoritative). The queries below are kept for re-exporting if the schema
> changes, or to additionally capture **foreign keys** and **RLS policy bodies**
> (not yet folded in).

Run **one** of the following and paste the result back:

**Option 1 — SQL Editor (quickest).** In Supabase → SQL Editor, run:
```sql
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;
```
…and, for constraints / FKs:
```sql
select tc.table_name, tc.constraint_type, kcu.column_name,
       ccu.table_name as references_table, ccu.column_name as references_column
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
       on tc.constraint_name = kcu.constraint_name
left join information_schema.constraint_column_usage ccu
       on tc.constraint_name = ccu.constraint_name
where tc.table_schema = 'public'
order by tc.table_name;
```

**Option 2 — Supabase CLI (full DDL):**
```bash
supabase db dump --schema public -f schema.sql        # structure
# or include policies/functions/triggers:
supabase db dump --schema public --data-only=false -f schema_full.sql
```

**Option 3 — Dashboard:** Database → Schema Visualizer / Tables, export.

Send me `schema.sql` (or the query output) and I will fold the exact column types,
defaults, constraints, and all RLS policy bodies into §I.5.

## Appendix D — End-to-End Worked Example

**Scenario (from the requirement):**
- Waiting queue: a `CRITICAL` near Madinat Nasr, a `CRITICAL` near Sheikh Zayed,
  and a `HIGH/URGENT` near Al Haram — all needing the same unit type.
- A unit becomes free near Masr El Gedida.

**Trace:**
1. The unit resolves → `units_auto_resolve` sets it `Available` →
   `units_dispatch_after_available` fires `dispatch_available_unit(unit)`.
2. `max(severity_rank)` over the queued demands = **3 (CRITICAL)** → the
   URGENT-near-Al-Haram demand is **ignored**.
3. Among the two CRITICAL demands, `haversine(unit, incident)` is computed →
   nearest wins; if within ~0.1 km, the **older** (smaller `enqueued_at`) wins.
4. `_perform_dispatch` writes the `incident_dispatches` row, sets the unit
   `Assigned`, promotes the incident to `Assigned`; the satisfied demand row is
   `DELETE`d from `dispatch_queue`.
5. The citizen who reported that incident sees the response card update from
   "Waiting for the next available unit" to "Units have been assigned."

— *End of document.*

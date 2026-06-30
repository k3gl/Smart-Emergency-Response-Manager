# Smart Emergency Response Manager — Full Demo Walkthrough (step by step)

> Pure click-through. What to open, what to show, what to type.
> Spoken narration is intentionally left out — add your own later.

## Devices / screens

| Screen | Role | Notes |
|---|---|---|
| Phone | **Unit** (responder) | Native maps + notifications work here |
| Chrome | **Citizen** | Use phone-frame view: F12 -> Ctrl+Shift+M |
| Edge | **Admin** | Separate browser = separate session |

> The Python AI service must be running in the background the whole time
> (it does the classification + dispatch). Do NOT show it on screen.

## Demo accounts (prepare beforehand)

| Role | Email | Password |
|---|---|---|
| Citizen (you'll create live) | citizen.demo@gmail.com | 123456 |
| Admin (seeded) | admin@demo.com | (your admin pass) |
| Unit (admin provisions it live, or pre-made) | unit.demo@demo.com | 123456 |

---

# PHASE 0 — Pre-demo setup (off camera)

1. Start the Python AI service and leave it running (not shown on screen).
2. Phone: app installed, on the Welcome/Login screen, NOT logged in yet
   (or logged in as the Unit and showing **Available** — your choice).
3. Edge: open the app URL, log in as **Admin**, sit on the Admin Console.
4. Chrome: open the app URL, sit on the **Welcome screen**, location allowed.
5. Make sure at least **2 units are Available** (so manual "Add Unit" works later).

---

# PHASE 1 — Onboarding & Auth  (Chrome)

1. **Open Chrome** on the **Welcome screen**. Show the two buttons: *Get Started* / *Create an account*.
2. Tap **Create an account** -> **Registration screen**.
3. Type into the fields:
   - **Full Name:** `Omar Gamal`
   - **Email:** `citizen.demo@gmail.com`
   - **Password:** `123456`
   - **Emergency Contact Name:** `Ahmed Ali`
   - **Emergency Contact Phone:** `01012345678`
4. Turn ON the **Enable Location Access** toggle.
5. Point out: there is **no Admin option** here — only citizens can self-register.
6. Tap **Create Account** -> it returns to **Login**.
7. On **Login**, type:
   - **Email:** `citizen.demo@gmail.com`
   - **Password:** `123456`
8. Tap **Login** -> lands on the **Citizen Dashboard**.

---

# PHASE 2 — Admin sets up the system  (Edge)

1. **Switch to Edge** (Admin Console).
2. Show **System Overview** cards: **Assigned / Pending / Resolved** counts.
3. Show the **Live Queue (severity -> time)** section (likely empty now).
4. Tap **Stations** -> **Stations & Units** screen:
   - Show each station and the units stationed there, each with a status color.
5. Go back, tap **Units** -> **Units Management** screen.
6. Tap **Create Unit**. In the dialog, type:
   - **Display name:** `Officer Adel`
   - **Unit code:** `POL-009`
   - **Login email (unique):** `unit.demo@demo.com`
   - **Temporary password:** `123456`
   - **Type:** select `POLICE`
   - **Station:** pick any station from the dropdown
   - Tap **Create**.
7. On the new (or an existing) unit, open its menu (the trailing icon) and show:
   - **Provision login credentials**
   - **Edit details**
   - **Disable unit** (then **Re-enable** so it stays active)
   - **Delete unit** (just show it exists — don't delete)
8. Confirm a unit shows status **Available** (it's ready for dispatch).

---

# PHASE 3 — Citizen features + smart filtering  (Chrome)

### 3A. Live location + edit contact
1. **Switch to Chrome** (Citizen Dashboard).
2. Show the **live location** line at the top (Lat/Long).
3. Tap **Edit Emergency Contact**. In the dialog, change:
   - **Name:** `Mona Ali`
   - **Phone:** `01099998888`
   - Tap **Save** -> "Contact updated!" appears.

### 3B. FAKE report (AI rejects it)
4. Scroll to **Report Incident**. In the description box type a NON-emergency:
   - `Hello how are you doing today?`
5. Tap the **SOS / send** button -> "SOS Sent!" -> status shows **Processing**.
6. WAIT a few seconds. The card changes to **"Report not verified"**
   ("This report wasn't recognised as a genuine emergency...").
   >> SCREENSHOT THIS FAST — it auto-hides after ~5 seconds.
7. Point out: no unit was dispatched — the AI filtered out a false alarm.

### 3C. Show the voice + anonymous options
8. In the report box, show the **microphone / record** button (voice reporting).
9. Show the **Report anonymously** toggle (leave it OFF for the main flow).

### 3D. REAL emergency (this one gets dispatched)
10. Clear the box and type a clear emergency:
    - `There is a big fire in the building with heavy smoke. People are trapped on the third floor.`
11. Tap **SOS / send** -> "SOS Sent! Help is on the way." -> status **Processing**.
12. Leave Chrome on this screen — you'll come back to watch the response card.

---

# PHASE 4 — Unit gets dispatched  (Phone)

1. **Switch to the phone** (Unit Dashboard, logged in as the unit).
   - If not logged in yet, log in now with `unit.demo@demo.com` / `123456`.
2. Show the **notification** pop-up (new assignment).
3. Show the **Current Assignment** card:
   - severity chip (e.g. CRITICAL/URGENT) + **Type**
   - the **map** with the incident pin
   - **Approx ... km · ETA ~... min**
   - the **description** text (the fire message)
4. Show the **Unit Status** controls at the bottom (Available / Enroute / OnScene).

---

# PHASE 5 — Admin oversight  (Edge)

1. **Switch to Edge** (Admin Console).
2. Show the counts changed: **Pending -> Assigned** (overview updated live).
3. Show the incident now appears in the list with its severity + status.
4. Tap the incident -> **Incident Details** screen:
   - the **map** showing the incident location + the dispatched unit
   - the **Dispatched Units** list (code, type, station, ~km, ~min)
5. Tap **Add Unit** -> pick an available unit from the sheet -> it's added
   (shows manual multi-unit dispatch).
6. Point out the **Resolve** button exists here too (don't tap it — the unit will resolve).

---

# PHASE 6 — Unit responds  (Phone + Chrome)

1. **Phone:** in **Unit Status**, tap **Enroute**.
2. **Switch to Chrome** (Citizen): the **Active Response** card now reads
   **"Help is on the way"** with the unit + ETA.
3. **Phone:** tap **On Scene**.
4. **Chrome:** the card updates to **"Help has arrived"**.

---

# PHASE 7 — Resolve the incident  (Phone)

1. **Phone:** tap **Write incident report** -> **Post-Incident Report** screen.
2. Fill the form:
   - **Incident Type:** select `Fire`
   - **Actions Taken:** `Extinguished the fire and evacuated all residents safely.`
   - **Outcome:** `Fire fully controlled. No casualties. Building secured and handed over.`
3. Tap **Submit & Resolve**.
4. Show: the unit returns to **Available** (assignment card clears).
5. **Switch to Chrome:** the Active Response card has disappeared (incident closed).

---

# PHASE 8 — Citizen feedback  (Chrome)

1. **Chrome:** a **rating pop-up** appears ("How was your experience?").
2. Tap to give a star rating (e.g. **5 stars**).
3. In the comment box type:
   - `Very fast response, the unit arrived quickly. Thank you!`
4. Tap **Submit** -> "Thanks for your feedback!" appears.

---

# PHASE 9 — (Optional) Extra features

### 9A. Voice report
1. **Chrome (Citizen):** tap the **microphone** button, speak a short emergency
   (e.g. "There is a car accident on the main road, someone is injured"), stop recording.
2. Tap **SOS / send** -> the AI transcribes the voice and dispatches as before.

### 9B. Anonymous report
1. Turn ON the **Report anonymously** toggle, then submit any report.
2. Show in **Admin / Unit** that the reporter identity is hidden.

### 9C. Duplicate detection
1. Submit a SECOND fire report from a nearby location (similar text).
2. The citizen card shows **"Already being handled"** (matched to the existing incident).

---

# PHASE 10 — Wrap-up  (Edge)

1. **Switch to Edge** (Admin Console).
2. Show **Resolved count incremented** by 1.
3. Show the **queue is empty** and units are **Available** again.

---

# Coverage checklist

- [ ] Welcome / Register / Login
- [ ] Citizen: live location, edit contact
- [ ] Citizen: text report, voice report, anonymous toggle
- [ ] AI: FAKE rejected ("Report not verified")
- [ ] AI: duplicate ("Already being handled")
- [ ] Citizen: Active Response (Assigned -> Enroute -> OnScene)
- [ ] Citizen: rating + comment
- [ ] Unit: Available state
- [ ] Unit: assignment + map + ETA + description
- [ ] Unit: Enroute / OnScene status
- [ ] Unit: Post-Incident Report + Resolve -> back to Available
- [ ] Admin: System Overview stats
- [ ] Admin: Live Queue
- [ ] Admin: Stations & Units
- [ ] Admin: Units Management (create / provision / edit / disable / enable / delete)
- [ ] Admin: Incident Details + map + Add Unit + Resolve

# Demo-day reminders

- Keep the AI service running the whole time (off screen).
- Screenshot the FAKE card immediately — it auto-hides in ~5s.
- If a web map is blank, show the map on the phone instead (or enable the Maps JavaScript API beforehand).
- Have a backup screen recording of the full flow in case Wi-Fi/dispatch lags.

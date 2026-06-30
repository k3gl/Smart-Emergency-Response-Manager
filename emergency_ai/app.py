import os
import math
import requests
import whisper
import time
from supabase import create_client, Client
from emergency_response_manager import predict_incident, MODELS
from sentence_transformers import util
from geopy.distance import geodesic
from datetime import datetime, timedelta

# 1. Supabase Configuration
# The service_role key is a full-admin secret and must NEVER be committed.
# It is read from the SUPABASE_SERVICE_KEY environment variable, or from a
# local, git-ignored file (emergency_ai/service_key.txt) for convenience.
SUPABASE_URL = "https://uhxnkufxjcqtmajkostv.supabase.co"
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")
if not SUPABASE_KEY:
    try:
        with open(os.path.join(os.path.dirname(__file__), "service_key.txt")) as _f:
            SUPABASE_KEY = _f.read().strip()
    except FileNotFoundError:
        raise RuntimeError(
            "Supabase service key not found. Set the SUPABASE_SERVICE_KEY "
            "environment variable, or create emergency_ai/service_key.txt "
            "containing the service_role key."
        )
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 2. Load Whisper
print("Loading Whisper model...")
whisper_model = whisper.load_model("base")

# Tunable constants for the approximate ETA model.
# Documented for the GP defense:
#  - ROAD_FACTOR: roads aren't straight, so the actual driven distance is
#    typically ~1.3x the great-circle distance (standard urban heuristic).
#  - AVG_CITY_SPEED_KMH: average speed including traffic in Cairo/Giza arteries.
ROAD_FACTOR = 1.3
AVG_CITY_SPEED_KMH = 30.0


def haversine_km(lat1, lng1, lat2, lng2):
    """Great-circle distance in kilometers between two GPS points."""
    R = 6371.0
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1_r) * math.cos(lat2_r) * math.sin(dlng / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def estimate_distance_and_eta(lat1, lng1, lat2, lng2):
    """Return (approx_road_km, approx_eta_minutes) for a station -> incident trip."""
    straight = haversine_km(lat1, lng1, lat2, lng2)
    road_km = straight * ROAD_FACTOR
    eta_min = (road_km / AVG_CITY_SPEED_KMH) * 60.0
    return road_km, eta_min


def dispatch_units_to_incident(incident, ai_results):
    """
    Multi-unit dispatch, delegated to the database dispatch engine.

      For EACH needed unit type (POLICE / AMBULANCE / FIRE) call the
      `request_dispatch` SQL function, which atomically either:
        - dispatches the nearest Available unit of that type (across all
          stations), writing the incident_dispatches row and flipping the
          unit to Assigned and the incident to Assigned; OR
        - if none is free, adds the demand to the global dispatch_queue and
          marks the incident 'Queued'.

      Matching, queueing, and priority all live in Postgres so the worker and
      the Flutter app share one source of truth and can't race.  When a unit
      later becomes Available, a DB trigger pulls the highest-priority queued
      incident automatically — no worker involvement needed.

    Returns the list of unit types that were dispatched immediately.
    """
    needed = [d for d in ai_results.get("dispatch", []) if d in ("POLICE", "AMBULANCE", "FIRE")]
    if not needed:
        return []  # FAKE / NONE

    dispatched = []
    for utype in needed:
        try:
            res = supabase.rpc("request_dispatch", {
                "p_incident_id": incident["id"],
                "p_unit_type": utype,
            }).execute()
            # request_dispatch returns True if dispatched, False if queued.
            if res.data is True:
                dispatched.append(utype)
                print(f"[DISPATCH] {utype} dispatched to incident {incident['id']}.")
            else:
                print(f"[DISPATCH] No {utype} available -> queued (incident {incident['id']}).")
        except Exception as e:
            print(f"[DISPATCH] request_dispatch failed for {utype}: {e}")

    return dispatched


def process_incident(record):
    incident_id = record.get('id')
    voice_url = record.get('voice_url')
    description = record.get('description')

    print(f"\n[AI] New incident detected: {incident_id}")

    try:
        final_text = description or ""

        # 1. Handle Audio if URL exists
        if voice_url:
            print(f"[AI] Downloading audio from {voice_url}")
            response = requests.get(voice_url)

            # Use absolute path for Windows reliability
            temp_file = os.path.abspath(f"temp_{incident_id}.m4a")

            with open(temp_file, "wb") as f:
                f.write(response.content)

            print(f"[AI] Transcribing with Whisper: {temp_file}")
            # Ensure ffmpeg is installed on your system!
            result = whisper_model.transcribe(temp_file)
            final_text = result["text"]


            # Remove file after transcription
            if os.path.exists(temp_file):
                os.remove(temp_file)

        # 2. Run your Custom AI Analysis
        print(f"[AI] Analyzing text: {final_text}")
        ai_results = predict_incident(final_text, MODELS)

        # 3. Duplicate Detection
        updated_record = {
              **record,
              "description": final_text
        }

        duplicate_result = check_duplicate_incident(updated_record)

        if duplicate_result["is_duplicate"]:
            handle_duplicate_incident(
            updated_record,
            duplicate_result["matched_incident"],
            ai_results
            )
            return

        # 4. Update Supabase with AI results, status='Pending'
        severity = ai_results.get("severity", "UNKNOWN")
        dispatch_list = ai_results.get("dispatch", [])
        dispatch_summary = ", ".join(dispatch_list)

        # Fake reports are rejected (never dispatched); everything else is Pending.
        new_status = "Rejected" if severity == "FAKE" else "Pending"

        print(f"[AI] Saving results: {severity} | Units: {dispatch_summary}")
        supabase.table("incidents").update({
            "description": final_text,
            "severity": severity,
            "incident_type": dispatch_summary,
            "status": new_status
        }).eq("id", incident_id).execute()

        # 5. Auto-dispatch one unit PER required type (multi-unit).
        if severity != "FAKE" and dispatch_list and dispatch_list != ["NONE"]:
            dispatch_units_to_incident(record, ai_results)

        print(f"[AI] SUCCESS: Incident processed.")

    except Exception as e:
        print(f"[AI] ERROR: {e}")


def are_similar(text1, text2, threshold=0.5):

    emb1 = MODELS["st_encoder"].encode(text1)
    emb2 = MODELS["st_encoder"].encode(text2)

    similarity = util.cos_sim(emb1, emb2).item()

    return similarity >= threshold, similarity


def parse_created_at(created_at):

    timestamp = created_at.replace("Z", "+00:00")

    if "." in timestamp:

        before_fraction, after_fraction = timestamp.split(".", 1)
        timezone_index = max(
            after_fraction.rfind("+"),
            after_fraction.rfind("-")
        )

        if timezone_index != -1:
            fraction = after_fraction[:timezone_index]
            timezone = after_fraction[timezone_index:]
        else:
            fraction = after_fraction
            timezone = ""

        if fraction.isdigit():
            fraction = fraction[:6].ljust(6, "0")
            timestamp = f"{before_fraction}.{fraction}{timezone}"

    return datetime.fromisoformat(timestamp)


def check_duplicate_incident(record):

    try:

        current_id = record.get("id")
        current_desc = record.get("description") or ""
        current_lat = record.get("latitude")
        current_lng = record.get("longitude")

        # =================================================
        # GET ALL INCIDENTS EXCEPT CURRENT
        # =================================================
        response = supabase.table("incidents") \
            .select("*") \
            .neq("id", current_id) \
            .eq("has_duplicate", False)\
            .execute()

        incidents = response.data
        print("\nReturned incidents:")

        for i in incidents:
            print(
                f"{i['id']} | {i['description']} | duplicate={i['has_duplicate']}"
            )

        # =================================================
        # STEP 1: LOCATION FILTER FIRST
        # =================================================
        nearby_incidents = []

        for incident in incidents:

            if (
                incident.get("latitude") is None or
                incident.get("longitude") is None
            ):
                continue

            distance = geodesic(
                (current_lat, current_lng),
                (
                    incident["latitude"],
                    incident["longitude"]
                )
            ).meters

            # 500 meter radius
            if distance <= 500:

                nearby_incidents.append(incident)

        print(
            f"[AI] Nearby incidents found: "
            f"{len(nearby_incidents)}"
        )

        # =================================================
        # STEP 2: TIME FILTER SECOND
        # =================================================
        recent_nearby_incidents = []

        for incident in nearby_incidents:

            created_at = incident.get("created_at")

            if not created_at:
                continue

            incident_time = parse_created_at(created_at)

            current_time = datetime.now(
                incident_time.tzinfo
            )

            time_diff = current_time - incident_time

            print(f"[AI] Time difference: {time_diff}")

            # 30 minute window
            if time_diff <= timedelta(minutes=30):

                recent_nearby_incidents.append(
                    incident
                )
        # =================================================
        # STEP 3: AI SIMILARITY
        # =================================================
        for incident in recent_nearby_incidents:

            similar, score = are_similar(
                current_desc,
                incident.get("description", ""),
                threshold=0.5
            )

            print(
                f"[AI] Similarity with "
                f"{incident['id']}: {score}"
            )

            if similar:

                print(
                    f"[AI] Duplicate detected "
                    f"with incident {incident['id']}"
                )

                return {
                    "is_duplicate": True,
                    "matched_incident": incident
                }

        print(
            f"[AI] NO Duplicate detected "
        )

        return {
            "is_duplicate": False,
            "matched_incident": None
        }

    except Exception as e:

        print(
            f"[AI] Duplicate check error: {e}"
        )

        return {
            "is_duplicate": False,
            "matched_incident": None
        }


SEVERITY_ORDER = {
    "LOW": 1,
    "URGENT": 2,
    "CRITICAL": 3,
    "FAKE": 0
}


def handle_duplicate_incident(current_record, matched_incident, ai_results):
    try:
        current_id = current_record["id"]
        matched_id = matched_incident["id"]
        current_severity = ai_results.get("severity")
        dispatch_summary = ", ".join(ai_results.get("dispatch", []))
        master_severity = matched_incident.get("severity")

        # Reuse or create case id
        case_id = matched_incident.get("case_id")

        if not case_id:
            case_id = f"CASE-{int(time.time())}"

            # Give the master a case id
            supabase.table("incidents").update({
            "incident_type": ", ".join(ai_results.get("dispatch", [])),
            "case_id": case_id
             }).eq("id", matched_id).execute()

        # Link the duplicate to the same case. The duplicate itself is
        # Rejected (never dispatched on its own — the master is being handled).
        supabase.table("incidents").update({
            "description": current_record["description"],
            "severity": current_severity,
            "incident_type": dispatch_summary,
            "case_id": case_id,
            "has_duplicate": True,
            "status": "Rejected"
        }).eq("id", current_id).execute()

        # If this duplicate is MORE severe than the master, upgrade the master
        # so the active response reflects the worst report. Use .get(...) so a
        # missing/unknown severity never crashes the comparison (which silently
        # prevented the upgrade before).
        cur_rank = SEVERITY_ORDER.get(current_severity, 0)
        mas_rank = SEVERITY_ORDER.get(master_severity, 0)
        if cur_rank > mas_rank:
            supabase.table("incidents").update({
                "severity": current_severity,
                "incident_type": ", ".join(ai_results.get("dispatch", []))
            }).eq("id", matched_id).execute()

            # If the master is still waiting in the dispatch queue, bump its
            # priority rank too so it gets served sooner.
            supabase.table("dispatch_queue").update({
                "severity_rank": cur_rank
            }).eq("incident_id", matched_id).execute()

            print(f"[AI] Master {matched_id} severity upgraded to {current_severity}")

        print("[AI] Duplicate linked successfully")
        return True

    except Exception as e:
        print(f"[AI] Duplicate handling error: {e}")
        return False


def start_polling():
    print("\n--- AI Worker Started ---")
    print("Watching Supabase for new incidents...")
    while True:
        try:
            response = supabase.table("incidents").select("*").eq("status", "Processing").execute()
            incidents = response.data
            if incidents:
                for incident in incidents:
                    process_incident(incident)
        except Exception as e:
            print(f"Polling error: {e}")
        time.sleep(3)

if __name__ == "__main__":
    start_polling()

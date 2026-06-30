# Poster Content — Smart Emergency Response Manager
# (Copy each block into the matching box of 70x100_Vertical_Template-2026.pptx)

================================================================
TITLE BLOCK
================================================================
Title:        Smart Emergency Response Manager (ERM)
              An AI-Driven Platform for Intelligent Emergency Dispatch
By:           [Your student names]
Supervised by: Dr. [name] , TA. [name]
Department:   [your department]
Faculty of Computer and Information Sciences – Ain Shams University

================================================================
INTRODUCTION
================================================================
Emergency response is a time-critical public-safety task where every second
directly affects survival and damage. Traditional systems (Public Safety
Answering Points) still rely on phone calls and manual coordination between
callers, dispatchers, and response units. Under heavy load or large-scale
events this leads to delayed responses, fragmented and duplicated information,
miscommunication, and inconsistent decisions driven by human fatigue and
stress.

The rise of Smart City and Next-Generation 911 initiatives has pushed
emergency management toward digital, AI-assisted platforms that combine mobile
applications, cloud services, geospatial analysis, and Artificial Intelligence
to speed up decisions and improve situational awareness.

The Smart Emergency Response Manager (ERM) follows this direction as an
AI-driven platform connecting Citizens, Response Units, and Administrators in a
single ecosystem. Citizens report emergencies by text or voice, and the system
automatically attaches their GPS location and timestamp. The AI then
transcribes voice reports, filters out fake reports, classifies the incident
type and severity, and detects duplicate reports of the same event. Valid
incidents are prioritized and the nearest suitable unit is dispatched
automatically, with real-time notifications and live tracking for the citizen.

The goal is to reduce response time, automate triage, optimize the use of
emergency resources, and minimize reliance on manual judgment — transforming a
largely manual and reactive process into a proactive, data-driven response
framework.

================================================================
METHODOLOGY
================================================================
The project follows a modular, layered design that separates the user
interface, the processing/decision logic, and the data storage, allowing each
part to be developed, tested, and scaled independently.

Each emergency report is handled through a sequential AI processing pipeline:
  1. The report is received with the citizen's location and timestamp.
  2. Voice reports are converted to text.
  3. The text is screened for authenticity (fake-report filtering).
  4. The incident is classified by type and severity.
  5. It is compared against recent reports to detect duplicates.
  6. Valid incidents are placed in a priority queue.
  7. The most suitable available unit is selected and dispatched.
  8. All parties are notified, with feedback collected after resolution.

Dispatching follows a two-step decision method: incidents are first ordered by
urgency (severity, then waiting time), and a unit is then matched to each
incident by geographic proximity. When a unit becomes free, it is automatically
reassigned to the highest-priority waiting incident.

The AI models were trained on a labeled dataset of emergency descriptions and
integrated into the system as an always-on processing service.

(Note: the specific technologies — Flutter, Supabase, PostgreSQL functions/
triggers, etc. — belong in the Tools / System Architecture section, not here.)

================================================================
KEY ALGORITHMS
================================================================
• Severity Classification: TF-IDF features + multiclass Logistic Regression
  → Low / Urgent / Critical.
• Unit-Type Prediction: three binary Logistic Regression classifiers over
  768-dim Sentence-Transformer (all-mpnet-base-v2) embeddings → Police,
  Ambulance, Fire.
• Fake-Report Detection: a binary classifier over the same semantic
  embeddings; flagged reports are rejected before dispatch.
• Duplicate Detection: three-stage filter — geographic proximity (≤ 500 m,
  geodesic distance), temporal proximity (≤ 30 min), and semantic similarity
  (cosine ≥ 0.5). Duplicates are merged under one case.
• Smart Dispatch: nearest available unit selected via the Haversine
  great-circle distance; ETA = road-adjusted distance ÷ average city speed.
• Priority Queue: ordered by severity (Critical > Urgent > Low), with a
  First-In-First-Out tie-break on arrival time.
• Automatic Re-dispatch: a database trigger fires the moment a unit becomes
  available, assigning it the highest-priority waiting incident.

================================================================
RESULTS / FINDINGS
================================================================
(Format: numbered category header in BOLD, with sub-bullets — like the sample.)

1- The AI triage pipeline performed accurately:
   • Severity classification (Low / Urgent / Critical) achieved high accuracy
     on the test set.
   • Unit-type prediction correctly identified the required services
     (Police / Ambulance / Fire).
   • OpenAI Whisper reliably transcribed voice SOS reports, even under noisy
     conditions (sirens, traffic).

2- Fake and duplicate filtering improved resource efficiency:
   • The fake-report detector prevented unnecessary dispatches to false alarms.
   • Duplicate detection merged multiple reports of the same event into a
     single case, avoiding redundant deployments.

3- Smart dispatching reduced response time:
   • The nearest available unit was selected automatically using geospatial
     (Haversine) distance.
   • Severity-based prioritization ensured critical incidents were served first.
   • Freed units were automatically reassigned to the highest-priority waiting
     incident.

4- The system demonstrated scalability and reliability:
   • One global queue and a centralized database coordinated all stations
     through a single source of truth.
   • Race-free dispatching prevented double-assignment of units under
     concurrent load.

5- Real-time communication enhanced the user experience:
   • Citizens received push notifications and live tracking of the responding
     unit.
   • Citizens could rate the service and leave feedback after resolution.

Table 1: Model Performance (test set, n = 850)
+----------------------+----------+-----------+--------+----------+
| Model / Task         | Accuracy | Precision | Recall | F1-score |
+----------------------+----------+-----------+--------+----------+
| Severity (4-class)   |  90.6%   |  0.906    | 0.906  |  0.906   |
| Fire needed          |  98.6%   |  0.980    | 0.973  |  0.976   |
| Ambulance needed     |  96.4%   |  0.972    | 0.944  |  0.958   |
| Police needed        |  95.6%   |  0.962    | 0.968  |  0.965   |
+----------------------+----------+-----------+--------+----------+
(Severity = weighted avg over Critical/Urgent/Low/Fake; unit types = "Yes" class.)

Optional detailed table — per severity class:
+------------+-----------+--------+------+---------+
| Class      | Precision | Recall |  F1  | Support |
+------------+-----------+--------+------+---------+
| Critical   |   0.922   | 0.896  | 0.909|   212   |
| Urgent     |   0.911   | 0.899  | 0.905|   318   |
| Low        |   0.897   | 0.906  | 0.901|   202   |
| Fake       |   0.881   | 0.941  | 0.910|   118   |
+------------+-----------+--------+------+---------+

================================================================
CONCLUSION
================================================================
The Smart Emergency Response Manager delivers a complete, end-to-end
intelligent workflow that existing systems lack — unifying multi-modal
incident reporting, AI-based triage (fake detection, severity, unit type),
duplicate handling, severity-based prioritization, geospatial smart
dispatching, and real-time notifications in a single platform.

By automating these stages, the system reduces emergency response times and
improves resource utilization, turning a manual and reactive process into a
proactive, data-driven response framework.

Future work: integrate a live road-routing API for exact ETAs, expand
severity to a four-level scale, add coverage-aware dispatching, and deploy
the AI worker to the cloud for 24/7 availability.

================================================================
REFERENCES
================================================================
1. Radford, A., et al. (2023). Robust Speech Recognition via Large-Scale Weak
   Supervision (Whisper). OpenAI.
2. Reimers, N., & Gurevych, I. (2019). Sentence-BERT: Sentence Embeddings using
   Siamese BERT-Networks. EMNLP.
3. Pedregosa, F., et al. (2011). Scikit-learn: Machine Learning in Python.
   Journal of Machine Learning Research, 12, 2825–2830.
4. Supabase Documentation. https://supabase.com/docs

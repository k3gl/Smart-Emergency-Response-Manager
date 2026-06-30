import pandas as pd
import numpy as np
from sentence_transformers import SentenceTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.multioutput import MultiOutputClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import warnings

warnings.filterwarnings("ignore")

# 1. LOAD DATA
print("--- Step 1: Loading Dataset ---")
# Update this path if your Excel file is moved
excel_path = "C:/Users/khaled/Downloads/gp/wahd.xlsx" 
try:
    df = pd.read_excel(excel_path, header=1)
except Exception as e:
    print(f"Error: Could not find Excel file at {excel_path}. Please check the path.")
    exit()

# Clean columns
df.columns = df.columns.astype(str).str.strip().str.lower()
df = df.rename(columns={
    "boolean fire": "fire",
    "boolean ambulance": "ambulance",
    "boolean police": "police"
})
df = df.dropna(subset=["description", "severity"]).copy()

# 2. ENCODING (The AI's Ears)
print("--- Step 2: Encoding Text (This may take a minute) ---")
model = SentenceTransformer('sentence-transformers/all-mpnet-base-v2')
X = model.encode(df["description"].tolist(), show_progress_bar=True)

# Labels
y_sev = df["severity"].str.lower().str.strip()
y_units = df[["fire", "ambulance", "police"]]

# 3. TRAINING (The AI's Brain)
print("--- Step 3: Training Models ---")
X_train, X_test, y_sev_train, y_sev_test, y_unit_train, y_unit_test = train_test_split(
    X, y_sev, y_units, test_size=0.2, random_state=42
)

# Severity Model
severity_model = LogisticRegression(max_iter=1000)
severity_model.fit(X_train, y_sev_train)

# Unit Model
unit_model = MultiOutputClassifier(LogisticRegression(max_iter=1000))
unit_model.fit(X_train, y_unit_train)

print("\n--- Training Complete! ---")

# 4. TEST FUNCTION
def test_sos(text):
    emb = model.encode([text])
    sev = severity_model.predict(emb)[0]
    units_binary = unit_model.predict(emb)[0]
    
    unit_names = ["FIRE", "AMBULANCE", "POLICE"]
    dispatched = [unit_names[i] for i in range(3) if units_binary[i] == 1]
    
    print(f"\nSOS Message: {text}")
    print(f"AI Result -> Severity: {sev.upper()}")
    print(f"AI Result -> Units: {dispatched if dispatched else 'NONE'}")

# --- RUN SAMPLES ---
test_sos("There is a fire in my kitchen!")
test_sos("A car hit a pedestrian and they are bleeding.")
test_sos("I lost my keys and I'm bored.")

# -*- coding: utf-8 -*-
"""
Model evaluation for the Emergency Response Manager.

Reproduces the same train/test split used in train_and_test.py, then reports
precision / recall / F1 / accuracy and the confusion matrix for:
  * Severity classification (multiclass: LOW / URGENT / CRITICAL)
  * Unit-type classification (binary: FIRE, AMBULANCE, POLICE)

Confusion-matrix images are saved as PNG files for the report.

Run:  python evaluate.py
"""

import pandas as pd
import numpy as np
from sentence_transformers import SentenceTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.multioutput import MultiOutputClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    accuracy_score,
    ConfusionMatrixDisplay,
)
import matplotlib.pyplot as plt
import warnings

warnings.filterwarnings("ignore")

# --- 1. Load dataset (same file as training) --------------------------------
EXCEL_PATH = "C:/Users/khaled/Downloads/gp/wahd.xlsx"
print("--- Loading dataset ---")
df = pd.read_excel(EXCEL_PATH, header=1)
df.columns = df.columns.astype(str).str.strip().str.lower()
df = df.rename(columns={
    "boolean fire": "fire",
    "boolean ambulance": "ambulance",
    "boolean police": "police",
})
df = df.dropna(subset=["description", "severity"]).copy()
print(f"Samples: {len(df)}")

# --- 2. Encode text + labels ------------------------------------------------
print("--- Encoding descriptions (all-mpnet-base-v2) ---")
encoder = SentenceTransformer("all-mpnet-base-v2")
X = encoder.encode(df["description"].tolist(), show_progress_bar=True)

y_sev = df["severity"].str.upper().str.strip()
y_units = df[["fire", "ambulance", "police"]].astype(int)

# Same split as training (random_state=42, 20% test) so results are comparable.
X_tr, X_te, ys_tr, ys_te, yu_tr, yu_te = train_test_split(
    X, y_sev, y_units, test_size=0.2, random_state=42
)

# --- 3. Train ---------------------------------------------------------------
print("--- Training models ---")
sev_model = LogisticRegression(max_iter=1000).fit(X_tr, ys_tr)
unit_model = MultiOutputClassifier(LogisticRegression(max_iter=1000)).fit(X_tr, yu_tr)

# --- 4. Evaluate severity ---------------------------------------------------
print("\n" + "=" * 60)
print("SEVERITY CLASSIFICATION")
print("=" * 60)
ys_pred = sev_model.predict(X_te)
print(f"Accuracy: {accuracy_score(ys_te, ys_pred):.3f}\n")
print(classification_report(ys_te, ys_pred, digits=3))

labels = sorted(y_sev.unique())
cm = confusion_matrix(ys_te, ys_pred, labels=labels)
print("Confusion matrix (rows = actual, cols = predicted):")
print(pd.DataFrame(cm, index=labels, columns=labels))

ConfusionMatrixDisplay(cm, display_labels=labels).plot(cmap="Blues", colorbar=False)
plt.title("Severity Confusion Matrix")
plt.tight_layout()
plt.savefig("cm_severity.png", dpi=150)
print("Saved: cm_severity.png")

# --- 5. Evaluate unit types (one report per type) ---------------------------
print("\n" + "=" * 60)
print("UNIT-TYPE CLASSIFICATION")
print("=" * 60)
yu_pred = unit_model.predict(X_te)
unit_names = ["FIRE", "AMBULANCE", "POLICE"]
for i, name in enumerate(unit_names):
    print(f"\n--- {name} ---")
    actual = yu_te.iloc[:, i].values
    pred = yu_pred[:, i]
    print(f"Accuracy: {accuracy_score(actual, pred):.3f}")
    print(classification_report(actual, pred, target_names=["No", "Yes"], digits=3))

print("\nDone. Use the printed precision/recall/F1 tables and the PNG "
      "confusion matrices in your results chapter.")

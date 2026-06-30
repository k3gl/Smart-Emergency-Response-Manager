# -*- coding: utf-8 -*-
import os
import re
import joblib
import numpy as np
from sentence_transformers import SentenceTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer

# Automatically find the path to the models folder
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(BASE_DIR, "models")

def get_model_path(filename):
    return os.path.join(MODELS_DIR, filename)

FAKE_DETECTOR_PATH = get_model_path("fake_detector.pkl")
SEV_MODEL_PATH     = get_model_path("severity_model.pkl")
SEV_VECT_PATH      = get_model_path("severity_vectorizor.pkl")
AMB_MODEL_PATH     = get_model_path("amb_model.pkl")
FIRE_MODEL_PATH    = get_model_path("fire_model.pkl")
POL_MODEL_PATH     = get_model_path("pol_model.pkl")

def clean_text(text):
    text = str(text).lower()
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"[^a-z0-9\s]", "", text)
    return text.strip()

def load_models():
    print("--- Loading AI Brain Models ---")
    models = {}
    models["st_encoder"] = SentenceTransformer("all-mpnet-base-v2")
    
    try:
        models["fake_detector"] = joblib.load(FAKE_DETECTOR_PATH)
        models["severity_model"] = joblib.load(SEV_MODEL_PATH)
        models["severity_vectorizer"] = joblib.load(SEV_VECT_PATH)
        models["amb_model"] = joblib.load(AMB_MODEL_PATH)
        models["fire_model"] = joblib.load(FIRE_MODEL_PATH)
        models["pol_model"] = joblib.load(POL_MODEL_PATH)
        print("--- All Models Loaded Successfully ---")
    except Exception as e:
        print(f"CRITICAL ERROR: Could not load model files. Check the 'models' folder. Error: {e}")
    
    return models

MODELS = load_models()

SEVERITY_MAP = {0: "LOW", 1: "URGENT", 2: "CRITICAL"}

def predict_incident(text: str, models: dict) -> dict:
    text_clean = clean_text(text)
    
    # 1. Fake Detection
    fake_emb = models["st_encoder"].encode([text_clean])
    fake_probs = models["fake_detector"].predict_proba(fake_emb)[0]
    fake_conf = float(fake_probs[1])
    
    if fake_conf >= 0.5:
        return {"Fake": True, "severity": "FAKE", "dispatch": ["NONE"]}

    # 2. Severity (TF-IDF)
    sev_vec = models["severity_vectorizer"].transform([text_clean])
    sev_probs = models["severity_model"].predict_proba(sev_vec)[0]
    sev_idx = int(np.argmax(sev_probs))
    severity = SEVERITY_MAP[sev_idx]

    # 3. Dispatch (Sentence Transformer)
    # Using the same embedding for all 3 units to save time
    emb = models["st_encoder"].encode([text_clean])
    
    dispatch = []
    if float(models["amb_model"].predict_proba(emb)[0][1]) >= 0.5:
        dispatch.append("AMBULANCE")
    if float(models["fire_model"].predict_proba(emb)[0][1]) >= 0.5:
        dispatch.append("FIRE")
    if float(models["pol_model"].predict_proba(emb)[0][1]) >= 0.5:
        dispatch.append("POLICE")

    return {
        "severity": severity,
        "dispatch": dispatch if dispatch else ["NONE"]
    }

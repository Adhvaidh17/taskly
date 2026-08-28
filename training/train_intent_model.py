from __future__ import annotations

import base64
import json
import math
import random
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from scipy.sparse import csr_matrix
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
from sklearn.model_selection import train_test_split

SEED = 20260805
random.seed(SEED)
np.random.seed(SEED)
DIM = 8192

NAMES = ["mathi", "arun", "priya", "kumar", "rahul", "anu", "bro", "machi", "anna", "sir"]
OBJECTS = [
    "the report", "invoice", "quotation", "milk", "two milk packets", "client files", "presentation",
    "agreement", "ledger", "campaign report", "design draft", "meeting notes", "payment", "groceries",
    "the document", "customer list", "website backup", "proposal", "purchase order", "attendance sheet",
]
TIMES_EN = ["", "today", "tomorrow", "by 5 pm", "at 10 am", "before lunch", "this evening", "on Friday", "by end of day"]
TIMES_TA = ["", "innaiku", "nalaiku", "nalaiku 5 manikku", "evening kulla", "10 manikku", "Friday kulla"]
TIMES_HI = ["", "aaj", "kal", "kal 5 baje", "shaam tak", "10 baje", "Friday tak"]

ACTIONS = [
    ("send", "anupidu", "bhej dena"),
    ("submit", "submit pannu", "jama kar dena"),
    ("call", "call pannu", "call kar dena"),
    ("buy", "vangidu", "kharid lena"),
    ("collect", "eduthu va", "le aana"),
    ("review", "review pannu", "review karna"),
    ("check", "check pannu", "check karna"),
    ("update", "update pannu", "update kar dena"),
    ("upload", "upload pannu", "upload kar dena"),
    ("pay", "pay pannu", "payment kar dena"),
    ("schedule", "schedule pannu", "schedule kar dena"),
    ("prepare", "prepare pannu", "prepare kar dena"),
    ("complete", "mudichidu", "complete kar dena"),
    ("share", "share pannu", "share kar dena"),
    ("notarize", "notarize pannu", "notarize kar dena"),
    ("reconcile", "reconcile pannu", "reconcile kar dena"),
]

POS_EXTRAS = [
    "remind me to call Mathi tomorrow at 8",
    "rember me tmrw 8 call Mathi",
    "I'll finish the quotation before lunch",
    "I will send the report tomorrow",
    "let me update the client by evening",
    "hey bro get me the milk today at 5",
    "get the milk from Kumar today at 5",
    "get me milk from supermarket today at 5",
    "please reconcile the ledger",
    "please notarize the agreement",
    "mark August performance report done",
    "set the invoice task to completed",
    "envía el informe mañana",
    "envoie le rapport demain",
    "envie o relatório amanhã",
    "schick den bericht morgen",
    "kirim laporan besok",
    "invia il rapporto domani",
    "明天发送报告",
    "明日レポートを送って",
    "أرسل التقرير غدًا",
    "отправь отчет завтра",
    "Mathi தயவு செய்து invoice அனுப்பு நாளை 5 மணிக்கு",
    "कल 5 बजे रिपोर्ट भेज देना",
    "நாளைக்கு 5 மணிக்கு ரிப்போர்ட் அனுப்பு",
]

NEG_EXTRAS = [
    "hello bro", "okay thanks", "Mathi is in the office", "Lunch was good today",
    "I finished the quotation yesterday", "When will you send the invoice?", "Did you send the report?",
    "what is the deadline", "why was the invoice rejected", "how do I buy milk online", "can milk go bad",
    "the report is ready", "I like calling clients", "we are reviewing the proposal", "the payment was sent",
    "tomorrow is a holiday", "5 pm is too late", "Kumar brought milk", "I need information about the report",
    "please explain the invoice", "tell me what happened", "who sent the document", "where is the client file",
    "kal meeting hai", "report bhej diya", "invoice anupiten", "nalaiku leave", "seri bro", "haan theek hai",
    "நாளை விடுமுறை", "ரிப்போர்ட் அனுப்பிவிட்டேன்", "कल छुट्टी है", "रिपोर्ट भेज दिया",
]


def clean(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"https?://\S+", " url ", text)
    text = re.sub(r"\s+", " ", text)
    return text


def fnv1a(data: str) -> int:
    h = 2166136261
    for b in data.encode("utf-8"):
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def features(text: str) -> dict[int, float]:
    text = f"^{clean(text)}$"
    out: dict[int, float] = {}
    # Character n-grams are robust to spelling errors and transliteration.
    for n in (3, 4, 5):
        for i in range(max(0, len(text) - n + 1)):
            token = "c" + text[i:i+n]
            h = fnv1a(token)
            idx = h % DIM
            sign = 1.0 if (h & 0x80000000) == 0 else -1.0
            out[idx] = out.get(idx, 0.0) + sign
    words = re.findall(r"[\w']+", text, flags=re.UNICODE)
    for n in (1, 2):
        for i in range(max(0, len(words) - n + 1)):
            token = "w" + "_".join(words[i:i+n])
            h = fnv1a(token)
            idx = h % DIM
            sign = 1.0 if (h & 0x80000000) == 0 else -1.0
            out[idx] = out.get(idx, 0.0) + 1.6 * sign
    norm = math.sqrt(sum(v*v for v in out.values())) or 1.0
    return {k: v / norm for k, v in out.items()}


def typo(text: str) -> str:
    if len(text) < 7 or random.random() > 0.35:
        return text
    chars = list(text)
    candidates = [i for i, c in enumerate(chars) if c.isalpha() and i > 0]
    if not candidates:
        return text
    i = random.choice(candidates)
    op = random.choice(["drop", "swap", "repeat"])
    if op == "drop":
        del chars[i]
    elif op == "swap" and i + 1 < len(chars):
        chars[i], chars[i + 1] = chars[i + 1], chars[i]
    else:
        chars.insert(i, chars[i])
    return "".join(chars)


def generate() -> tuple[list[str], list[int]]:
    positives: list[str] = list(POS_EXTRAS)
    negatives: list[str] = list(NEG_EXTRAS)

    en_prefixes = ["please", "pls", "kindly", "hey bro", "", "can you", "could you", "make sure to"]
    ta_prefixes = ["", "dei", "bro", "konjam", "please", "machi"]
    hi_prefixes = ["", "arey", "bhai", "zara", "please", "yaar"]

    for _ in range(8500):
        action_en, action_ta, action_hi = random.choice(ACTIONS)
        obj = random.choice(OBJECTS)
        name = random.choice(NAMES)
        lang = random.choice(["en", "en", "ta", "hi"])
        if lang == "en":
            prefix = random.choice(en_prefixes)
            time = random.choice(TIMES_EN)
            patterns = [
                f"{prefix} {action_en} {obj} {time}",
                f"{name} {action_en} {obj} {time}",
                f"{prefix} {action_en} me {obj} {time}",
                f"{action_en} {obj} {time}",
            ]
        elif lang == "ta":
            prefix = random.choice(ta_prefixes)
            time = random.choice(TIMES_TA)
            patterns = [
                f"{name} {time} {obj} {action_ta}",
                f"{prefix} {obj} {action_ta} {time}",
                f"{obj} {time} {action_ta}",
            ]
        else:
            prefix = random.choice(hi_prefixes)
            time = random.choice(TIMES_HI)
            patterns = [
                f"{name} {time} {obj} {action_hi}",
                f"{prefix} {obj} {action_hi} {time}",
                f"{obj} {time} {action_hi}",
            ]
        text = re.sub(r"\s+", " ", random.choice(patterns)).strip()
        positives.append(typo(text))

    statements = [
        "I {past} {obj} yesterday", "we {past} {obj}", "{name} {past} {obj}",
        "the {noun} is ready", "the {noun} was good", "I am {gerund} {obj}",
        "when will you {action} {obj}?", "did you {action} {obj}?", "how can I {action} {obj}?",
        "why did {name} {action} {obj}?", "what about {obj}?", "{time} is fine", "I need details about {obj}",
    ]
    pasts = ["sent", "submitted", "called", "bought", "collected", "reviewed", "updated", "completed"]
    nouns = ["report", "invoice", "meeting", "design", "food", "milk", "client"]
    gerunds = ["sending", "reviewing", "checking", "buying", "discussing"]
    for _ in range(8500):
        action = random.choice(ACTIONS)[0]
        obj = random.choice(OBJECTS)
        txt = random.choice(statements).format(
            past=random.choice(pasts), obj=obj, name=random.choice(NAMES), noun=random.choice(nouns),
            gerund=random.choice(gerunds), action=action, time=random.choice(TIMES_EN[1:]),
        )
        negatives.append(typo(txt))

    X = positives + negatives
    y = [1] * len(positives) + [0] * len(negatives)
    return X, y


def matrix(texts: Iterable[str]) -> csr_matrix:
    rows, cols, vals = [], [], []
    for r, text in enumerate(texts):
        for c, v in features(text).items():
            rows.append(r); cols.append(c); vals.append(v)
    return csr_matrix((vals, (rows, cols)), shape=(len(list(texts)) if not isinstance(texts, list) else len(texts), DIM), dtype=np.float32)


def main() -> None:
    X_text, y = generate()
    X_train_text, X_test_text, y_train, y_test = train_test_split(
        X_text, y, test_size=0.18, random_state=SEED, stratify=y
    )
    X_train = matrix(X_train_text)
    X_test = matrix(X_test_text)
    model = LogisticRegression(C=3.0, max_iter=800, class_weight={0: 1.05, 1: 1.0}, random_state=SEED)
    model.fit(X_train, y_train)
    probs = model.predict_proba(X_test)[:, 1]
    pred = (probs >= 0.5).astype(int)
    report = classification_report(y_test, pred, digits=4)
    cm = confusion_matrix(y_test, pred).tolist()
    auc = float(roc_auc_score(y_test, probs))

    weights = model.coef_[0].astype(np.float32)
    max_abs = float(np.max(np.abs(weights))) or 1.0
    scale = max_abs / 32767.0
    quant = np.round(weights / scale).astype("<i2")
    packed = quant.tobytes(order="C")
    b64 = base64.b64encode(packed).decode("ascii")

    package_root = Path(__file__).resolve().parents[1]
    function_dir = package_root / "supabase" / "functions" / "analyse-task-message"
    pack_dir = package_root / "models" / "taskly_intent_v30"
    function_dir.mkdir(parents=True, exist_ok=True)
    pack_dir.mkdir(parents=True, exist_ok=True)
    out = function_dir / "intent_model_weights.ts"
    out.write_text(
        "// Generated by training/train_intent_model.py. Do not hand-edit.\n"
        f"export const INTENT_MODEL_DIM = {DIM};\n"
        f"export const INTENT_MODEL_BIAS = {float(model.intercept_[0]):.10f};\n"
        f"export const INTENT_MODEL_SCALE = {scale:.12g};\n"
        f"export const INTENT_MODEL_BASE64 = `{b64}`;\n"
        f"export const INTENT_MODEL_METADATA = {json.dumps({'version':'taskly-intent-charhash-v1','seed':SEED,'train_examples':len(X_train_text),'test_examples':len(X_test_text),'auc':round(auc,6),'confusion_matrix':cm}, separators=(',',':'))} as const;\n",
        encoding="utf-8",
    )
    metadata = {
        "version": "taskly-intent-charhash-v1",
        "seed": SEED,
        "dimension": DIM,
        "quantization": "signed_int16",
        "scale": scale,
        "bias": float(model.intercept_[0]),
        "train_examples": len(X_train_text),
        "test_examples": len(X_test_text),
        "auc": round(auc, 6),
        "confusion_matrix": cm,
        "features": {"character_ngrams": [3, 4, 5], "word_ngrams": [1, 2], "hash": "FNV-1a"},
    }
    (pack_dir / "taskly_intent_v30.int16.bin").write_bytes(packed)
    (pack_dir / "model.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    validation = pack_dir / "SYNTHETIC_HOLDOUT_VALIDATION.txt"
    validation.write_text(
        f"Taskly intent model synthetic holdout validation\nAUC: {auc:.6f}\nConfusion matrix: {cm}\n\n{report}\n",
        encoding="utf-8",
    )
    print(validation.read_text())


if __name__ == "__main__":
    main()

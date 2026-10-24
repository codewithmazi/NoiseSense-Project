"""M7: how well does the on-device noise-source classifier work?"""

import csv
import json
import sys
import wave
from pathlib import Path

import numpy as np
from ai_edge_litert.interpreter import Interpreter
from scipy.signal import resample_poly

APP = Path(__file__).resolve().parents[2] / "noisesense-app" / "assets" / "models"
SOURCES = ["road_traffic", "speech", "construction", "other"]
ESC50_TO_SOURCE = {
    "car_horn": "road_traffic", "engine": "road_traffic", "siren": "road_traffic",
    "chainsaw": "construction", "hand_saw": "construction",
    "laughing": "speech", "crying_baby": "speech",
}
FRAME = 15600


def load_model():
    it = Interpreter(model_path=str(APP / "yamnet.tflite"))
    it.allocate_tensors()
    labels = (APP / "yamnet_labels.txt").read_text().splitlines()
    mapping = json.loads((APP / "source_categories.json").read_text())
    idx = {c: [labels.index(l) for l in ls] for c, ls in mapping["categories"].items()}
    global SILENCE
    SILENCE = labels.index("Silence")
    return it, idx


SILENCE = None  # index of YAMNet's "Silence" label, set in main()


def frame_category_scores(it, idx, path):
    """Per-frame category scores (frames x 4)."""
    with wave.open(str(path)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
        if w.getnchannels() > 1:
            x = x.reshape(-1, w.getnchannels()).mean(1)
        x = resample_poly(x, 16000, w.getframerate()).astype(np.float32)
    i_in = it.get_input_details()[0]["index"]
    i_out = it.get_output_details()[0]["index"]
    rows = []
    for start in range(0, max(1, len(x) - FRAME + 1), FRAME):
        f = np.zeros(FRAME, np.float32)
        seg = x[start:start + FRAME]
        f[: len(seg)] = seg
        it.set_tensor(i_in, f)
        it.invoke()
        s = it.get_tensor(i_out)[0]
        rows.append([max(s[j] for j in idx[c]) for c in SOURCES[:3]] + [s[SILENCE]])
    return np.array(rows)


# A frame counts as silent when the model's "Silence" score is at least this.
SILENT_AT = 0.3


def decide(frames, rule, threshold):
    silence = frames[:, 3]
    frames = frames[:, :3]
    if rule == "active":
        # "mean" over non-silent frames only.
        active = frames[silence < SILENT_AT]
        if len(active) == 0:
            return "other"
        frames = active
        rule = "mean"
    if rule == "mean":
        m = frames.mean(0)
        k = int(m.argmax())
        return SOURCES[k] if m[k] >= threshold else "other"
    best = frames.argmax(1)
    voted = [SOURCES[b] for b, row in zip(best, frames) if row[b] >= threshold]
    if not voted:
        return "other"
    return max(set(voted), key=voted.count)


def metrics(truth, pred):
    cm = {t: {p: 0 for p in SOURCES} for t in SOURCES}
    for t, p in zip(truth, pred):
        cm[t][p] += 1
    per = {}
    for c in SOURCES:
        tp = cm[c][c]
        fp = sum(cm[t][c] for t in SOURCES) - tp
        fn = sum(cm[c].values()) - tp
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        per[c] = (prec, rec, f1, tp + fn)
    macro = float(np.mean([per[c][2] for c in SOURCES]))
    return cm, per, macro


def main(esc_root, out_dir):
    esc_root, out_dir = Path(esc_root), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    it, idx = load_model()
    meta = list(csv.DictReader(open(esc_root / "meta" / "esc50.csv")))
    clips = []
    for i, row in enumerate(meta):
        frames = frame_category_scores(it, idx, esc_root / "audio" / row["filename"])
        clips.append((int(row["fold"]), ESC50_TO_SOURCE.get(row["category"], "other"), frames))
        if i % 250 == 0:
            print(f"  scored {i}/{len(meta)} clips", flush=True)
    tune = [c for c in clips if c[0] <= 3]
    test = [c for c in clips if c[0] >= 4]

    grid = [round(t, 2) for t in np.arange(0.05, 0.61, 0.05)]
    report = ["M7 classifier evaluation (ESC-50; tuned on folds 1-3, tested on 4-5)\n"]
    for rule in ("mean", "vote", "active"):
        scores = {t: metrics([c[1] for c in tune], [decide(c[2], rule, t) for c in tune])[2] for t in grid}
        best_t = max(scores, key=scores.get)
        shipped = metrics([c[1] for c in test], [decide(c[2], rule, 0.2) for c in test])[2]
        report.append(f"Rule '{rule}': threshold chosen on tuning folds = {best_t} "
                      f"(tuning macro-F1 {scores[best_t]:.3f})")
        # Both matrices are printed and labelled.
        for label, t in ((f"TUNED threshold {best_t}", best_t), ("SHIPPED threshold 0.2", 0.2)):
            cm, per, macro = metrics([c[1] for c in test], [decide(c[2], rule, t) for c in test])
            report.append(f"  [{label}]  TEST macro-F1 {macro:.3f}")
            report.append("  confusion matrix, rows = truth, columns = predicted")
            report.append("  " + " " * 14 + "".join(f"{p[:12]:>13}" for p in SOURCES))
            for tr in SOURCES:
                report.append(f"  {tr[:12]:<14}" + "".join(f"{cm[tr][p]:>13}" for p in SOURCES))
            report.append("  class          precision  recall    F1   support")
            for c in SOURCES:
                p, r, f, n = per[c]
                report.append(f"  {c:<14} {p:9.2f} {r:7.2f} {f:6.2f} {n:8d}")
        report.append("")
    text = "\n".join(report)
    print(text)
    (out_dir / "m7_results.txt").write_text(text)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

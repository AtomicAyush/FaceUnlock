# The face-embedding model

FaceUnlock recognizes a face by turning it into a vector (an "embedding") and
comparing vectors. Apple's Vision framework finds the face and its landmarks, but
it does not produce a recognition embedding, so that one piece comes from an
open-source model that runs fully on-device via Core ML.

The model is the **only** third-party artifact in this project. It is a data file
compiled into the app bundle, not a program that runs on its own. It is not
downloaded automatically — you fetch it deliberately, once, and verify its
checksum. Nothing here contacts the network at build time or at run time.

Until a model is placed at `Model/FaceEmbedding.mlpackage`, the app builds and
runs, detects faces, and does nothing — exactly the v1 behavior.

## Pick one model

### Option A — OpenCV SFace  (recommended)

- **License:** Apache-2.0 — unambiguous, fine for personal use.
- **Embedding:** 128 numbers. **Size:** ~38.7 MB.
- **Why:** clean license, small, more than accurate enough for "is this me,
  not a photo of me." This is the default.
- **File:** `face_recognition_sface_2021dec.onnx`
- **Download:** `https://huggingface.co/opencv/face_recognition_sface/resolve/main/face_recognition_sface_2021dec.onnx`
- **Mirror:** `https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx`
- **Expected SHA-256:**
  `0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79`

Verify after download and refuse to proceed on a mismatch:

```bash
shasum -a 256 face_recognition_sface_2021dec.onnx
# must print the hash above
```

### Option B — InsightFace w600k_r50  (higher accuracy, license caveat)

- **License:** code MIT, but the **pretrained weights are "non-commercial
  research only."** Fine for a personal tool, but know the terms.
- **Embedding:** 512 numbers. **Size:** ~174 MB.
- **File:** `w600k_r50.onnx` (from the official `buffalo_l` pack).
- Only choose this if you want the extra accuracy and accept the weights' terms.
  It is a different pipeline from A (different embedding width and thresholds),
  not a drop-in swap.

## Convert to Core ML (offline, throwaway environment)

`coremltools` is not installed on this Mac, so the conversion uses a disposable
Python virtual environment. Nothing from it ships in the app — only the compiled
`.mlmodelc` does.

```bash
cd ~/code/FaceUnlock
python3 -m venv Model/.venv
source Model/.venv/bin/activate
pip install --upgrade pip
# Let the resolver pick a torch that coremltools accepts:
pip install coremltools onnx onnx2torch torch
```

Then convert (SFace shown; the exact preprocessing values are baked into the
Core ML input so the Swift side just passes the aligned 112×112 image):

```bash
python scripts/convert_model.py \
    --onnx face_recognition_sface_2021dec.onnx \
    --out Model/FaceEmbedding.mlpackage
```

`scripts/convert_model.py` will be added alongside this doc when you approve a
model; it loads the ONNX graph, traces it to Core ML, bakes in the model's
normalization, and prints a numerical check comparing the ONNX and Core ML
outputs on a sample image (they must agree to a few decimals).

## After conversion

```bash
./scripts/build_app.sh     # compiles the model into FaceUnlock.app
open build/FaceUnlock.app  # then use "Enroll Face…" from the menu bar
```

---

**Status:** no model is downloaded yet. This file describes exactly what will be
fetched so it can be approved first.

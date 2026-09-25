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
pip install coremltools onnx onnx2torch onnxruntime numpy pillow
# coremltools 9 is tested against torch 2.7; the latest torch breaks onnx2torch's
# torchvision import, so pin the matched pair:
pip install "torch==2.7.0" "torchvision==0.22.0"
```

Then convert with `scripts/convert_model.py`:

```bash
python scripts/convert_model.py \
    --onnx Model/face_recognition_sface_2021dec.onnx \
    --out Model/FaceEmbedding.mlpackage
```

It loads the ONNX via onnx2torch, traces it, converts to a Core ML **ML Program**
(FP16), and runs a numerical self-check: it feeds the same input to onnxruntime
and to the converted model and fails if their 128-D outputs disagree.

**What the converter bakes in (verified against the ONNX graph and OpenCV source):**

- **Normalization is inside the model.** The ONNX graph's first two ops are
  `(x − 127.5) × 0.0078125` (i.e. `(x − 127.5) / 128`), so the Core ML image input
  takes **raw 0–255 pixels** (`scale=1, bias=0`) and the network normalizes itself.
- **Channel order is RGB.** OpenCV's `FaceRecognizerSF::feature` calls
  `blobFromImage(..., swapRB=true, ...)`, feeding the network RGB, so the Core ML
  input uses `color_layout=RGB`. The app just passes a plain 112×112 crop.
- **Match threshold:** cosine **0.363** (OpenCV's documented value), unchanged by
  the FP16 conversion.

Last validated run: embedding dimension **128**, cosine(onnx, coreml)
**0.999995**, max abs error **0.0044** — FP16 is well within tolerance.

## After conversion

```bash
./scripts/build_app.sh     # compiles the model into FaceUnlock.app
open build/FaceUnlock.app  # then use "Enroll Face…" from the menu bar
```

---

**Status:** SFace (Option A) has been downloaded, checksum-verified, and converted
to `Model/FaceEmbedding.mlpackage`. The model file itself is not committed (it is
git-ignored); regenerate it with the steps above. Run `./scripts/build_app.sh`,
then use "Enroll Face…" from the menu bar.

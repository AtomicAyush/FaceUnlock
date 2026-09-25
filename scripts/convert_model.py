#!/usr/bin/env python3
"""Convert OpenCV's SFace ONNX model to a Core ML .mlpackage for FaceUnlock.

Pipeline: ONNX --onnx2torch--> nn.Module --trace--> coremltools --> .mlpackage
(coremltools has no ONNX front-end, hence the torch hop).

Preprocessing is BAKED INTO the ONNX graph: its first two ops are
    data' = (data - 127.5) * 0.0078125          # i.e. (x - 127.5) / 128
so the Core ML image input must receive RAW 0-255 pixels (scale=1, bias=0) and
the network normalizes internally. Channel order follows OpenCV's
FaceRecognizerSF, whose feature() calls
    blobFromImage(aligned, 1, Size(112,112), Scalar(0,0,0), swapRB=true, crop=false)
so it feeds the network RGB (it swaps OpenCV's native BGR). The Core ML input
therefore uses color_layout=RGB. The Swift side hands the model a plain 112x112
crop and does nothing else.

The output is a 128-D embedding (not L2-normalized in-graph); the app normalizes
it before cosine comparison. OpenCV's documented match threshold is cosine 0.363.
"""

import argparse
import sys
import numpy as np


CHANNEL_ORDER = "RGB"  # OpenCV FaceRecognizerSF feeds RGB (blobFromImage swapRB=true)


def build_test_tensor(seed: int = 7) -> np.ndarray:
    """A deterministic 0-255 float image tensor, shape (1,3,112,112), channel
    order == CHANNEL_ORDER. Used only to compare the two runtimes numerically."""
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(1, 3, 112, 112)).astype(np.float32)


def tensor_to_pil(tensor: np.ndarray):
    """Turn the (1,3,112,112) CHANNEL_ORDER tensor into an RGB PIL image, so the
    Core ML model (fed the image) sees exactly the tensor onnxruntime sees."""
    from PIL import Image
    chw = tensor[0]  # (3,112,112) in CHANNEL_ORDER
    if CHANNEL_ORDER == "BGR":
        rgb = chw[::-1]  # -> RGB
    else:
        rgb = chw
    hwc = np.transpose(rgb, (1, 2, 0)).clip(0, 255).astype(np.uint8)
    return Image.fromarray(hwc, mode="RGB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--onnx", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--precision", choices=["fp16", "fp32"], default="fp16")
    ap.add_argument("--pass-cosine", type=float, default=0.995)
    args = ap.parse_args()

    import torch
    import coremltools as ct
    from onnx2torch import convert as onnx2torch_convert

    print(f"Loading {args.onnx} via onnx2torch…")
    torch_model = onnx2torch_convert(args.onnx).eval()

    example = torch.rand(1, 3, 112, 112) * 255.0
    with torch.no_grad():
        traced = torch.jit.trace(torch_model, example)

    precision = ct.precision.FLOAT16 if args.precision == "fp16" else ct.precision.FLOAT32
    color = ct.colorlayout.BGR if CHANNEL_ORDER == "BGR" else ct.colorlayout.RGB

    print(f"Converting to Core ML (mlprogram, {args.precision}, {CHANNEL_ORDER} image input)…")
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.ImageType(name="image", shape=(1, 3, 112, 112),
                             scale=1.0, bias=[0.0, 0.0, 0.0], color_layout=color)],
        outputs=[ct.TensorType(name="embedding")],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=precision,
        compute_units=ct.ComputeUnit.ALL,
    )

    mlmodel.short_description = "SFace-128 (opencv sface_2021dec) face embedding"
    mlmodel.input_description["image"] = "Aligned 112x112 face crop"
    mlmodel.output_description["embedding"] = "128-D face embedding (compare with cosine)"

    print(f"Saving {args.out}…")
    mlmodel.save(args.out)

    # ---- Numerical self-check: onnxruntime (fp32) vs Core ML on one input ----
    print("Validating converted model against onnxruntime…")
    import onnxruntime as ort

    tensor = build_test_tensor()
    sess = ort.InferenceSession(args.onnx, providers=["CPUExecutionProvider"])
    onnx_in = sess.get_inputs()[0].name
    onnx_out = sess.run(None, {onnx_in: tensor})[0].reshape(-1)

    pil = tensor_to_pil(tensor)
    cm = ct.models.MLModel(args.out)
    cm_out_name = list(cm.output_description._fd_spec)[0].name if hasattr(cm.output_description, "_fd_spec") else "embedding"
    cm_pred = cm.predict({"image": pil})
    cm_out = np.array(cm_pred.get("embedding", next(iter(cm_pred.values())))).reshape(-1)

    def cosine(a, b):
        return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))

    cos = cosine(onnx_out, cm_out)
    max_abs = float(np.max(np.abs(onnx_out - cm_out)))
    dim = cm_out.shape[0]

    print(f"  embedding dimension : {dim}")
    print(f"  cosine(onnx, coreml): {cos:.6f}")
    print(f"  max abs error       : {max_abs:.6f}")

    ok = True
    if dim != 128:
        print(f"FAIL: expected 128-D embedding, got {dim}")
        ok = False
    if cos < args.pass_cosine:
        print(f"FAIL: cosine {cos:.6f} below pass bar {args.pass_cosine}")
        ok = False

    if ok:
        print("OK: conversion validated.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

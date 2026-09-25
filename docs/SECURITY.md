# Security notes

## What this app is, and is not

FaceUnlock recognizes its owner's face on-device. In v1 it takes **no action** on
recognition — it updates a menu-bar status and nothing else.

It is **not** a lock-screen unlocker. There is no code anywhere in this project
that stores the macOS login password, decrypts a credential while you are away,
or types anything into the login window. That capability is indistinguishable
from lock-bypass malware, so it is deliberately absent. If you want hands-free
login, the native, credential-free options on this Mac are **Touch ID** and
**Apple Watch auto-unlock** (System Settings → Touch ID & Password → Apple Watch).

The single place a recognition could ever turn into an effect is the
`RecognitionAction` enum in `FaceUnlockCore`. In v1 its only case is `.doNothing`.

## Data and permissions

- **Camera only.** The app declares exactly one entitlement,
  `com.apple.security.device.camera`. It links no networking frameworks and makes
  no network connections; video is processed in memory and never written to disk.
- **No login credential** is ever stored, because the app never needs one.
- **Enrolled face data** — the embeddings that represent your face — is the only
  thing persisted. It lives in `~/Library/Application Support/FaceUnlock/` with
  owner-only permissions.

## Known limitations

- **2-D liveness only.** The blink / eye-aspect-ratio check defeats a still photo
  held up to the camera. It does **not** reliably defeat a video replay — a webcam
  has no depth sensor. This is inherent, and stated rather than hidden.
- **Recognition accuracy** depends on the chosen model (see `docs/MODEL.md`) and
  on lighting and pose.

## Planned follow-ups

- **Encrypt the enrolled template at rest** behind Touch ID (a Secure Enclave key
  gating a symmetric key), so the face embeddings are protected even though they
  are not a credential. Tracked here; not yet implemented in v1.

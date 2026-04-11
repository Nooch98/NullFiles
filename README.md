# 🛡️ NullFiles

**NullFiles** is a portable privacy tool for USB drives and external storage that quickly hides and protects files by relocating them into a protected internal vault structure with encrypted metadata indexing.

It is optimized for:

- speed on large portable drives
- low memory usage
- minimal write amplification on USB devices
- practical everyday privacy on removable media

> **Fast portable privacy — without encrypting terabytes of data.**

---

## 🚀 What NullFiles Actually Is

NullFiles is **not full-disk encryption**, and it is **not a VeraCrypt-style encrypted container**.

Instead, it is a:

### Portable Fast-Lock Vault System

It protects your files by:

1. Moving them into a hidden internal vault folder
2. Renaming them with randomized cryptographic identifiers
3. Encrypting all vault metadata (real names and paths)
4. Making original file structure unreadable without unlocking

This makes NullFiles ideal for:

- portable USB drives
- external hard drives
- fast hide/unhide workflows
- large collections of files where full encryption is impractical

---

## 🔐 Security Model

NullFiles is designed for:

### Strong protection against:
- casual unauthorized access
- opportunistic snooping
- someone browsing your USB manually
- accidental exposure of visible file names

### Limited protection against:
- forensic analysis
- advanced reverse engineering
- attackers inspecting raw blob contents

> [!IMPORTANT]
> NullFiles protects metadata cryptographically, but in fast mode it does **not encrypt file contents themselves**.

That design choice is intentional for speed and portability.

---

## 🛠️ How It Works

---

### 1. Fast Relocation Layer

When vault is locked:

- files are moved into `.sys_data`
- original filenames disappear
- each file gets a randomized secure fake identifier

Example:

```bash
VacationPhotos.jpg
```
becomes:
```bash
blob_KJ83jsP9xQaLm2Vf
```
Directories become:
```bash
dir_X2kPq91LmNf8ZsA
```
---

### 2. Encrypted Metadata Vault
The mapping between:

* fake names
* real names
* original paths

is stored in an encrypted SQLite vault database.

Protected metadata includes:

* real file names
* original relative paths

---
### 3. Cryptographic Protection
NullFiles uses:

**Argon2id**

For master password key derivation.

This protects against:

* brute force attacks
* GPU cracking attempts
* rainbow table attacks

**AES-256-GCM**

Used to encrypt metadata securely with:

* confidentiality
* authentication
* tamper detection

---

### 4. Hidden Vault Directory

Vault storage is kept inside:

```bash
.sys_data
```

On Windows:

* hidden attribute enabled
* system attribute enabled


---

### ⚡ Why NullFiles Does NOT Encrypt File Contents

This is intentional.

Encrypting large USB drives fully creates problems:

* very slow on cheap pendrives
* huge write overhead
* more flash wear
* temporary storage duplication
* poor UX on multi-GB archives

NullFiles chooses:

> speed + portability + practicality over heavy cryptographic full-file encryption

---

### ✨ Key Features
**Portable-first**

Runs directly from USB without installation.

**Fast locking/unlocking**

Moving + renaming is dramatically faster than encrypting large files.

**Low memory footprint**

No giant RAM usage for huge files.

**Encrypted vault index**

Metadata remains cryptographically protected.

**Safer recovery model**

Improved rollback and per-file restore tracking.

**No cloud, no telemetry**

Everything stays local.

---

### ❌ What NullFiles Is NOT

NullFiles is NOT:

* full file encryption
* disk encryption
* military-grade secure wipe
* ransomware-proof storage

If your threat model requires protection against forensic attackers:

use VeraCrypt, LUKS, BitLocker, or full encrypted containers.

---

### 💻 Tech Stack
* **Framework:** Flutter Desktop
* **Language:** Dart
* **Crypto:** Argon2id + AES-GCM
* **Database:** SQLite (sqflite_common_ffi)
* **Platform:** Windows Portable EXE

---

### 🔧 Build From Source
```bash
# 1. Clone the repository
git clone https://github.com/Nooch98/NullFiles.git

# 2. Get dependencies
flutter pub get

# 3. Generate icons (Requires icon.png in assets/)
dart run flutter_launcher_icons

# 4. Build the portable executable
flutter build windows
```

---

### 🧠 Design Philosophy

NullFiles follows one principle:

> On removable media, practical privacy often matters more than heavyweight encryption.

This tool is built for people who need:

* speed
* portability
* simplicity
* plausible privacy on external drives

---

### ⚠️ Security Disclaimer

Always keep backups.

If you lose:

* your master password
* your vault database
* your hidden vault folder

your files may become unrecoverable.

> [!IMPORTANT]
> NullFiles is designed for privacy convenience, not high-security threat models.

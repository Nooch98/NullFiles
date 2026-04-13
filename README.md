# 🛡️ NullFiles

**NullFiles** is a portable privacy tool for USB drives and external storage that protects files using a **hybrid vault model**:

- **Fast Mode:** moves files into a hidden internal vault and renames them with randomized identifiers
- **Deep Mode:** optionally encrypts selected files or folders inside the vault using authenticated encryption

This design is optimized for:

- speed on large portable drives
- low memory usage
- minimal write amplification on USB devices
- practical everyday privacy on removable media
- selective cryptographic protection for sensitive files

> **Fast portable privacy, with optional deep encryption where it matters.**

https://github.com/user-attachments/assets/fcaad4f1-2466-41f4-be64-e37280f4a6e7

---

## 🚀 What NullFiles Actually Is

NullFiles is **not full-disk encryption**, and it is **not a VeraCrypt-style encrypted container**.

Instead, it is a:

## Portable Hybrid Vault System

It protects your files by combining two layers:

### 1. Stealth Layer
- files are moved into a hidden internal vault folder
- original visible names disappear from the root of the drive
- each file or folder receives a randomized identifier

### 2. Crypto Layer
- vault metadata is encrypted
- selected files or folders can also be encrypted recursively inside the vault

This makes NullFiles ideal for:

- portable USB drives
- external hard drives
- fast hide/unhide workflows
- large collections of files where full encryption is impractical
- sensitive documents that need real cryptographic protection

---

## 🔐 Security Model

NullFiles is designed for:

### Effective protection against:
- casual unauthorized access
- opportunistic snooping
- someone manually browsing your USB drive
- accidental exposure of visible file names
- recovery of selected encrypted files without the correct master key

### Limited protection against:
- full forensic analysis
- advanced reverse engineering
- highly specialized post-compromise investigation

> [!IMPORTANT]
> NullFiles always protects vault metadata cryptographically, but **file contents are only encrypted when you explicitly enable content encryption**.

That tradeoff is intentional: it preserves speed and portability while still allowing stronger protection for selected data.

---

## 🛠️ How It Works

### 1. Fast Relocation Layer

When the vault is locked:

- files are moved into `.sys_data`
- original filenames disappear
- each file gets a randomized fake identifier

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
* vault indexing information

---
### 3. Cryptographic Protection
NullFiles uses:

- **Argon2id** For master password key derivation
- **AES-256-GCM** For metadata and optinal file content encryption (Authenticated Encryption)
- **SQLite (encrypted metadata mapping)** to track the relationship between randomized vault names and original file structure

This gives NullFiles a hybrid model:

* **fast concealment** for large datasets
* **real encryption** for selected sensitive content

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

### ⚡ Why NullFiles Uses Optional Content Encryption

Encrypting an entire USB drive or large archive can create practical problems:

* very slow on cheap pendrives
* huge write overhead
* more flash wear
* temporary storage duplication
* poor UX on multi-GB archives

NullFiles chooses a hybrid approach:

> speed + portability by default, stronger encryption only where needed

That makes it practical for removable media while still allowing targeted protection for important files.

---

### ✨ Key Features
**Portable-first**

Runs directly from USB without installation.

**Fast locking/unlocking**

Moving + renaming is dramatically faster than encrypting large files.

**Optional recursive encryption**

Selected files and folders can be encrypted inside the vault.

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

* full-disk encryption
* a hidden volume / plausible deniability system
* ransomware-proof storage
* a replacement for BitLocker, VeraCrypt, LUKS, or other dedicated disk/container encryption systems

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

> On removable media, practical privacy often matters more than heavyweight full-disk encryption.

This tool is built for people who need:

* speed
* portability
* simplicity
* practical privacy on external drives
* optional deeper protection for selected files

---

### ⚠️ Security Disclaimer

Always keep backups.

If you lose:

* your master password
* your vault database
* your hidden vault folder

your files may become unrecoverable.

> [!IMPORTANT]
> NullFiles is designed for practical privacy and selective protection on removable media. It is not intended to replace high-security full-disk encryption in hostile forensic threat models.

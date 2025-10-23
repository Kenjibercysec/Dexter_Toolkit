# Dexter Toolkit

![Version](https://img.shields.io/badge/Version-1.0-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey)

A comprehensive penetration testing and security assessment toolkit built for security professionals and ethical hackers.

## Features

* **Directory & File Discovery** — Advanced directory brute-forcing capabilities.
* **XSS Scanning** — Cross-site scripting vulnerability detection.
* **Custom Wordlist Integration** — Support for multiple wordlist formats and custom lists.
* **Output Management** — Organized results and report generation.
* **Modular Architecture** — Easy to extend and customize with additional modules.

## Prerequisites

Before using Dexter Toolkit, make sure you have the following installed:

* **Linux** (Ubuntu, Debian, Kali, Arch, etc.)
* **Bash** (v4.0 or higher)
* **Git**
* **Python 3** (required by some components)
* **Common security tools** (these will be checked during setup)

## Installation

### Quick install

```bash
git clone https://github.com/Kenjibercysec/Dexter_Toolkit.git
cd Dexter_Toolkit
chmod +x dexter.sh
./dexter.sh
```

### Manual setup

```bash
# Clone the repository
git clone https://github.com/Kenjibercysec/Dexter_Toolkit.git

# Navigate to the toolkit directory
cd Dexter_Toolkit

# Make scripts executable
chmod +x dexter.sh xss.sh

# Run the main tool
./dexter.sh
```

## Wordlists Setup

**Important:** Dexter Toolkit requires wordlists for effective operation. Wordlists are not included due to size and licensing — download them separately.

**Option 1: Using the included downloader script (recommended)**

```bash
# Run the wordlist downloader if available
./download_wordlists.sh
```

**Option 2: Manual wordlist installation**

```bash
# Clone SecLists into a local directory
git clone --depth 1 https://github.com/danielmiessler/SecLists.git seclists

# Or download specific lists you need
mkdir -p wordlists
wget -O wordlists/rockyou.txt https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
```

**Essential wordlists to consider:**

* `rockyou.txt` — popular password wordlist
* `SecLists` — comprehensive collection for security testing
* DirBuster / directory enumeration lists — for web discovery

**Option 3: Using the system package manager (Kali Linux)**

```bash
sudo apt update
sudo apt install seclists wordlists
```

## Usage

### Main interface

Run the main script to start the interactive menu:

```bash
./dexter.sh
```

The interactive menu provides the following options:

* **Directory Scanning** — Web directory enumeration
* **XSS Testing** — Cross-site scripting checks
* **Custom Scans** — User-configured scanning workflows
* **Output Management** — View and manage scan results and reports

### Direct script usage

Run individual utilities directly when needed:

```bash
# Run the XSS scanner against a target
./xss.sh -u https://example.com

# Use a custom configuration file
./dexter.sh --config scan.lib
```

## Project structure

```
Dexter_Toolkit/
├── dexter.sh                # Main toolkit interface
├── xss.sh                   # XSS scanning utility
├── scan.lib                 # Scanning configuration library
├── xnss-dir.json            # Directory scanning configuration
├── dirsearch/               # Directory brute-forcing tool
├── output/                  # Scan results and reports
└── download_wordlists.sh    # Wordlist download utility
```

## Contributing

Contributions, issue reports and feature requests are welcome. Please open an issue or submit a pull request on the repository.

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

## Contact

For questions or collaboration, open an issue on the repository or contact the maintainer via the GitHub profile.

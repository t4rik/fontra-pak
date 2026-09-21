# Fontra Pak

Fontra Pak is a cross-platform, standalone, bundled [Fontra](https://github.com/fontra/fontra) application for desktop use.

## Download

Binaries for MacOS (11 and up), Windows (10 and up) and Ubuntu x86_64 (works on other Linux distributions too, given glibc 2.39 or higher) can be [downloaded under releases](https://github.com/fontra/fontra-pak/releases/latest).

> [!IMPORTANT]
> The Ubuntu binary now requires glibc 2.39, i.e. Ubuntu 24.04, Debian 13, Fedora 40, or later. If you're on an older distribution (or another one using glibc earlier than 2.39), you'll need to upgrade your OS to run it.

For Linux, there are more options, such as `flatpak` and `snap`: https://docs.fontra.xyz/how-tos/installation/installing-fontra-pak-linux/

## Run locally from source

To run the main program directly, set up a Python 3.11 (or higher) virtual environment, install the requirements from `requirements.txt`, then run:

    python FontraPakMain.py

## Build a self-contained application locally

To build a self-contained application, set up a Python 3.11 (or higher) virtual environment, install the requirements from `requirements.txt` and `requirements-dev.txt`, then run:

    pyinstaller FontraPak.spec -y

## How it works

Drop a font file onto application icon, or launch the application, and drop a font file onto the drop area. Or use the "New font" button to create a new font.

https://github.com/fontra/fontra-pak/assets/4246121/a4e8054e-995a-4bcc-ac64-5c8a0ea415aa

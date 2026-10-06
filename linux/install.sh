#!/usr/bin/env bash
set -euo pipefail

APP_ID="xyz.fontra.FontraPak.Native"
APP_NAME="Fontra Pak"

PREFIX="${PREFIX:-$HOME/.local}"
APP_DIR="${PREFIX}/lib/fontrapak"
BIN_DIR="${PREFIX}/bin"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

VENV="${APP_DIR}/venv"

# Requirements. Fontra's build step runs "npm install" and "npm run bundle",
# and its README asks for Node.js 24 or newer.
REQUIRED_NODE_MAJOR=24
UV_PYTHON_VERSION="${UV_PYTHON_VERSION:-3.12}"
NVM_VERSION="${NVM_VERSION:-v0.40.7}"

ASSUME_YES=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Installs ${APP_NAME} for the current user from this source tree.

If Python 3.11+ or Node.js ${REQUIRED_NODE_MAJOR}+ is missing, the script offers to
download them (Python through uv, Node.js through nvm) instead of stopping.

Options:
  -y, --yes    Accept every download offer without asking.
  -h, --help   Show this help.

Environment:
  PYTHON             Python interpreter to use (must be 3.11 or newer).
  PREFIX             Install prefix (default: ~/.local).
  UV_PYTHON_VERSION  Python version uv downloads (default: ${UV_PYTHON_VERSION}).
  NVM_VERSION        nvm release the script installs (default: ${NVM_VERSION}).
EOF
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option: ${arg}" >&2; usage >&2; exit 2 ;;
    esac
done

die() {
    echo "error: $*" >&2
    exit 1
}

# Ask a yes/no question. Without a terminal and without --yes the answer is no.
confirm() {
    local reply
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        return 1
    fi
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found"
}

echo "==> Installing ${APP_NAME}"
echo "    Source: ${PROJECT_DIR}"
echo "    Prefix: ${PREFIX}"

require_tool git

mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# ---------------------------------------------------------------- Python ----

python_ok() {
    "$1" -c 'import sys; raise SystemExit(sys.version_info < (3, 11))' >/dev/null 2>&1
}

find_python() {
    local candidate
    if [[ -n "${PYTHON:-}" ]]; then
        command -v "$PYTHON" >/dev/null 2>&1 && python_ok "$PYTHON" && command -v "$PYTHON"
        return
    fi
    for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
        if command -v "$candidate" >/dev/null 2>&1 && python_ok "$candidate"; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    require_tool curl
    echo "==> Installing uv (standalone installer, shell profiles are not modified)"
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
    export PATH="${HOME}/.local/bin:${PATH}"
    command -v uv >/dev/null 2>&1 || die "uv was installed but is not on PATH"
}

USE_UV=0
PYTHON_BIN=""
if PYTHON_BIN="$(find_python)"; then
    echo "    Python: ${PYTHON_BIN} ($("$PYTHON_BIN" --version 2>&1))"
else
    echo "Python 3.11 or newer was not found${PYTHON:+ (PYTHON=${PYTHON})}."
    if confirm "Download Python ${UV_PYTHON_VERSION} with uv? (uv is installed to ~/.local/bin if missing)"; then
        ensure_uv
        USE_UV=1
        echo "    Python: ${UV_PYTHON_VERSION} (managed by uv)"
    else
        cat >&2 <<EOF
error: Python 3.11 or newer is required.
Install it with your package manager, point PYTHON at it, or run this script
again in a terminal and accept the uv option (or pass --yes).
EOF
        exit 1
    fi
fi

# ---------------------------------------------------------------- Node.js ---

# Fontra's build step needs Node.js. The installed app does not.
node_ok() {
    local major
    command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || return 1
    major="$(node -p 'process.versions.node.split(".")[0]')"
    (( major >= REQUIRED_NODE_MAJOR ))
}

# nvm does not work under "set -eu", so relax both while it runs.
use_nvm_node() {
    local nvm_dir="" candidate status
    for candidate in "${NVM_DIR:-}" "${XDG_CONFIG_HOME:-${HOME}/.config}/nvm" "${HOME}/.nvm" "${APP_DIR}/nvm"; do
        if [[ -n "$candidate" && -s "${candidate}/nvm.sh" ]]; then
            nvm_dir="$candidate"
            break
        fi
    done
    if [[ -z "$nvm_dir" ]]; then
        require_tool curl
        nvm_dir="${APP_DIR}/nvm"
        echo "==> Installing nvm ${NVM_VERSION} into ${nvm_dir} (shell profiles are not modified)"
        # The nvm installer refuses to run if NVM_DIR does not exist yet.
        mkdir -p "$nvm_dir"
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
            | NVM_DIR="$nvm_dir" PROFILE=/dev/null bash
    else
        echo "==> Using existing nvm in ${nvm_dir}"
    fi
    export NVM_DIR="$nvm_dir"
    set +eu
    # shellcheck disable=SC1091
    . "${NVM_DIR}/nvm.sh"
    nvm install "${REQUIRED_NODE_MAJOR}" && nvm use "${REQUIRED_NODE_MAJOR}"
    status=$?
    set -eu
    return "$status"
}

if ! node_ok; then
    if command -v node >/dev/null 2>&1; then
        echo "Found Node.js $(node --version), but Node.js ${REQUIRED_NODE_MAJOR}+ with npm is needed to build Fontra."
    else
        echo "Node.js ${REQUIRED_NODE_MAJOR}+ with npm is needed to build Fontra and was not found."
    fi
    if confirm "Download Node.js ${REQUIRED_NODE_MAJOR} with nvm? (only needed to build Fontra)"; then
        use_nvm_node || die "nvm could not install Node.js ${REQUIRED_NODE_MAJOR}"
        node_ok || die "Node.js ${REQUIRED_NODE_MAJOR}+ with npm is still not available"
    else
        cat >&2 <<EOF
error: Node.js ${REQUIRED_NODE_MAJOR} or newer (with npm) is required.
Install it from https://nodejs.org/en/download/ or with your own nvm, then run
this script again, or run it in a terminal and accept the nvm option (or pass --yes).
EOF
        exit 1
    fi
fi
echo "    Node.js: $(node --version), npm $(npm --version)"

# ---------------------------------------------------------- Virtual env -----

if [[ ! -d "$VENV" ]]; then
    echo "==> Creating virtual environment"
    if [[ "$USE_UV" -eq 1 ]]; then
        uv venv --seed --python "$UV_PYTHON_VERSION" "$VENV"
    else
        "$PYTHON_BIN" -m venv "$VENV"
    fi
elif ! python_ok "${VENV}/bin/python"; then
    die "the existing environment in ${VENV} uses Python older than 3.11; run linux/uninstall.sh and try again"
fi

echo "==> Updating packaging tools"
"${VENV}/bin/python" -m pip install --upgrade pip

echo "==> Installing Fontra Pak dependencies"
"${VENV}/bin/python" -m pip install -r "${PROJECT_DIR}/requirements.txt"

echo "==> Installing Fontra Pak"

# Keep the source tree as the application source for now.
# This avoids PyInstaller and therefore uses the host Linux libraries.
ln -sfn "${PROJECT_DIR}/FontraPakMain.py" "${APP_DIR}/FontraPakMain.py"

cat > "${BIN_DIR}/fontrapak" <<EOF
#!/usr/bin/env bash
exec "${VENV}/bin/python" "${APP_DIR}/FontraPakMain.py" "\$@"
EOF

chmod +x "${BIN_DIR}/fontrapak"

echo "==> Installing desktop entry"

cat > "${DESKTOP_DIR}/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Name=${APP_NAME} (Native)
Comment=Font editor and design application
Exec=${BIN_DIR}/fontrapak %F
Icon=${APP_ID}
Terminal=false
Type=Application
Categories=Graphics;Development;
MimeType=
StartupNotify=true
StartupWMClass=fontrapak
EOF

echo "==> Installing icon"

if [[ -f "${PROJECT_DIR}/icon/FontraIcon.svg" ]]; then
    install -m 0644 \
        "${PROJECT_DIR}/icon/FontraIcon.svg" \
        "${ICON_DIR}/${APP_ID}.svg"
else
    echo "warning: icon/FontraIcon.svg not found; desktop entry installed without an icon file"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" || true
fi

echo
echo "Installation complete."
echo
echo "Run:"
echo "  ${BIN_DIR}/fontrapak"
echo
echo "If ${BIN_DIR} is not in PATH:"
echo "  export PATH=\"${BIN_DIR}:\$PATH\""

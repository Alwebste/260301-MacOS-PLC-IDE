#!/bin/bash
# Build the Rust core library for macOS and generate Swift bindings via UniFFI.
#
# This script is called by Xcode as a pre-build phase.
# It can also be run manually during development.
#
# Prerequisites:
#   - Rust toolchain: rustup (with aarch64-apple-darwin and x86_64-apple-darwin targets)
#   - UniFFI bindgen: cargo install uniffi-bindgen-cli (or via cargo-binstall)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RUST_TARGET="aarch64-apple-darwin"
elif [ "$ARCH" = "x86_64" ]; then
    RUST_TARGET="x86_64-apple-darwin"
else
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
fi

echo "==> Building plc-core for $RUST_TARGET (release)..."
cargo build --release --target "$RUST_TARGET" -p plc-core

# Generate Swift bindings from UniFFI
UNIFFI_OUT="$SCRIPT_DIR/target/uniffi"
mkdir -p "$UNIFFI_OUT"

echo "==> Generating UniFFI Swift bindings..."
cargo run --release -p uniffi-bindgen-cli -- \
    generate plc-core/src/plc_core.udl \
    --language swift \
    --out-dir "$UNIFFI_OUT" \
    2>/dev/null || {
    # Fallback: use cargo-uniffi if uniffi-bindgen-cli isn't available
    echo "  Note: uniffi-bindgen-cli not found, trying uniffi-bindgen..."
    cargo uniffi-bindgen generate plc-core/src/plc_core.udl \
        --language swift \
        --out-dir "$UNIFFI_OUT"
}

# Copy the static library to a predictable location for Xcode
LIB_SRC="$SCRIPT_DIR/target/$RUST_TARGET/release/libplc_core.a"
LIB_DST="$SCRIPT_DIR/target/release/libplc_core.a"
mkdir -p "$SCRIPT_DIR/target/release"

if [ -f "$LIB_SRC" ]; then
    cp "$LIB_SRC" "$LIB_DST"
    echo "==> Static library: $LIB_DST"
else
    echo "Warning: Static library not found at $LIB_SRC"
fi

echo "==> Swift bindings generated at: $UNIFFI_OUT"
echo "==> Build complete."

#!/usr/bin/env bash
# =============================================================================
#  setup_android_opensuse.sh
#  Android SDK + Gradle wrapper setup for openSUSE Tumbleweed
#  Author: Mark Harrington
#
#  Target hardware: 2x AMD Athlon(tm) II X2 215, openSUSE Tumbleweed 20260610
#                    Kernel 7.0.11-1-default (64-bit), Qt 6.11
#
#  This script:
#    1. Installs Java (OpenJDK 17) via zypper
#    2. Downloads & installs Android SDK command line tools
#    3. Installs platform-tools, build-tools 34.0.0, platform android-34
#    4. Sets up ANDROID_HOME / PATH in ~/.bashrc
#    5. Writes a Gradle 8.2 wrapper (gradlew + gradle-wrapper.jar) into a
#       target project directory (or creates one if it doesn't exist)
#    6. Checks/advises on swap space — important for this older dual-core CPU
#
#  Usage:
#    chmod +x setup_android_opensuse.sh
#    ./setup_android_opensuse.sh [optional: path to existing project]
#
#  If no project path is given, the script only sets up the SDK/Gradle
#  download cache and environment — run it again later from inside any
#  Android project to add the wrapper to that project.
# =============================================================================
set -e

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ANDROID_SDK_ROOT="$HOME/Android/Sdk"
CMDLINE_TOOLS_VER="11076708"
BUILD_TOOLS_VER="34.0.0"
PLATFORM_VER="android-34"
GRADLE_VERSION="8.2"

PROJECT_DIR="${1:-}"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Android SDK + Gradle Setup — openSUSE Tumbleweed       ║${NC}"
echo -e "${CYAN}║   Mark Harrington                                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Java ───────────────────────────────────────────────────────────────────
echo "[1/6] Checking Java (OpenJDK 17)..."
if ! command -v java &>/dev/null; then
    echo -e "  ${YELLOW}Java not found — installing via zypper...${NC}"
    sudo zypper --non-interactive install java-17-openjdk java-17-openjdk-devel
else
    JAVA_VER=$(java -version 2>&1 | head -1)
    echo -e "  ${GREEN}Found:${NC} $JAVA_VER"
    if ! java -version 2>&1 | grep -q "17\."; then
        echo -e "  ${YELLOW}Java 17 recommended for AGP 8.x. Installing alongside...${NC}"
        sudo zypper --non-interactive install java-17-openjdk java-17-openjdk-devel
    fi
fi

# Ensure wget/unzip are present
echo ""
echo "  Checking wget/unzip/tar..."
sudo zypper --non-interactive install -y wget unzip tar gzip >/dev/null 2>&1 || true
echo -e "  ${GREEN}OK${NC}"

# ── 2. Swap space check ────────────────────────────────────────────────────────
echo ""
echo "[2/6] Checking swap space (Athlon II X2 215 is dual-core — Gradle/AGP can be heavy)..."
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
echo "  RAM:  ${TOTAL_RAM_MB} MB"
echo "  Swap: ${SWAP_MB} MB"

if [ "$SWAP_MB" -lt 2048 ]; then
    echo -e "  ${YELLOW}WARNING: Less than 2GB swap detected.${NC}"
    echo "  Gradle daemons can use 1-2GB+ of heap during Android builds."
    echo "  Recommended: create a swap file if you hit OOM errors during build:"
    echo ""
    echo "    sudo fallocate -l 4G /swapfile"
    echo "    sudo chmod 600 /swapfile"
    echo "    sudo mkswap /swapfile"
    echo "    sudo swapon /swapfile"
    echo "    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab"
    echo ""
else
    echo -e "  ${GREEN}Sufficient swap available.${NC}"
fi

# ── 3. Android SDK command line tools ──────────────────────────────────────────
echo ""
echo "[3/6] Android SDK command line tools..."
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "  Downloading Android command line tools (~150MB)..."
    wget -q --show-progress \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VER}_latest.zip" \
        -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
    # Google zips into 'cmdline-tools/' — sdkmanager requires folder named 'latest'
    if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]; then
        mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" \
           "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    fi
    rm /tmp/cmdline-tools.zip
    echo -e "  ${GREEN}Installed.${NC}"
else
    echo -e "  ${GREEN}Already present.${NC}"
fi

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

# ── 4. SDK components ───────────────────────────────────────────────────────────
echo ""
echo "[4/6] Installing SDK components (platform-tools, build-tools, platform)..."
export JAVA_HOME="${JAVA_HOME:-$(readlink -f /usr/lib64/jvm/java-17-openjdk 2>/dev/null || dirname $(dirname $(readlink -f $(command -v java))))}"
echo "  Using JAVA_HOME=$JAVA_HOME"

yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" \
    "platform-tools" \
    "build-tools;${BUILD_TOOLS_VER}" \
    "platforms;${PLATFORM_VER}"
echo -e "  ${GREEN}Done.${NC}"

# ── 5. Environment variables (~/.bashrc) ────────────────────────────────────────
echo ""
echo "[5/6] Setting up environment variables..."

BASHRC="$HOME/.bashrc"
MARKER="# --- Android SDK (added by setup_android_opensuse.sh) ---"

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    {
        echo ""
        echo "$MARKER"
        echo "export ANDROID_HOME=\"$ANDROID_SDK_ROOT\""
        echo "export ANDROID_SDK_ROOT=\"$ANDROID_SDK_ROOT\""
        echo "export PATH=\"\$PATH:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin\""
        # Gradle daemon memory cap — important on dual-core, modest-RAM hardware
        echo "export GRADLE_OPTS=\"-Dorg.gradle.daemon=true -Dorg.gradle.jvmargs=-Xmx1536m\""
        echo "# --- end Android SDK setup ---"
    } >> "$BASHRC"
    echo -e "  ${GREEN}Added to ~/.bashrc${NC}"
else
    echo -e "  ${GREEN}Already configured in ~/.bashrc${NC}"
fi

# Export for the rest of this script's run too
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"

# ── 6. Gradle wrapper (only if a project directory was given) ──────────────────
echo ""
echo "[6/6] Gradle wrapper setup..."

if [ -z "$PROJECT_DIR" ]; then
    echo -e "  ${YELLOW}No project directory given — skipping Gradle wrapper.${NC}"
    echo "  Run again with a project path to add the wrapper, e.g.:"
    echo "    $0 ~/Android_projects/MyApp"
else
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "  Creating project directory: $PROJECT_DIR"
        mkdir -p "$PROJECT_DIR"
    fi
    cd "$PROJECT_DIR"
    mkdir -p gradle/wrapper

    # 6a. Write gradlew launcher (java launcher — no Gradle extraction needed)
    if [ ! -f "gradlew" ]; then
        cat > gradlew << 'GRADLEW'
#!/bin/sh
set -e
APP_HOME="$(cd "$(dirname "$0")" && pwd -P)"
exec java \
  -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" \
  "-Dorg.gradle.appname=gradlew" \
  org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
        chmod +x gradlew
        echo -e "  ${GREEN}Wrote gradlew launcher${NC}"
    else
        echo "  gradlew already exists — leaving as-is"
    fi

    # 6b. Write wrapper properties
    cat > gradle/wrapper/gradle-wrapper.properties << PROPS
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
PROPS

    # 6c. Download gradle-wrapper.jar — verify it's a real jar
    JAR="gradle/wrapper/gradle-wrapper.jar"
    JAR_OK=false
    if [ -f "$JAR" ] && unzip -t "$JAR" >/dev/null 2>&1; then
        JAR_OK=true
    fi

    if [ "$JAR_OK" = false ]; then
        rm -f "$JAR"
        echo "  Downloading gradle-wrapper.jar..."
        wget -q --show-progress \
            "https://github.com/gradle/gradle/raw/v${GRADLE_VERSION}.0/gradle/wrapper/gradle-wrapper.jar" \
            -O "$JAR"
        if ! unzip -t "$JAR" >/dev/null 2>&1; then
            echo -e "  ${RED}Download failed or corrupt jar.${NC}"
            echo "  Manually download from:"
            echo "  https://github.com/gradle/gradle/raw/v${GRADLE_VERSION}.0/gradle/wrapper/gradle-wrapper.jar"
            echo "  and place at: $PROJECT_DIR/$JAR"
            rm -f "$JAR"
            exit 1
        fi
        echo -e "  ${GREEN}gradle-wrapper.jar downloaded and verified.${NC}"
    else
        echo -e "  ${GREEN}gradle-wrapper.jar already present.${NC}"
    fi

    # 6d. gradle.properties — AndroidX + memory cap for this hardware
    GRADLE_PROPS="gradle.properties"
    touch "$GRADLE_PROPS"
    grep -q "android.useAndroidX" "$GRADLE_PROPS" || echo "android.useAndroidX=true" >> "$GRADLE_PROPS"
    grep -q "org.gradle.jvmargs" "$GRADLE_PROPS" || echo "org.gradle.jvmargs=-Xmx1536m" >> "$GRADLE_PROPS"
    # Dual-core CPU — don't over-parallelise
    grep -q "org.gradle.parallel" "$GRADLE_PROPS" || echo "org.gradle.parallel=false" >> "$GRADLE_PROPS"
    echo -e "  ${GREEN}gradle.properties configured for this hardware (Xmx1536m, parallel=false)${NC}"

    # 6e. Kill any stale Gradle daemons before first build
    bash gradlew --stop 2>/dev/null || true
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅  SETUP COMPLETE                                     ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  ANDROID_HOME = $ANDROID_SDK_ROOT"
echo -e "${GREEN}║${NC}  Build-tools  = ${BUILD_TOOLS_VER}"
echo -e "${GREEN}║${NC}  Platform     = ${PLATFORM_VER}"
echo -e "${GREEN}║${NC}  Gradle       = ${GRADLE_VERSION} (via wrapper)"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  IMPORTANT: run 'source ~/.bashrc' or open a new"
echo -e "${GREEN}║${NC}  terminal for the environment variables to take effect."
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"

if [ -n "$PROJECT_DIR" ]; then
    echo ""
    echo "Next step — build your project:"
    echo "  cd $PROJECT_DIR"
    echo "  source ~/.bashrc"
    echo "  bash gradlew assembleDebug"
fi

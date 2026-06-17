# Android SDK and Gradle Setup Script

*Technical Explanation for openSUSE Tumbleweed*

**Prepared for:** Mark David Harrington
**Document subject:** `setup_android_opensuse.sh`

| Property | Value |
| --- | --- |
| Target hardware | 2 x AMD Athlon(tm) II X2 215 Processor |
| Operating system | openSUSE Tumbleweed 20260610 |
| Kernel | 7.0.11-1-default (64-bit) |
| Desktop environment | Qt 6.11 |
| Script purpose | Install Android SDK command line tools, build tools, platform, set up the Gradle wrapper, and configure the shell environment for Android app builds |

# 1. Overview and Purpose

The script setup_android_opensuse.sh automates the installation and configuration of every tool required to build Android applications from the command line on openSUSE Tumbleweed. It was written specifically for this machine because the standard Debian-based instructions (which use apt) do not apply — openSUSE uses the zypper package manager, and the system also ships with a newer default Java runtime that is incompatible with the version of Gradle used by the Android Gradle Plugin.

The script performs six sequential tasks, each printed as a numbered step so progress can be tracked during a run:

- Install and verify a Java 17 runtime via zypper
- Check available swap space and warn if it is too low for the hardware
- Download and install the Android SDK command line tools
- Install the specific SDK components needed (platform-tools, build-tools 34.0.0, Android 14 platform)
- Write persistent environment variables to ~/.bashrc, including a pinned JAVA_HOME
- Create or update the Gradle wrapper inside a target project directory, tuned for this hardware

The remainder of this document walks through each section of the script in the order it executes, explaining the reasoning behind each command and what would go wrong if that step were omitted.

# 2. Script Header and Safety Settings

```bash
#!/usr/bin/env bash
set -e
```

The shebang line tells the operating system to execute this file using bash, located via the PATH rather than a hardcoded path — this makes the script portable across systems where bash may live in /bin or /usr/bin.

The set -e instruction is critical: it causes the entire script to stop immediately if any command returns a non-zero (failure) exit code. Without this, a failed download or a missing package could be silently ignored, and the script would continue attempting later steps using missing or broken components, leading to confusing errors much further down the line. With set -e, the script fails fast and the error message points directly at the step that went wrong.

# 3. Configuration Variables

```bash
ANDROID_SDK_ROOT="$HOME/Android/Sdk"
CMDLINE_TOOLS_VER="11076708"
BUILD_TOOLS_VER="34.0.0"
PLATFORM_VER="android-34"
GRADLE_VERSION="8.2"
PROJECT_DIR="${1:-}"
```

These variables centralise every version number and path used throughout the script. Keeping them at the top means that if Google releases a newer SDK tools package, or the project later needs to target Android 15 instead of Android 14, only these lines need to change rather than hunting through the whole script.

- ANDROID_SDK_ROOT — the installation directory for the entire Android SDK. $HOME/Android/Sdk is the conventional location used by Android Studio, so anything installed here would also be recognised by Android Studio if it is installed later.
- CMDLINE_TOOLS_VER — the build number of Google's command line tools package. This number changes with each Google release and must match a real download URL.
- BUILD_TOOLS_VER and PLATFORM_VER — these define which version of the Android build toolchain and which Android API level (34 = Android 14) the SDK will install.
- GRADLE_VERSION — the version of Gradle the wrapper will request. Version 8.2 is required to be compatible with the version of the Android Gradle Plugin used in the HC-05 project.
- PROJECT_DIR — an optional command-line argument. If the script is run as ./setup_android_opensuse.sh ~/Android_projects/MyApp, this variable captures that path. If no argument is given, it defaults to an empty string, and later steps that need a project directory are skipped.

# 4. Terminal Colour Codes

```bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m';
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
```

These variables hold ANSI escape codes — special character sequences that most terminal emulators interpret as instructions to change text colour rather than printing visible characters. RED, GREEN and YELLOW are used to colour-code success, warning and error messages so they stand out at a glance in a long stream of output. NC stands for 'No Colour' and is used to reset the terminal back to its default colour after a coloured message, so the colour does not bleed into subsequent normal text.

# 5. Step 1 — Installing Java 17

```bash
if ! command -v java &>/dev/null; then
    sudo zypper --non-interactive install java-17-openjdk java-17-openjdk-devel
else
    JAVA_VER=$(java -version 2>&1 | head -1)
    if ! java -version 2>&1 | grep -q "17\."; then
        sudo zypper --non-interactive install java-17-openjdk java-17-openjdk-devel
    fi
fi
```

This step ensures a Java Development Kit version 17 is present, which is the version required by Gradle 8.2 and the Android Gradle Plugin used in this project.

command -v java &>/dev/null checks whether a program called 'java' exists anywhere on the PATH, redirecting any output to /dev/null so nothing is printed — the script only cares about the exit code, not the output. The exclamation mark inverts the result, so this branch runs only if java is NOT found.

If Java is found, the script then checks its version string for the text '17.' — this is a simple but effective way to detect whether the installed Java is version 17.x without needing to parse complex version numbers. If the installed Java is some other version (commonly a newer default JDK on Tumbleweed), Java 17 is installed alongside it without removing the existing version.

The --non-interactive flag tells zypper not to pause and ask for confirmation, which would otherwise halt an unattended script run.

```bash
sudo zypper --non-interactive install -y wget unzip tar gzip >/dev/null 2>&1 || true
```

This line ensures the basic download and archive tools used later in the script are present. The trailing || true means that even if this command fails for any reason (for example, the packages are already installed and zypper returns a warning exit code), the script does not abort — these tools are not critical enough to halt the entire setup over.

# 6. Step 1b — Locating and Pinning Java 17

This is the section added specifically to resolve the build error encountered previously: 'Unsupported class file major version 69'. That error occurs because Gradle 8.2 was compiled to run on Java versions up to 20, but openSUSE Tumbleweed's default 'java' command pointed at a much newer Java release (version 25, which produces class file major version 69). Gradle could not understand the class files produced by that newer compiler and refused to proceed.

```bash
JAVA17_HOME=""
for candidate in /usr/lib64/jvm/java-17-openjdk /usr/lib64/jvm/java-17* \
                 /usr/lib/jvm/java-17-openjdk /usr/lib/jvm/java-17*; do
    if [ -x "$candidate/bin/java" ]; then
        JAVA17_HOME="$candidate"
        break
    fi
done
```

This loop checks a list of likely installation paths for Java 17 on openSUSE. The wildcard patterns (java-17*) account for the fact that the exact folder name can vary slightly between Tumbleweed snapshots (for example, java-17-openjdk versus java-17-openjdk-17.0.x). For each candidate path, the script checks whether a file named 'java' exists inside its bin subdirectory AND that the file is executable (-x). The moment a match is found, JAVA17_HOME is set to that path and the loop exits early with break — there is no need to keep searching once a valid installation has been found.

If no match is found anywhere, JAVA17_HOME remains an empty string, and the script prints a clear warning listing what Java versions ARE installed, along with manual instructions, rather than failing silently or guessing incorrectly.

# 7. Step 2 — Swap Space Check

The target hardware uses two AMD Athlon II X2 215 processors — a dual-core CPU design from around 2010. While perfectly capable of running Linux and compiling small programs, the Android Gradle Plugin and Gradle daemon are notoriously memory-hungry, sometimes requiring well over a gigabyte of heap space during a build. If physical RAM runs out and there is insufficient swap space configured, the Linux kernel's out-of-memory (OOM) killer may terminate the Gradle process partway through a build, producing confusing and seemingly random failures.

```bash
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
```

The free command reports memory statistics. Piping its output to awk and matching the line beginning with 'Mem:' or 'Swap:' extracts just the total value from the second column, in megabytes (the -m flag to free).

```bash
if [ "$SWAP_MB" -lt 2048 ]; then
    echo -e "${YELLOW}WARNING: Less than 2GB swap detected.${NC}"
    ... (instructions to create a 4GB swap file)
else
    echo -e "${GREEN}Sufficient swap available.${NC}"
fi
```

If less than 2048 MB (2 GB) of swap is detected, the script does not attempt to create swap space itself — creating swap files requires careful decisions about disk location and size that depend on available disk space, which the script cannot safely assume. Instead, it prints the exact commands (fallocate, mkswap, swapon, and an /etc/fstab entry to make it permanent across reboots) so Mark can run them manually if and when a build actually runs out of memory.

# 8. Step 3 — Android SDK Command Line Tools

```bash
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
    wget -q --show-progress \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VER}_latest.zip" \
        -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
    if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]; then
        mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" \
           "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    fi
    rm /tmp/cmdline-tools.zip
fi
```

mkdir -p creates the target directory structure, including any missing parent directories, and does not error if the directory already exists — this makes the script safe to re-run.

The if statement checks for the presence of the sdkmanager executable specifically. This is the actual tool the rest of the script depends on, so its presence is a reliable signal that this step has already completed successfully on a previous run, allowing the (slow, ~150MB) download to be skipped.

wget downloads the command line tools archive from Google's official repository. The -q flag suppresses wget's normal verbose output, while --show-progress still displays a simple progress bar — giving useful feedback without flooding the terminal with redirect and header information.

unzip -q extracts the downloaded archive quietly. Google's zip file extracts into a folder literally named 'cmdline-tools', but the sdkmanager tool itself expects to find itself inside a folder named 'latest'. The if block detects this mismatched folder name and uses mv to rename it, a step that is easy to miss and a common source of 'sdkmanager not found' errors when following manual instructions.

Finally, rm removes the downloaded zip file, since it is no longer needed and would otherwise consume disk space unnecessarily.

# 9. Step 4 — Installing SDK Components

```bash
if [ -n "$JAVA17_HOME" ]; then
    export JAVA_HOME="$JAVA17_HOME"
else
    export JAVA_HOME="${JAVA_HOME:-$(dirname $(dirname $(readlink -f $(command -v java))))}"
fi
```

Before running sdkmanager, the script sets JAVA_HOME for the remainder of the script's execution (export makes the variable available to any programs the script launches, not just the script itself). If Step 1b successfully found a Java 17 installation, that path is used directly.

If no Java 17 was found, a fallback expression attempts to derive a sensible JAVA_HOME from whatever 'java' is currently on the PATH: command -v java finds the path to the java executable, readlink -f resolves any symbolic links to find the real file location, and dirname is applied twice to walk up from .../bin/java to the JDK's root directory. This fallback is a best-effort measure and is why the script prints a clear warning earlier if Java 17 specifically could not be located.

```bash
yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
"$SDKMANAGER" \
    "platform-tools" \
    "build-tools;${BUILD_TOOLS_VER}" \
    "platforms;${PLATFORM_VER}"
```

The Android SDK requires the user to accept several licence agreements before any components can be installed. sdkmanager --licenses normally prompts interactively for each one. The yes command is a standard Unix utility that does nothing but continuously output the letter 'y' followed by a newline, forever — piping this into sdkmanager answers every prompt with 'yes' automatically. The output is discarded (both stdout and stderr, via >/dev/null 2>&1) since it is just a long stream of licence text, and || true ensures that if sdkmanager exits with a non-zero code once all licences are processed (which it sometimes does), the script does not treat this as a fatal error.

The final command installs three SDK packages in one invocation: platform-tools (which includes adb, the Android Debug Bridge used for installing apps and communicating with devices), build-tools at the specific version required by the project's Gradle configuration, and the platform package for Android 14 (API level 34), which provides the android.jar containing all the framework classes the app compiles against.

# 10. Step 5 — Persistent Environment Variables

This step writes configuration into ~/.bashrc, the file bash reads every time a new interactive shell starts. Anything exported here becomes available automatically in every future terminal session, without needing to re-run the setup script.

```bash
BASHRC="$HOME/.bashrc"
MARKER="# --- Android SDK (added by setup_android_opensuse.sh) ---"

if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    { ... append block ... } >> "$BASHRC"
else
    echo "Already configured"
fi
```

The MARKER variable is a unique comment string written into .bashrc alongside the configuration. Before appending anything, grep -qF searches .bashrc for this exact marker string (-F treats it as a literal string rather than a pattern, and -q suppresses output, only returning a yes/no exit code). This prevents the script from appending the same block of environment variables every time it is run — without this check, running the setup script three times would result in three duplicate, possibly conflicting, sets of exports in .bashrc.

The block of code that gets appended (inside the curly braces, redirected with >> to append rather than overwrite) contains several export statements:

- If Java 17 was located, JAVA_HOME is exported to that path, and PATH is updated to put $JAVA_HOME/bin first — guaranteeing that typing 'java' or 'javac' in any new terminal uses version 17, regardless of what other JDKs are installed on the system.
- ANDROID_HOME and ANDROID_SDK_ROOT are both set, as different tools historically expect different variable names for the same thing, and setting both avoids compatibility issues.
- PATH is extended to include the platform-tools directory (so adb and similar tools can be run by name from anywhere) and the cmdline-tools/latest/bin directory (for sdkmanager and avdmanager).
- GRADLE_OPTS is set with a memory limit of 1536 megabytes for the Gradle daemon's Java Virtual Machine, chosen specifically to leave headroom for the rest of the system on this dual-core machine with potentially limited RAM.

After writing this block, the script also immediately exports JAVA_HOME and updates PATH for its own currently-running process. This is necessary because changes to ~/.bashrc only take effect in NEW shell sessions — without these extra export lines, the rest of THIS script run (specifically, the Gradle wrapper steps that follow) would still be using the old, unpinned Java.

# 11. Step 6 — Gradle Wrapper Setup

This final step only runs if a project directory was supplied as a command-line argument. If PROJECT_DIR is empty, the script prints instructions for how to re-run it later with a project path, and exits this section without error.

## 11.1 The gradlew Launcher Script

```bash
cat > gradlew << 'GRADLEW'
#!/bin/sh
set -e
APP_HOME="$(cd "$(dirname "$0")" && pwd -P)"
exec java \
  -classpath "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" \
  "-Dorg.gradle.appname=gradlew" \
  org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
```

Rather than downloading the entire Gradle distribution and extracting a pre-built gradlew script (an approach that previously failed due to mismatched internal file paths inside the Gradle zip), this script writes a minimal, hand-crafted launcher directly. The heredoc syntax (<< 'GRADLEW' ... GRADLEW) writes everything between the two GRADLEW markers literally into the gradlew file, without bash trying to interpret any of the $ variables inside it — the quotes around the opening GRADLEW marker are what disable that interpretation.

The launcher script itself does three things: it determines its own directory (APP_HOME) regardless of where it is run from, so the project can be built from any working directory; it then uses exec to replace itself with a Java process (exec avoids leaving an extra shell process running uselessly in memory); and that Java process runs the class org.gradle.wrapper.GradleWrapperMain, found inside gradle-wrapper.jar, passing along any arguments given to gradlew (such as 'assembleDebug') via "$@".

## 11.2 Wrapper Properties File

```bash
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

This properties file tells GradleWrapperMain where to download the actual Gradle distribution from, and where to cache it once downloaded (inside ~/.gradle, the GRADLE_USER_HOME). The backslash before the colon in the URL is required because Java properties files treat an unescaped colon as a key/value separator — without escaping it, the URL would be parsed incorrectly. The first time gradlew runs, it reads this file, downloads the specified Gradle version if not already cached, and uses it to run the actual build.

## 11.3 Downloading and Verifying gradle-wrapper.jar

```bash
JAR="gradle/wrapper/gradle-wrapper.jar"
JAR_OK=false
if [ -f "$JAR" ] && unzip -t "$JAR" >/dev/null 2>&1; then
    JAR_OK=true
fi

if [ "$JAR_OK" = false ]; then
    rm -f "$JAR"
    wget -q --show-progress \
        "https://github.com/gradle/gradle/raw/v${GRADLE_VERSION}.0/gradle/wrapper/gradle-wrapper.jar" \
        -O "$JAR"
    if ! unzip -t "$JAR" >/dev/null 2>&1; then
        ... print manual instructions and exit 1 ...
    fi
fi
```

This block first checks whether a usable gradle-wrapper.jar already exists. Importantly, it does not just check that the file exists — unzip -t (test) attempts to verify the file's internal zip structure without extracting it. A jar file IS a zip file, so this check catches the case where a previous download failed partway through or returned an HTML error page instead of the actual binary, which would otherwise sit on disk looking like a valid file but crash Gradle the moment it tried to use it.

If the jar is missing or fails this integrity check, it is deleted and re-downloaded directly from the Gradle project's GitHub repository at the tag matching the requested version. After downloading, the same unzip -t check is run again on the new file — if it still fails, the script removes the bad file, prints the exact URL and target path for manual download, and exits with status 1 (a non-zero exit code, signalling failure to anything that called this script).

## 11.4 gradle.properties — Hardware-Specific Tuning

```bash
touch "$GRADLE_PROPS"
grep -q "android.useAndroidX" "$GRADLE_PROPS" || echo "android.useAndroidX=true" >> "$GRADLE_PROPS"
grep -q "org.gradle.jvmargs" "$GRADLE_PROPS" || echo "org.gradle.jvmargs=-Xmx1536m" >> "$GRADLE_PROPS"
grep -q "org.gradle.parallel" "$GRADLE_PROPS" || echo "org.gradle.parallel=false" >> "$GRADLE_PROPS"
```

touch creates the gradle.properties file if it does not already exist, without modifying it if it does. Each subsequent line follows the same pattern: grep -q searches for a setting name, and only if that setting is NOT already present (the || operator only runs the right-hand command if the left-hand command failed, i.e. grep found nothing) does it append the new setting. This means re-running the script will never create duplicate or conflicting settings.

- android.useAndroidX=true — required because the project's dependencies (AppCompat, Material Components) are all part of Google's modern AndroidX library family, which must be explicitly enabled.
- org.gradle.jvmargs=-Xmx1536m — caps the maximum heap size of the Gradle build process itself at 1.5 gigabytes, matching the GRADLE_OPTS value set earlier in .bashrc, to avoid exhausting memory on this machine.
- org.gradle.parallel=false — disables Gradle's parallel project execution. On a dual-core CPU, running multiple build tasks simultaneously often provides little benefit and can increase peak memory usage; disabling it favours stability over a marginal speed gain.

## 11.5 Clearing Stale Daemons and Caches

```bash
bash gradlew --stop 2>/dev/null || true
if [ -d "$HOME/.gradle/caches/${GRADLE_VERSION}" ]; then
    rm -rf "$HOME/.gradle/caches/${GRADLE_VERSION}"
fi
```

Gradle runs a background 'daemon' process to speed up repeated builds by keeping the JVM warm between invocations. If a previous build attempt ran under the wrong Java version (the major version 69 error), that daemon — and the cache of compiled build scripts it created — would be permanently corrupted from the perspective of the now-correct Java 17. bash gradlew --stop asks any running daemon to shut down cleanly; the 2>/dev/null || true ensures that if no daemon is running (and the command therefore errors), this is treated as a normal, non-fatal outcome. The subsequent rm -rf removes the cached build script compilations for this Gradle version specifically, forcing Gradle to recompile them fresh under the now-correctly-configured Java 17 on the next run.

# 12. Summary and Next Steps

At the end of its run, the script prints a boxed summary showing the resolved ANDROID_HOME, JAVA_HOME, build-tools version, platform version, and Gradle version, so the configuration can be verified at a glance. It then reminds the user that ~/.bashrc changes only apply to new shells, and — if a project directory was supplied — prints the exact three commands needed to build the project: navigating to the directory, sourcing .bashrc to load the new environment, and running bash gradlew assembleDebug.

This script is designed to be safely re-runnable: every step checks whether its work has already been done before repeating it, every download is verified before being trusted, and every modification to shared configuration files (.bashrc, gradle.properties) is guarded against duplication. This makes it suitable both for the initial setup of this machine and as a recovery tool if the build environment becomes corrupted in the future.

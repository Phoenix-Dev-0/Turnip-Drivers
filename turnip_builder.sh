#!/bin/bash -e

# ANSI color codes for output
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Required dependencies
deps="meson ninja patchelf unzip curl pip flex bison zip git"

# Directory and version variables
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r28"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

# Patches: array of strings in the format => "patch_name;patch_path;patch_args"
base_patches=(
    "Quest3;../../patches/quest3.patch;"
    "disable_VK_KHR_workgroup_memory_explicit_layout;../../patches/disable_KHR_workgroup_memory_explicit_layout.patch;"
)
experimental_patches=(
    "force_sysmem_no_autotuner;../../patches/force_sysmem_no_autotuner.patch;"
)
failed_patches=()
commit=""
commit_short=""
mesa_version=""
vulkan_version=""

clear  # Clear the terminal for better visibility

# Main function to run all steps
run_all() {
    check_deps
    prep "base"
    if (( ${#base_patches[@]} )); then
        prep "patched"
    fi
    if (( ${#experimental_patches[@]} )); then
        prep "experimental"
    fi
}

# Prepare working directory and build
prep() {
    prepare_workdir "$1"
    build_lib_for_android
    port_lib_for_adrenotool "$1"
}

# Check for required dependencies
check_deps() {
    echo "Checking system for required dependencies..."
    sudo apt remove meson &>/dev/null
    pip install meson PyYAML &>/dev/null

    for dep in $deps; do
        sleep 0.25
        if command -v "$dep" >/dev/null 2>&1; then
            echo -e "${green} - $dep found${nocolor}"
        else
            echo -e "${red} - $dep not found, please install it.${nocolor}"
            missing_deps=1
        fi
    done

    if [[ "$missing_deps" == "1" ]]; then
        echo "Please install the missing dependencies." && exit 1
    fi

    echo "Installing Python Mako dependency..."
    pip install mako &>/dev/null
}

# Prepare working directory and clone Mesa
prepare_workdir() {
    echo "Setting up work directory..."
    mkdir -p "$workdir" && cd "$workdir"

    if [[ -z "${ANDROID_NDK_LATEST_HOME}" ]]; then
        if [[ ! -d "$ndkver" ]]; then
            echo "Downloading Android NDK (~640MB)..."
            curl -O https://dl.google.com/android/repository/"$ndkver"-linux.zip &>/dev/null
            echo "Extracting Android NDK..."
            unzip "$ndkver"-linux.zip &>/dev/null
        fi
    else
        echo "Using Android NDK from environment variable."
    fi

    if [[ -z "$1" ]]; then
        if [[ -d mesa ]]; then
            echo "Removing old Mesa directory..."
            rm -rf mesa
        fi
        echo "Cloning Mesa repository..."
        git clone --depth=1 "$mesasrc"

        cd mesa
        collect_mesa_info
    else
        cd mesa
        if [[ $1 == "patched" ]]; then
            apply_patches "${base_patches[@]}"
        else
            apply_patches "${experimental_patches[@]}"
        fi
    fi
}

# Gather Mesa version and Vulkan information
collect_mesa_info() {
    commit_short=$(git rev-parse --short HEAD)
    commit=$(git rev-parse HEAD)
    mesa_version=$(cat VERSION | xargs)
    vulkan_version=$(awk -F'COMPLETE VK_MAKE_API_VERSION(|)' '{print $2}' include/vulkan/vulkan_core.h | xargs)
}

# Apply patches
apply_patches() {
    local patches=("$@")
    for patch in "${patches[@]}"; do
        local patch_name=$(echo "$patch" | cut -d ";" -f 1 | xargs)
        local patch_source=$(echo "$patch" | cut -d ";" -f 2 | xargs)
        local patch_args=$(echo "$patch" | cut -d ";" -f 3 | xargs)

        echo "Applying patch: $patch_name"
        if [[ $patch_source == *"../.."* ]]; then
            if git apply $patch_args "$patch_source"; then
                echo "Patch applied successfully."
            else
                echo "Failed to apply $patch_name."
                failed_patches+=("$patch")
            fi
        else
            patch_file="${patch_source##*/}"
            curl --output "../$patch_file.patch" -k --retry 5 "https://gitlab.freedesktop.org/mesa/mesa/-/$patch_source.patch"
            if git apply $patch_args "../$patch_file.patch"; then
                echo "Patch applied successfully."
            else
                echo "Failed to apply $patch_name."
                failed_patches+=("$patch")
            fi
        fi
    done
}

# Build Mesa library for Android
build_lib_for_android() {
    echo "Generating Meson cross file..."
    if [[ -z "${ANDROID_NDK_LATEST_HOME}" ]]; then
        ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
    else
        ndk="$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    fi

    cat <<EOF >"android-aarch64"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ndk/aarch64-linux-android-strip'
pkgconfig = ['/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    echo "Building Mesa for Android..."
    meson build-android-aarch64 --cross-file android-aarch64 \
        -Dbuildtype=release -Dplatforms=android -Dgallium-drivers= -Dvulkan-drivers=freedreno &>/dev/null
    ninja -C build-android-aarch64 &>/dev/null
}

# Port and package library for Adreno tool
port_lib_for_adrenotool() {
    echo "Using patchelf to adjust soname..."
    cp build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
    cd "$workdir"
    patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
    mv libvulkan_freedreno.so vulkan.ad07XX.so

    if [[ ! -f vulkan.ad07XX.so ]]; then
        echo -e "${red}Build failed!${nocolor}" && exit 1
    fi

    echo "Packaging for Adreno tool..."
    package_files "$1"
}

# Package files into a zip for release
package_files() {
    local suffix=""
    [[ -n "$1" ]] && suffix="_$1"
    mkdir -p "$packagedir" && cd "$packagedir"

    local date=$(date +'%b %d, %Y')
    local filename="turnip_$(date +'%b-%d-%Y')_$commit_short$suffix"

    # Generate meta.json for packaging
    cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip - $date - $commit_short$suffix",
  "description": "Compiled from Mesa, Commit $commit_short$suffix",
  "author": "mesa",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "$mesa_version/vk$vulkan_version",
  "minApi": 27,
  "libraryName": "vulkan.ad07XX.so"
}
EOF

    echo "Copying necessary files..."
    cp "$workdir"/vulkan.ad07XX.so "$packagedir"
    zip -9 "$workdir"/"$filename$suffix".zip ./*

    if [[ ! -f "$workdir/$filename.zip" ]]; then
        echo -e "${red}Packing failed!${nocolor}" && exit 1
    else
        echo -e "${green}All done! Your zip file is ready.${nocolor} Location: $workdir"
    fi
}

# Run all steps
run_all

#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r27"
sdkver="33"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

# Array of patches: "commit/branch;patch args"
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

run_all() {
    check_deps
    prep

    if (( ${#base_patches[@]} )); then
        prep "patched"
    fi

    if (( ${#experimental_patches[@]} )); then
        prep "experimental"
    fi
}

prep() {
    prepare_workdir "$1"
    build_lib_for_android
    port_lib_for_adrenotool "$1"
}

check_deps() {
    sudo apt remove meson
    pip install meson PyYAML

    echo "Checking system for required dependencies ..."
    for dep in $deps; do
        sleep 0.25
        if command -v "$dep" >/dev/null 2>&1; then
            echo -e "$green - $dep found $nocolor"
        else
            echo -e "$red - $dep not found, can't continue. $nocolor"
            deps_missing=1
        fi
    done

    if [ "$deps_missing" == "1" ]; then
        echo "Please install missing dependencies" && exit 1
    fi

    echo "Installing Python Mako dependency..."
    pip install mako &> /dev/null
}

prepare_workdir() {
    echo "Creating work directory..." $'\n'
    mkdir -p "$workdir" && cd "$_"

    if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
        if [ ! -n "$(ls -d android-ndk*)" ]; then
            echo "Downloading Android NDK..." $'\n'
            curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
            echo "Extracting Android NDK..." $'\n'
            unzip "$ndkver"-linux.zip &> /dev/null
        fi
    else
        echo "Using Android NDK from environment variable"
    fi

    if [ -z "$1" ]; then
        if [ -d mesa ]; then
            echo "Removing old mesa..." $'\n'
            rm -rf mesa
        fi
        echo "Cloning mesa repository..." $'\n'
        git clone --depth=1 "$mesasrc"
        cd mesa
        commit_short=$(git rev-parse --short HEAD)
        commit=$(git rev-parse HEAD)
        mesa_version=$(cat VERSION | xargs)
        version=$(awk -F'COMPLETE VK_MAKE_API_VERSION(|)' '{print $2}' <<< $(cat include/vulkan/vulkan_core.h) | xargs)
        major=$(echo $version | cut -d "," -f 2 | xargs)
        minor=$(echo $version | cut -d "," -f 3 | xargs)
        patch=$(awk -F'VK_HEADER_VERSION |\n#define' '{print $2}' <<< $(cat include/vulkan/vulkan_core.h) | xargs)
        vulkan_version="$major.$minor.$patch"
    else
        cd mesa
        if [ $1 == "patched" ]; then
            apply_patches "${base_patches[@]}"
        else
            apply_patches "${experimental_patches[@]}"
        fi
    fi
}

apply_patches() {
    local arr=("$@")
    for patch in "${arr[@]}"; do
        echo "Applying patch $patch"
        patch_source="$(echo $patch | cut -d ";" -f 2 | xargs)"
        patch_args=$(echo $patch | cut -d ";" -f 3 | xargs)

        if [[ $patch_source == *"../.."* ]]; then
            if git apply $patch_args "$patch_source"; then
                echo "Patch applied successfully"
            else
                echo "Failed to apply $patch"
                failed_patches+=("$patch")
            fi
        else
            patch_file="${patch_source#*/}"
            curl --output "../$patch_file.patch" -k --retry-delay 30 --retry 5 -f --retry-all-errors https://gitlab.freedesktop.org/mesa/mesa/-/"$patch_source".patch
            sleep 1

            if git apply $patch_args "../$patch_file.patch"; then
                echo "Patch applied successfully"
            else
                echo "Failed to apply $patch"
                failed_patches+=("$patch")
            fi
        fi
    done
}

build_lib_for_android() {
    echo "Creating meson cross file..." $'\n'
    if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
        ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
    else
        ndk="$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
    fi

    cat <<EOF >"android-aarch64"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ndk/aarch64-linux-android-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=NDKDIR/pkgconfig', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    echo "Generating build files..." $'\n'
    meson build-android-aarch64 --cross-file "$workdir"/mesa/android-aarch64 -Dbuildtype=release -Dplatforms=android -Dplatform-sdk-version=$sdkver -Dandroid-stub=true -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Db_lto=true &> "$workdir"/meson_log

    echo "Compiling build files..." $'\n'
    ninja -C build-android-aarch64 &> "$workdir"/ninja_log
}

port_lib_for_adrenotool() {
    echo "Using patchelf to match soname..." $'\n'
    cp "$workdir"/mesa/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
    cd "$workdir"
    patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
    mv libvulkan_freedreno.so vulkan.ad07XX.so

    if ! [ -a vulkan.ad07XX.so ]; then
        echo -e "$red Build failed! $nocolor" && exit 1
    fi

    mkdir -p "$packagedir" && cd "$_"
    date=$(date +'%b %d, %Y')
    suffix=""

    if [ ! -z "$1" ]; then
        suffix="_$1"
    fi

    # Ensure description file is created
    if [ ! -f "$workdir/description" ]; then
        echo "Description file not found, creating an empty description."
        touch "$workdir/description"
    fi

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

    filename=turnip_"$(date +'%b-%d-%Y')"_"$commit_short"
    echo "Copying necessary files..." $'\n'
    cp "$workdir"/vulkan.ad07XX.so "$packagedir"

    echo "Packing files into a zip..." $'\n'
    zip -9 "$workdir"/"$filename$suffix".zip ./*

    # Ensure the zip file exists
    if [ ! -f "$workdir/$filename$suffix.zip" ]; then
        echo "ZIP file not created, build might have failed."
        exit 1
    fi

    if (( ${#failed_patches[@]} )); then
        echo "#### Failed patches" >> description
        patch_to_description "${failed_patches[@]}"
    fi

    if ! [ -a "$workdir/$filename.zip" ]; then
        echo -e "$red-Packing failed!$nocolor" && exit 1
    else
        echo -e "$green-All done!$nocolor"
        echo "$workdir/"
    fi
}

run_all

#!/bin/bash -e

# Color definitions
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Dependencies and configurations
deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r26c"
sdkver="33"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

# Array of patches with source and arguments
patches=(
	"visual-fix-issues-in-some-games-1;merge_requests/27986;--reverse"
	"visual-fix-issues-in-some-games-2;commit/9de628b65ca36b920dc6181251b33c436cad1b68;--reverse"
	"visual-fix-issues-in-some-game-3;merge_requests/28148;--reverse"
	"8gen3-fix;merge_requests/27912;--reverse"
	"mem-leaks-tu-shader;merge_requests/27847;--reverse"
	"add-RMV-Support;commit/a13860e5dfd0cf28ff5292b410d5be44791ca7cc;--reverse"
	"fix-color-buffer;commit/782fb8966bd59a40b905b17804c493a76fdea7a0;--reverse"
	"Fix-undefined-value-gl_ClipDistance;merge_requests/28109;--reverse"
	"tweak-attachment-validation;merge_requests/28135;--reverse"
	"Fix-undefined-value-gl_ClipDistance;merge_requests/28109;"
	"Add-PC_TESS_PARAM_SIZE-PC_TESS_FACTOR_SIZE;merge_requests/28210;"
	"Dont-fast-clear-z-isNotEq-s;merge_requests/28249;"
	"disable-gmem;commit/1ba6ccc51a4483a6d622c91fc43685150922dcdf;--reverse"
	"KHR_8bit_storage-support-fix-games-a7xx-break-some-a6xx;merge_requests/28254;"
	"disable-gmem;commit/1ba6ccc51a4483a6d622c91fc43685150922dcdf;--reverse"
)

commit=""
commit_short=""
mesa_version=""
vulkan_version=""

clear

# Main function to run all steps
run_all() {
	check_deps
	prepare_workdir
	build_lib_for_android
	port_lib_for_adrenotool

	if (( ${#patches[@]} )); then
		prepare_workdir "patched"
		build_lib_for_android
		port_lib_for_adrenotool "patched"
	fi
}

# Check and install dependencies
check_deps() {
	echo "Checking system for required Dependencies ..."
	for dep in $deps; do
		if ! command -v "$dep" >/dev/null 2>&1; then
			echo -e "$red - $dep not found, can't continue. $nocolor"
			deps_missing=1
		else
			echo -e "$green - $dep found $nocolor"
		fi
	done

	[ "$deps_missing" == "1" ] && echo "Please install missing dependencies" && exit 1

	echo "Installing python Mako dependency (if missing) ..."
	pip install mako &> /dev/null
}

# Prepare working directory and clone mesa
prepare_workdir() {
	echo "Creating and entering to work directory ..."
	mkdir -p "$workdir" && cd "$_"

	if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
		[ ! -d "$ndkver" ] && {
			echo "Downloading android-ndk from google server (~640 MB) ..."
			curl -sSLO https://dl.google.com/android/repository/"$ndkver"-linux.zip
			echo "Extracting android-ndk to a folder ..."
			unzip -q "$ndkver"-linux.zip
		}
	else	
		echo "Using android ndk from environment variable"
	fi

	[ -z "$1" ] && {
		[ -d mesa ] && rm -rf mesa
		echo "Cloning mesa ..."
		git clone --depth=1 "$mesasrc" mesa &> /dev/null
		cd mesa
		commit_short=$(git rev-parse --short HEAD)
		commit=$(git rev-parse HEAD)
		mesa_version=$(<VERSION xargs)
		vulkan_version=$(awk -F'COMPLETE VK_MAKE_API_VERSION(|)' '{print $2}' include/vulkan/vulkan_core.h | xargs | awk -F, '{print $2 "." $3 "." $4}')
	} || {
		cd mesa
		for patch in "${patches[@]}"; do
			patch_source=$(echo $patch | cut -d ";" -f 2)
			patch_file="${patch_source#*/}"
			patch_args=$(echo $patch | cut -d ";" -f 3)
			curl -sSLO "https://gitlab.freedesktop.org/mesa/mesa/-/$patch_source.patch"
			git apply $patch_args "$patch_file.patch"
		done
	}
}

# Build library for Android
build_lib_for_android() {
	echo "Creating meson cross file ..."
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

	echo "Generating build files ..."
	meson build-android-aarch64 --prefix=/tmp/mesa --cross-file "$workdir/android-aarch64" -Dbuildtype=release -Dplatforms=android -Dplatform-sdk-version=25 -Dandroid-stub=true -Degl=disabled -Dgbm=disabled -Dglx=disabled -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Db_lto=true &> "$workdir/meson_log"

	echo "Compiling build files ..."
	ninja -C build-android-aarch64 &> "$workdir/ninja_log"
}

# Port library for AdrenoTool
port_lib_for_adrenotool() {
	echo "Using patchelf to match soname ..."
	cp "$workdir/mesa/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so" "$workdir"
	cd "$workdir"
	patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
	mv libvulkan_freedreno.so vulkan.ad06XX.so

	[ ! -f vulkan.ad06XX.so ] && echo -e "$red Build failed! $nocolor" && exit 1

	mkdir -p "$packagedir" && cd "$_"

	date=$(date +'%b %d, %Y')
	patched=""
	[ ! -z "$1" ] && patched="_patched"

	cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip - $date - $commit_short$patched",
  "description": "Compiled from Mesa, Commit $commit_short$patched",
  "author": "mesa",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "$mesa_version/vk$vulkan_version",
  "minApi": 27,
  "libraryName": "vulkan.ad06XX.so"
}
EOF
}

# Run all steps
run_all
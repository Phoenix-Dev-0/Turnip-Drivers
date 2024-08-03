#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r27"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

#array of string => commit/branch;patch args
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
)
#patches=()
commit=""
commit_short=""
mesa_version=""
vulkan_version=""
clear

# there are 4 functions here, simply comment to disable.
# you can insert your own function and make a pull request.
run_all(){
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

check_deps(){
	sudo apt remove meson
	pip install meson

	echo "Checking system for required Dependencies ..."
	for deps_chk in $deps;
		do
			sleep 0.25
			if command -v "$deps_chk" >/dev/null 2>&1 ; then
				echo -e "$green - $deps_chk found $nocolor"
			else
				echo -e "$red - $deps_chk not found, can't countinue. $nocolor"
				deps_missing=1
			fi;
		done

		if [ "$deps_missing" == "1" ]
			then echo "Please install missing dependencies" && exit 1
		fi

	echo "Installing python Mako dependency (if missing) ..." $'\n'
	pip install mako &> /dev/null
}

prepare_workdir(){
	echo "Creating and entering to work directory ..." $'\n'
	mkdir -p "$workdir" && cd "$_"

	if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
		if [ ! -n "$(ls -d android-ndk*)" ]; then
			echo "Downloading android-ndk from google server (~640 MB) ..." $'\n'
			curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
			###
			echo "Exracting android-ndk to a folder ..." $'\n'
			unzip "$ndkver"-linux.zip  &> /dev/null
		fi
	else	
		echo "Using android ndk from github image"
	fi

	if [ -z "$1" ]; then
		if [ -d mesa ]; then
			echo "Removing old mesa ..." $'\n'
			rm -rf mesa
		fi
		
		echo "Cloning mesa ..." $'\n'
		git clone --depth=1 "$mesasrc"  &> /dev/null

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
		if [ -z ${experimental_patches+x} ]; then
			echo "No experimental patches found"; 
		else 
			patches=("${experimental_patches[@]}" "${patches[@]}")
		fi

		cd mesa
		for patch in ${patches[@]}; do
			echo "Applying patch $patch"
			patch_source="$(echo $patch | cut -d ";" -f 2 | xargs)"
			patch_file="${patch_source#*\/}"
			patch_args=$(echo $patch | cut -d ";" -f 3 | xargs)
			curl --output "$patch_file".patch -k --retry 5  https://gitlab.freedesktop.org/mesa/mesa/-/"$patch_source".patch
		
			git apply $patch_args "$patch_file".patch
		done
	fi
}

build_lib_for_android(){
	echo "Creating meson cross file ..." $'\n'
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

        cat <<EOF >"android-arm32"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang++', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android

# Also, include the plain DRM lib we found earlier. Panfrost relies on it rather heavily, especially when
# interacting with the panfrost DRM module and not kbase

pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.:/tmp/drm-static/lib/pkgconfig', '/usr/bin/pkg-config']

[host_machine]
system = 'linux'
# cpu_family = 'x86_64'
# cpu = 'amd64'

# ik this is wrong but workaround sanity check
cpu_family = 'arm'
cpu = 'armv7'

endian = 'little'
EOF

        cat <<EOF >"android-drm-aarch64"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang++', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android

# Also, include the plain DRM lib we found earlier. Panfrost relies on it rather heavily, especially when
# interacting with the panfrost DRM module and not kbase

pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.:/tmp/drm-static/lib/pkgconfig', '/usr/bin/pkg-config']

[host_machine]
system = 'linux'
# cpu_family = 'x86_64'
# cpu = 'amd64'

# ik this is wrong but workaround sanity check
cpu_family = 'arm'
cpu = 'armv7'

endian = 'little'
EOF

        cat <<EOF >"android-drm-arm32"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang++', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.', '/usr/bin/pkg-config']

[host_machine]
system = 'linux'
# cpu_family = 'x86_64'
# cpu = 'amd64'

# ik this is wrong but workaround sanity check
cpu_family = 'arm'
cpu = 'armv7'

endian = 'little'
EOF

        cat <<EOF >"android-drm-x86_64"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang++', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.', '/usr/bin/pkg-config']

[host_machine]
system = 'linux'
# cpu_family = 'x86_64'
# cpu = 'amd64'

# ik this is wrong but workaround sanity check
cpu_family = 'arm'
cpu = 'armv8'


endian = 'little'
EOF

        cat <<EOF >"android-turnip-aarch64"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

        cat <<EOF >"android-turnip-arm32"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7'
endian = 'little'
EOF

        cat <<EOF >"android-turnip-x86_64"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'x86_64'
cpu = 'amd64'
endian = 'little'
EOF

        cat <<EOF >"android-x86_64"
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android26-clang++', '-O3', '-DVK_USE_PLATFORM_ANDROID_KHR', '-fPIC', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
# Android doesn't come with a pkg-config, but we need one for meson to be happy not
# finding all the optional deps it looks for.  Use system pkg-config pointing at a
# directory we get to populate with any .pc files we want to add for Android

# Also, include the plain DRM lib we found earlier. Panfrost relies on it rather heavily, especially when
# interacting with the panfrost DRM module and not kbase

pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=.:/tmp/drm-static/lib/pkgconfig', '/usr/bin/pkg-config']

[host_machine]
system = 'linux'
# cpu_family = 'x86_64'
# cpu = 'amd64'

# ik this is wrong but workaround sanity check
cpu_family = 'arm'
cpu = 'armv8'


endian = 'little'
EOF


	echo "Generating build files ..." $'\n'
	meson build-android-aarch64 --prefix=/tmp/mesa --cross-file "$workdir"/mesa/android-aarch64 -Dbuildtype=release -Dplatforms=android -Dplatform-sdk-version=25 -Dandroid-stub=true -Degl=disabled -Dgbm=disabled -Dglx=disabled -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Db_lto=true &> "$workdir"/meson_log

	echo "Compiling build files ..." $'\n'
	ninja -C build-android-aarch64 &> "$workdir"/ninja_log

        echo "Generating build files ..." $'\n'
	meson build-android-aarch64 --cross-file "$workdir"/mesa/android-aarch64 -Dbuildtype=release -Dplatforms=android -Dplatform-sdk-version=$sdkver -Dandroid-stub=true -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dvulkan-beta=true -Dfreedreno-kmds=kgsl -Db_lto=true &> "$workdir"/meson_log

	echo "Compiling build files ..." $'\n'
	ninja -C build-android-aarch64 &> "$workdir"/ninja_log

}

port_lib_for_adrenotool(){
	echo "Using patchelf to match soname ..."  $'\n'
	cp "$workdir"/mesa/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
	cd "$workdir"
	patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
	mv libvulkan_freedreno.so vulkan.ad06XX.so

	if ! [ -a vulkan.ad06XX.so ]; then
		echo -e "$red Build failed! $nocolor" && exit 1
	fi

	mkdir -p "$packagedir" && cd "$_"

	date=$(date +'%b %d, %Y')
	patched=""

	if [ ! -z "$1" ]; then
		patched="_patched"
	fi

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

	filename=turnip_"$(date +'%b-%d-%Y')"_"$commit_short"
	echo "Copy necessary files from work directory ..." $'\n'
	cp "$workdir"/vulkan.ad06XX.so "$packagedir"

	echo "Packing files in to adrenotool package ..." $'\n'
	zip -9 "$workdir"/"$filename$patched".zip ./*

	cd "$workdir"
	
	echo "Turnip - $mesa_version - $date" > release
	echo "$mesa_version"_"$commit_short" > tag
	echo  $filename > filename
	echo "### Base commit : [$commit_short](https://gitlab.freedesktop.org/mesa/mesa/-/commit/$commit_short)" > description
	echo "## Upstreams / Patches" >> description
	
	if (( ${#patches[@]} )); then
		echo "These have not been merged by Mesa officially yet and may introduce bugs or" >> description
		echo "we revert stuff that breaks games but still got merged in (see --reverse)" >> description
		for patch in ${patches[@]}; do
			patch_name="$(echo $patch | cut -d ";" -f 1 | xargs)"
			patch_source="$(echo $patch | cut -d ";" -f 2 | xargs)"
			patch_args="$(echo $patch | cut -d ";" -f 3 | xargs)"
			echo "- $patch_name, [$patch_source](https://gitlab.freedesktop.org/mesa/mesa/-/$patch_source), $patch_args" >> description
		done
		echo "true" > patched
		echo "" >> description
		echo "_Upstreams / Patches are only applied to the patched version (\_patched.zip)_" >> description
	else
		echo "No patch" >> description
		echo "false" > patched
	fi
	
	echo "_If a patch is not present anymore, it's most likely because it got merged, is not needed anymore or was breaking something._" >> description

        echo "## Tested On Android 11+" >> description

	if ! [ -a "$workdir"/"$filename".zip ];
		then echo -e "$red-Packing failed!$nocolor" && exit 1
		else echo -e "$green-All done, you can take your zip from this folder;$nocolor" && echo "$workdir"/
	fi
}

run_all

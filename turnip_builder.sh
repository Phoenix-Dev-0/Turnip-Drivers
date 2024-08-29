#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r26"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"
mesabranch="24.2"

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
		
		echo "Cloning mesa from branch $mesabranch ..." $'\n'
		git clone --depth=1 --branch "$mesabranch" "$mesasrc" mesa &> /dev/null

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

	# (rest of the build_lib_for_android function remains unchanged)
}

port_lib_for_adrenotool(){
	# (rest of the port_lib_for_adrenotool function remains unchanged)
}

run_all

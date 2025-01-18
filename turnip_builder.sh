#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r28"
sdkver="35"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

# Updated patches array with current versions and proper ordering
patches=(
	# Core functionality patches
	"disable-gmem;commit/1ba6ccc51a4483a6d622c91fc43685150922dcdf;--reverse"
	"fix-color-buffer;commit/782fb8966bd59a40b905b17804c493a76fdea7a0;--reverse"
	
	# Feature patches - applied after core patches
	"Fix-undefined-value-gl_ClipDistance;merge_requests/28109;--reverse"
	"tweak-attachment-validation;merge_requests/28135;--reverse"
	"Add-PC_TESS_PARAM_SIZE-PC_TESS_FACTOR_SIZE;merge_requests/28210;"
	"Dont-fast-clear-z-isNotEq-s;merge_requests/28249;"
	"KHR_8bit_storage-support-fix-games-a7xx-break-some-a6xx;merge_requests/28254;"
)

commit=""
commit_short=""
mesa_version=""
vulkan_version=""
clear

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
	local suffix=$1
	echo "Creating and entering to work directory ..." $'\n'
	mkdir -p "$workdir" && cd "$_"

	if [ -z "${ANDROID_NDK_ROOT}" ]; then
		if [ ! -n "$(ls -d android-ndk*)" ]; then
			echo "Downloading android-ndk from google server (~640 MB) ..." $'\n'
			curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
			echo "Extracting android-ndk to a folder ..." $'\n'
			unzip "$ndkver"-linux.zip  &> /dev/null
		fi
		export ANDROID_NDK_ROOT="$workdir/$ndkver"
	fi

	if [ ! -d "mesa" ]; then
		echo "Cloning mesa repository ..." $'\n'
		git clone $mesasrc &> /dev/null
	fi

	cd mesa
	git reset --hard HEAD &> /dev/null
	git clean -f -d &> /dev/null

	if [ -z "$commit" ]; then
		echo "Getting latest mesa version ..." $'\n'
		git pull &> /dev/null
		commit=$(git rev-parse HEAD)
	else
		echo "Checking out specified commit ..." $'\n'
		git checkout $commit &> /dev/null
	fi

	commit_short=$(git rev-parse --short HEAD)
	mesa_version=$(cat VERSION)
	vulkan_version=$(cat src/vulkan/runtime/vk_common_entrypoints.h | grep -oP "(?<=VK_VERSION_).*(?=_MAJOR)" | head -1)

	if (( ${#patches[@]} )); then
		echo "No experimental patches found"
		for patch in "${patches[@]}"; do
			IFS=';' read -r name path reverse <<< "$patch"
			echo "Applying patch $name;$path;$reverse"
			curl -L "$mesasrc/-/raw/$path" | git apply $reverse -
		done
	fi
}

build_lib_for_android(){
	echo -e "Creating meson cross file ... \n"
	cat > android-aarch64 << EOF
[binaries]
ar = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
c = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android$sdkver-clang++']
c_ld = 'lld'
cpp_ld = 'lld'
strip = '$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkgconfig = ['env', 'PKG_CONFIG_LIBDIR=$ANDROID_NDK_ROOT/pkgconfig', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

	echo -e "Generating build files ... \n"
	meson setup build-android-aarch64 \
		--cross-file android-aarch64 \
		-Dplatforms=android \
		-Ddri-drivers= \
		-Dgallium-drivers= \
		-Dvulkan-drivers=freedreno \
		-Dandroid-stub=true \
		-Dllvm=disabled \
		-Dxlib-lease=disabled \
		-Dglx=disabled \
		-Degl=disabled \
		-Dgbm=disabled \
		-Dtools= \
		-Dzlib=enabled \
		-Dshared-llvm=disabled \
		-Dbuildtype=release \
		-Db_lto=true \
		-Dprefix=/usr/local

	echo -e "Compiling build files ... \n"
	ninja -C build-android-aarch64 libvulkan_freedreno.so

	echo -e "Using patchelf to match soname ... \n"
	cp build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so ./libvulkan_freedreno.so
	patchelf --set-soname "libvulkan_freedreno.so" libvulkan_freedreno.so
	mv libvulkan_freedreno.so $workdir/
}

port_lib_for_adrenotool() {
	local suffix=$1
	echo -e "Copy necessary files from work directory ... \n"
	cp $workdir/libvulkan_freedreno.so $workdir/vulkan.ad06XX.so

	echo -e "Packing files in to adrenotool package ... \n"
	cd $workdir
	
	# Create meta.json with version info
	cat > meta.json << EOF
{
	"name": "Turnip",
	"version": "${mesa_version}${suffix:+-$suffix}",
	"author": "Mesa",
	"description": "Open source Vulkan driver for Adreno GPU",
	"vulkan_support": "$vulkan_version",
	"devices_support": "Adreno 6xx series"
}
EOF
	
	zip -u turnip${suffix:+-$suffix}.zip vulkan.ad06XX.so meta.json
	echo -e "${green}-All done, you can take your zip from this folder;${nocolor}"
	echo "$workdir/"
}

run_all

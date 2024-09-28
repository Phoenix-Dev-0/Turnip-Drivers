# Turnip Vulkan Driver Build Script

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Build](https://img.shields.io/badge/build-passing-brightgreen.svg)

## Overview

This project provides a script to build and package the Turnip Vulkan driver from the Mesa source code for Android. The script automates the process of setting up the environment, checking dependencies, downloading and preparing the Android NDK, cloning the Mesa repository, applying patches, and compiling the Vulkan driver for Adreno GPUs.

## Features

- **Automated Dependency Checking**: Ensures all necessary tools and libraries are installed.
- **Environment Setup**: Prepares the working directory and handles the Android NDK setup.
- **Mesa Cloning and Patching**: Clones the Mesa repository and applies specified patches.
- **Building for Android**: Compiles the Turnip Vulkan driver using Meson and Ninja.
- **Packaging**: Packages the built driver with metadata for easy distribution and usage.

## Prerequisites

Ensure the following dependencies are installed on your system:

- `meson`
- `ninja`
- `patchelf`
- `unzip`
- `curl`
- `pip`
- `flex`
- `bison`
- `zip`
- `git`
- `ccache`

## Installation

Clone the repository and navigate to the project directory:

```sh
git clone https://github.com/Phoenix-Dev-0/Turnip-Drivers.git
cd Turnip-Drivers
```

## Usage

Run the script to start the build process:

```sh
./build_turnip.sh
```

The script will:

1. Check and install dependencies.
2. Prepare the working directory and Android NDK.
3. Clone the Mesa repository and apply patches.
4. Build the Turnip Vulkan driver for Android.
5. Package the built driver with metadata.

## Configuration

You can configure various parameters in the script:

- `ndkver`: Version of the Android NDK to use.
- `sdkver`: Android SDK version.
- `mesasrc`: URL of the Mesa source repository.
- `patches`: Array of patches to apply, with each entry containing the patch description, source, and arguments.

## Output

The built Vulkan driver and metadata will be packaged in the `turnip_module` directory within your working directory.

## Example

```json
{
  "schemaVersion": 1,
  "name": "Turnip - Jul 30, 2024 - abc1234",
  "description": "Compiled from Mesa, Commit abc1234",
  "author": "mesa",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "23.1.0/vk1.2.3",
  "minApi": 27,
  "libraryName": "vulkan.ad06XX.so"
}
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any changes or improvements.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Here’s an updated version of the **Acknowledgements** section to include the additional credits:

---

## Acknowledgements

- [Mesa 3D Graphics Library](https://mesa3d.org/)
- [Android NDK](https://developer.android.com/ndk)
- [Weab-chan](https://github.com/Weab-chan) - [Freedreno Turnip CI](https://github.com/Weab-chan/freedreno_turnip-CI)
- [K11MCH1](https://github.com/K11MCH1) - [Adreno Tools Drivers](https://github.com/K11MCH1/AdrenoToolsDrivers)

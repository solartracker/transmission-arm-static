#!/bin/sh
################################################################################
# transmission-arm-musl.sh
#
# Copyright (C) 2025 Richard Elwell
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################
PATH_CMD="$(readlink -f -- "$0")"
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "$0")")"
PARENT_DIR="$(dirname -- "$(dirname -- "$(readlink -f -- "$0")")")"
CACHED_DIR="${PARENT_DIR}/solartracker-sources"
set -e
set -x

################################################################################
# Helpers

# If autoconf/configure fails due to missing libraries or undefined symbols, you
# immediately see all undefined references without having to manually search config.log
handle_configure_error() {
    local rc=$1

    #grep -R --include="config.log" --color=always "undefined reference" .
    #find . -name "config.log" -exec grep -H "undefined reference" {} \;
    #find . -name "config.log" -exec grep -H -E "undefined reference|can't load library|unrecognized command-line option|No such file or directory" {} \;
    find . -name "config.log" -exec grep -H -E "undefined reference|can't load library|unrecognized command-line option" {} \;

    # Force failure if rc is zero, since error was detected
    [ "${rc}" -eq 0 ] && return 1

    return ${rc}
}

################################################################################
# Package management

# new files:       rw-r--r-- (644)
# new directories: rwxr-xr-x (755)
umask 022

sign_file()
( # BEGIN sub-shell
    [ -n "$1" ]            || return 1

    local target_path="$1"
    local option="$2"
    local sign_path="$(readlink -f "${target_path}").sha256"
    local target_file="$(basename -- "${target_path}")"
    local target_file_hash=""
    local temp_path=""
    local now_localtime=""

    if [ ! -f "${target_path}" ]; then
        echo "ERROR: File not found: ${target_path}"
        return 1
    fi

    if [ -z "${option}" ]; then
        target_file_hash="$(sha256sum "${target_path}" | awk '{print $1}')"
    elif [ "${option}" == "tar_extract" ]; then
        target_file_hash="$(tar -xJOf "${target_path}" | sha256sum | awk '{print $1}')"
    elif [ "${option}" == "xz_extract" ]; then
        target_file_hash="$(xz -dc "${target_path}" | sha256sum | awk '{print $1}')"
    else
        return 1
    fi

    now_localtime="$(date '+%Y-%m-%d %H:%M:%S %Z %z')"

    cleanup() { rm -f "${temp_path}"; }
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM
    trap 'cleanup' EXIT
    temp_path=$(mktemp "${sign_path}.XXXXXX")
    {
        #printf '%s released %s\n' "${target_file}" "${now_localtime}"
        #printf '\n'
        #printf 'SHA256: %s\n' "${target_file_hash}"
        #printf '\n'
        printf '%s  %s\n' "${target_file_hash}" "${target_file}"
    } >"${temp_path}" || return 1
    touch -r "${target_path}" "${temp_path}" || return 1
    mv -f "${temp_path}" "${sign_path}" || return 1
    # TODO: implement signing
    trap - EXIT INT TERM

    return 0
) # END sub-shell

# Checksum verification for downloaded file
verify_hash() {
    [ -n "$1" ] || return 1

    local file_path="$1"
    local expected="$2"
    local option="$3"
    local actual=""
    local sign_path="$(readlink -f "${file_path}").sha256"
    local line=""

    if [ ! -f "${file_path}" ]; then
        echo "ERROR: File not found: ${file_path}"
        return 1
    fi

    if [ -z "${option}" ]; then
        # hash the compressed binary file. this method is best when downloading
        # compressed binary files.
        actual="$(sha256sum "${file_path}" | awk '{print $1}')"
    elif [ "${option}" == "tar_extract" ]; then
        # hash the data, file names, directory names. this method is best when
        # archiving Github repos.
        actual="$(tar -xJOf "${file_path}" | sha256sum | awk '{print $1}')"
    elif [ "${option}" == "xz_extract" ]; then
        # hash the data, file names, directory names, timestamps, permissions, and
        # tar internal structures. this method is not as "future-proof" for archiving
        # Github repos because it is possible that the tar internal structures
        # could change over time as the tar implementations evolve.
        actual="$(xz -dc "${file_path}" | sha256sum | awk '{print $1}')"
    else
        return 1
    fi

    if [ -z "${expected}" ]; then
        if [ ! -f "${sign_path}" ]; then
            echo "ERROR: Signature file not found: ${sign_path}"
            return 1
        else
            # TODO: implement signature verify
            IFS= read -r line <"${sign_path}" || return 1
            expected=${line%%[[:space:]]*}
            if [ -z "${expected}" ]; then
                echo "ERROR: Bad signature file: ${sign_path}"
                return 1
            fi
        fi
    fi

    if [ "${actual}" != "${expected}" ]; then
        echo "ERROR: SHA256 mismatch for ${file_path}"
        echo "Expected: ${expected}"
        echo "Actual:   ${actual}"
        return 1
    fi

    echo "SHA256 OK: ${file_path}"
    return 0
}

retry() {
    local max=$1
    shift
    local i=1
    while :; do
        if ! "$@"; then
            if [ "${i}" -ge "${max}" ]; then
                return 1
            fi
            i=$((i + 1))
            sleep 10
        else
            return 0
        fi
    done
}

wget_clean() {
    [ -n "$1" ]          || return 1
    [ -n "$2" ]          || return 1
    [ -n "$3" ]          || return 1

    local temp_path="$1"
    local source_url="$2"
    local target_path="$3"

    rm -f "${temp_path}"
    if ! wget -O "${temp_path}" --tries=9 --retry-connrefused --waitretry=5 "${source_url}"; then
        rm -f "${temp_path}"
        return 1
    else
        if ! mv -f "${temp_path}" "${target_path}"; then
            rm -f "${temp_path}" "${target_path}"
            return 1
        fi
    fi

    return 0
}

download()
( # BEGIN sub-shell
    [ -n "$1" ]            || return 1
    [ -n "$2" ]            || return 1
    [ -n "$3" ]            || return 1
    [ -n "${CACHED_DIR}" ] || return 1

    local source_url="$1"
    local source="$2"
    local target_dir="$3"
    local cached_path="${CACHED_DIR}/${source}"
    local target_path="${target_dir}/${source}"
    local temp_path=""

    if [ ! -f "${cached_path}" ]; then
        mkdir -p "${CACHED_DIR}"
        if [ ! -f "${target_path}" ]; then
            cleanup() { rm -f "${cached_path}" "${temp_path}"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            temp_path=$(mktemp "${cached_path}.XXXXXX")
            if ! retry 100 wget_clean "${temp_path}" "${source_url}" "${cached_path}"; then
                return 1
            fi
            trap - EXIT INT TERM
        else
            cleanup() { rm -f "${cached_path}"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            if ! mv -f "${target_path}" "${cached_path}"; then
                return 1
            fi
            trap - EXIT INT TERM
        fi
    fi

    if [ ! -f "${target_path}" ]; then
        if [ -f "${cached_path}" ]; then
            ln -sfn "${cached_path}" "${target_path}"
        fi
    fi

    return 0
) # END sub-shell

clone_github()
( # BEGIN sub-shell
    [ -n "$1" ]            || return 1
    [ -n "$2" ]            || return 1
    [ -n "$3" ]            || return 1
    [ -n "$4" ]            || return 1
    [ -n "$5" ]            || return 1
    [ -n "${CACHED_DIR}" ] || return 1

    local source_url="$1"
    local source_version="$2"
    local source_subdir="$3"
    local source="$4"
    local target_dir="$5"
    local cached_path="${CACHED_DIR}/${source}"
    local target_path="${target_dir}/${source}"
    local temp_path=""
    local temp_dir=""
    local timestamp=""

    if [ ! -f "${cached_path}" ]; then
        umask 022
        mkdir -p "${CACHED_DIR}"
        if [ ! -f "${target_path}" ]; then
            cleanup() { rm -rf "${temp_path}" "${temp_dir}"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            temp_path=$(mktemp "${cached_path}.XXXXXX")
            temp_dir=$(mktemp -d "${target_dir}/temp.XXXXXX")
            mkdir -p "${temp_dir}"
            if ! retry 100 git clone "${source_url}" "${temp_dir}/${source_subdir}"; then
                return 1
            fi
            cd "${temp_dir}/${source_subdir}"
            if ! retry 100 git checkout ${source_version}; then
                return 1
            fi
            if ! retry 100 git submodule update --init --recursive; then
                return 1
            fi
            timestamp="$(git log -1 --format='@%ct')"
            rm -rf .git
            cd ../..
            #chmod -R g-w,o-w "${temp_dir}/${source_subdir}"
            if ! tar --numeric-owner --owner=0 --group=0 --sort=name --mtime="${timestamp}" \
                    -C "${temp_dir}" "${source_subdir}" \
                    -cv | xz -zc -7e -T0 >"${temp_path}"; then
                return 1
            fi
            touch -d "${timestamp}" "${temp_path}" || return 1
            mv -f "${temp_path}" "${cached_path}" || return 1
            rm -rf "${temp_dir}" || return 1
            trap - EXIT INT TERM
            sign_file "${cached_path}"
        else
            cleanup() { rm -f "${cached_path}"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            mv -f "${target_path}" "${cached_path}" || return 1
            trap - EXIT INT TERM
        fi
    fi

    if [ ! -f "${target_path}" ]; then
        if [ -f "${cached_path}" ]; then
            ln -sfn "${cached_path}" "${target_path}"
        fi
    fi

    return 0
) # END sub-shell

download_archive() {
    [ "$#" -eq 3 ] || [ "$#" -eq 5 ] || return 1

    local source_url="$1"
    local source="$2"
    local target_dir="$3"
    local source_version="$4"
    local source_subdir="$5"

    if [ -z "${source_version}" ]; then
        download "${source_url}" "${source}" "${target_dir}"
    else
        clone_github "${source_url}" "${source_version}" "${source_subdir}" "${source}" "${target_dir}"
    fi
}

apply_patch() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local patch_path="$1"
    local target_dir="$2"

    if [ -f "${patch_path}" ]; then
        echo "Applying patch: ${patch_path}"
        if patch --dry-run --silent -p1 -d "${target_dir}/" -i "${patch_path}"; then
            if ! patch -p1 -d "${target_dir}/" -i "${patch_path}"; then
                echo "The patch failed."
                return 1
            fi
        else
            echo "The patch was not applied. Failed dry run."
            return 1
        fi
    else
        echo "Patch not found: ${patch_path}"
        return 1
    fi

    return 0
}

apply_patch_folder() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local patch_dir="$1"
    local target_dir="$2"
    local patch_file=""
    local rc=0

    if [ -d "${patch_dir}" ]; then
        for patch_file in ${patch_dir}/*.patch; do
            if [ -f "${patch_file}" ]; then
                if ! apply_patch "${patch_file}" "${target_dir}"; then
                    rc=1
                fi
            fi
        done
    fi

    return ${rc}
}

rm_safe() {
    [ -n "$1" ] || return 1
    local target_dir="$1"

    # Prevent absolute paths
    case "${target_dir}" in
        /*)
            echo "Refusing to remove absolute path: ${target_dir}"
            return 1
            ;;
    esac

    # Prevent current/parent directories
    case "${target_dir}" in
        "."|".."|*/..|*/.)
            echo "Refusing to remove . or .. or paths containing ..: ${target_dir}"
            return 1
            ;;
    esac

    # Finally, remove safely
    rm -rf -- "${target_dir}"

    return 0
}

apply_patches() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local patch_dir="$1"
    local target_dir="$2"

    if ! apply_patch_folder "${patch_dir}" "${target_dir}"; then
        #rm_safe "${target_dir}"
        return 1
    fi

    return 0
}

extract_package() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local source_path="$1"
    local target_dir="$2"

    case "${source_path}" in
        *.tar.gz|*.tgz)
            tar xzvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *.tar.bz2|*.tbz)
            tar xjvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *.tar.xz|*.txz)
            tar xJvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *.tar.lz|*.tlz)
            tar xlvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *.tar.zst)
            tar xvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *.tar)
            tar xvf "${source_path}" -C "${target_dir}" || return 1
            ;;
        *)
            echo "Unsupported archive type: ${source_path}" >&2
            return 1
            ;;
    esac

    return 0
}

unpack_archive()
( # BEGIN sub-shell
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local source_path="$1"
    local target_dir="$2"
    local dir_tmp=""

    if [ ! -d "${target_dir}" ]; then
        cleanup() { rm -rf "${dir_tmp}" "${target_dir}"; }
        trap 'cleanup; exit 130' INT
        trap 'cleanup; exit 143' TERM
        trap 'cleanup' EXIT
        dir_tmp=$(mktemp -d "${target_dir}.XXXXXX")
        mkdir -p "${dir_tmp}"
        if ! extract_package "${source_path}" "${dir_tmp}"; then
            return 1
        else
            # try to rename single sub-directory
            if ! mv -f "${dir_tmp}"/* "${target_dir}"/; then
                # otherwise, move multiple files and sub-directories
                mkdir -p "${target_dir}" || return 1
                mv -f "${dir_tmp}"/* "${target_dir}"/ || return 1
            fi
        fi
        rm -rf "${dir_tmp}" || return 1
        trap - EXIT INT TERM
    fi

    return 0
) # END sub-shell

get_latest_package() {
    [ "$#" -eq 3 ] || return 1

    local prefix=$1
    local middle=$2
    local suffix=$3
    local pattern=${prefix}${middle}${suffix}
    local latest=""
    local version=""

    (
        cd "$CACHED_DIR" || return 1

        set -- $pattern
        [ "$1" != "$pattern" ] || return 1   # no matches

        latest=$1
        for f do
            latest=$f
        done

        version=${latest#"$prefix"}
        version=${version%"$suffix"}
        printf '%s\n' "$version"
    )
    return 0
}

is_version_git() {
    case "$1" in
        *+git*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

update_patch_library() {
    [ -n "$1" ]            || return 1
    [ -n "$2" ]            || return 1
    [ -n "$3" ]            || return 1
    [ -n "$4" ]            || return 1
    [ -n "${PARENT_DIR}" ] || return 1
    [ -n "${SCRIPT_DIR}" ] || return 1

    local git_commit="$1"
    local patches_dir="$2"
    local pkg_name="$3"
    local pkg_subdir="$4"
    local entware_packages_dir="${PARENT_DIR}/entware-packages"

    if [ ! -d "${entware_packages_dir}" ]; then
        cd "${PARENT_DIR}"
        git clone https://github.com/Entware/entware-packages
    fi

    cd "${entware_packages_dir}"
    git fetch origin
    git reset --hard "${git_commit}"
    [ -d "${patches_dir}" ] || return 1
    mkdir -p "${SCRIPT_DIR}/patches/${pkg_name}/${pkg_subdir}/entware"
    cp -pf "${patches_dir}"/* "${SCRIPT_DIR}/patches/${pkg_name}/${pkg_subdir}/entware/"
    cd ..

    return 0
}

check_static() {
    local rc=0
    for bin in "$@"; do
        echo "Checking ${bin}"
        file "${bin}" || true
        if ${CROSS_PREFIX}readelf -d "${bin}" 2>/dev/null | grep NEEDED; then
            rc=1
        fi || true
        "${LDD}" "${bin}" 2>&1 || true
    done

    if [ ${rc} -eq 1 ]; then
        echo "*** NOT STATICALLY LINKED ***"
        echo "*** NOT STATICALLY LINKED ***"
        echo "*** NOT STATICALLY LINKED ***"
    fi

    return ${rc}
}

finalize_build() {
    set +x
    echo ""
    echo "Stripping symbols and sections from files..."
    ${CROSS_PREFIX}strip -v "$@"

    # Exit here, if the programs are not statically linked.
    # If any binaries are not static, check_static() returns 1
    # set -e will cause the shell to exit here, so renaming won't happen below.
    echo ""
    echo "Checking statically linked programs..."
    check_static "$@"

    # Append ".static" to the program names
    echo ""
    echo "Create symbolic link with .static suffix..."
    for bin in "$@"; do
        case "$bin" in
            *.static) : ;;   # do nothing
            *) ln -sfn "$(basename "${bin}")" "${bin}.static" ;;
        esac
    done
    set -x

    return 0
}


################################################################################
# Install the build environment
# ARM Linux musl Cross-Compiler v0.1.0
#
CROSSBUILD_SUBDIR="cross-arm-linux-musleabi-build"
CROSSBUILD_DIR="${PARENT_DIR}/${CROSSBUILD_SUBDIR}"
export TARGET=arm-linux-musleabi
(
PKG_NAME=cross-arm-linux-musleabi
HOST_CPU="$(uname -m)"
get_latest() { get_latest_package "${PKG_NAME}-${HOST_CPU}-" "??????????????" ".tar.xz"; }
#PKG_VERSION="$(get_latest)" # this line will fail if you did not build a toolchain yourself
PKG_VERSION=0.1.0 # this line will cause a toolchain to be downloaded from Github
PKG_SOURCE="${PKG_NAME}-${HOST_CPU}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/solartracker/${PKG_NAME}/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_SOURCE_PATH="${CACHED_DIR}/${PKG_SOURCE}"

if [ $(expr length "$PKG_VERSION") -eq 14 ]; then
    # use an archived toolchain that you built yourself. the version number is a 14 digit timestamp.
    # Example: cross-arm-linux-musleabi-armv7l-20260115045834.tar.xz
    PKG_HASH=""
else
    # alternatively, the toolchain can be downloaded from Github. note that the version
    # number is the Github tag, instead of a 14 digit timestamp.
    case "${HOST_CPU}" in
        armv7l)
            # cross-arm-linux-musleabi-armv7l-0.1.0.tar.xz
            PKG_HASH="5c8f54f146082775cebd8d77624c4c4f3bb1b38c9a4dea01916453df029e9c48"
            ;;
        x86_64)
            # cross-arm-linux-musleabi-x86_64-0.1.0.tar.xz
            PKG_HASH="224113b04fd1d20ebf75f2016b2b623fb619db2bf3db0c5cba2ee8449847d9e4"
            ;;
        *)
            echo "Unsupported CPU architecture: "${HOST_CPU} >&2
            exit 1
            ;;
    esac
fi

# Check if toolchain exists and install it, if needed
if [ ! -d "${CROSSBUILD_DIR}" ]; then
    echo "Toolchain not found at ${CROSSBUILD_DIR}. Installing..."
    echo ""
    cd ${PARENT_DIR}
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "${CACHED_DIR}"
    verify_hash "${PKG_SOURCE_PATH}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE_PATH}" "${CROSSBUILD_DIR}"
fi

# Check for required toolchain tools
if [ ! -x "${CROSSBUILD_DIR}/bin/${TARGET}-gcc" ]; then
    echo "ERROR: Toolchain installation appears incomplete."
    echo "Missing ${TARGET}-gcc in ${CROSSBUILD_DIR}/bin"
    echo ""
    exit 1
fi
if [ ! -x "${CROSSBUILD_DIR}/${TARGET}/lib/libc.so" ]; then
    echo "ERROR: Toolchain installation appears incomplete."
    echo "Missing libc.so in ${CROSSBUILD_DIR}/${TARGET}/lib"
    echo ""
    exit 1
fi
)


################################################################################
# General

PKG_ROOT=transmission

#BUILD_TRANSMISSION_VERSION="3.00"
#BUILD_TRANSMISSION_VERSION="3.00+git"
BUILD_TRANSMISSION_VERSION="4.0.6"
#BUILD_TRANSMISSION_VERSION="4.0.6+git"

export PREFIX="${CROSSBUILD_DIR}"
export HOST=${TARGET}
export SYSROOT="${PREFIX}/${TARGET}"
export PATH="${PATH}:${PREFIX}/bin:${SYSROOT}/bin"

CROSS_PREFIX=${TARGET}-
export CC=${CROSS_PREFIX}gcc
export AR=${CROSS_PREFIX}ar
export RANLIB=${CROSS_PREFIX}ranlib
export STRIP=${CROSS_PREFIX}strip

export LDFLAGS="-L${PREFIX}/lib -Wl,--gc-sections"
export CPPFLAGS="-I${PREFIX}/include -D_GNU_SOURCE"
export CFLAGS="-O3 -march=armv7-a -mtune=cortex-a9 -marm -mfloat-abi=soft -mabi=aapcs-linux -fomit-frame-pointer -ffunction-sections -fdata-sections -pipe -Wall -fPIC"
export CXXFLAGS="${CFLAGS}"

case "${HOST_CPU}" in
    armv7l)
        LDD="${SYSROOT}/lib/libc.so --list"
        ;;
    *)
        LDD="ldd"
        ;;
esac

SRC_ROOT="${CROSSBUILD_DIR}/src/${PKG_ROOT}"
mkdir -p "${SRC_ROOT}"

MAKE="make -j$(grep -c ^processor /proc/cpuinfo)" # parallelism
#MAKE="make -j1"                                  # one job at a time

export PKG_CONFIG="pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH

# CMAKE options
CMAKE_BUILD_TYPE="RelWithDebInfo"
CMAKE_VERBOSE_MAKEFILE="YES"
CMAKE_C_FLAGS="${CFLAGS}"
CMAKE_CXX_FLAGS="${CXXFLAGS}"
CMAKE_LD_FLAGS="${LDFLAGS}"
CMAKE_CPP_FLAGS="${CPPFLAGS}"

{
    printf '%s\n' "# toolchain.cmake"
    printf '%s\n' "set(CMAKE_SYSTEM_NAME Linux)"
    printf '%s\n' "set(CMAKE_SYSTEM_PROCESSOR arm)"
    printf '%s\n' ""
    printf '%s\n' "# Cross-compiler"
    printf '%s\n' "set(CMAKE_C_COMPILER arm-linux-musleabi-gcc)"
    printf '%s\n' "set(CMAKE_CXX_COMPILER arm-linux-musleabi-g++)"
    printf '%s\n' "set(CMAKE_AR arm-linux-musleabi-ar)"
    printf '%s\n' "set(CMAKE_RANLIB arm-linux-musleabi-ranlib)"
    printf '%s\n' "set(CMAKE_STRIP arm-linux-musleabi-strip)"
    printf '%s\n' ""
    printf '%s\n' "# Optional: sysroot"
    printf '%s\n' "set(CMAKE_SYSROOT \"${SYSROOT}\")"
    printf '%s\n' ""
    printf '%s\n' "# Avoid picking host libraries"
    printf '%s\n' "set(CMAKE_FIND_ROOT_PATH \"${PREFIX}\")"
    printf '%s\n' ""
    printf '%s\n' "# Tell CMake to search only in sysroot"
    printf '%s\n' "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)"
    printf '%s\n' "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)"
    printf '%s\n' "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)"
    printf '%s\n' ""
    printf '%s\n' "set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY) # critical for skipping warning probes"
    printf '%s\n' ""
    printf '%s\n' "set(CMAKE_C_STANDARD 11)"
    printf '%s\n' "set(CMAKE_CXX_STANDARD 17)"
    printf '%s\n' ""
} >"${PREFIX}/arm-musl.toolchain.cmake"


################################################################################
# libdeflate-1.25
(
PKG_NAME=libdeflate
PKG_VERSION=1.25
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/ebiggers/libdeflate/releases/download/v${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="fed5cd22f00f30cc4c2e5329f94e2b8a901df9fa45ee255cb70e2b0b42344477"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    rm -rf build
    mkdir -p build
    cd build

    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE=${PREFIX}/arm-musl.toolchain.cmake \
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
        -DCMAKE_VERBOSE_MAKEFILE=${CMAKE_VERBOSE_MAKEFILE} \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++"

    $MAKE
    make install

    cd ..

    touch __package_installed
fi
)

################################################################################
# libnatpmp-20230423
(
PKG_NAME=libnatpmp
PKG_VERSION=20230423
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://miniupnp.tuxfamily.org/files/download.php?file=${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="0684ed2c8406437e7519a1bd20ea83780db871b3a3a5d752311ba3e889dbfc70"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker" "."

    $MAKE CC=${CC} CFLAGS="${CFLAGS} -DENABLE_STRNATPMPERR"
    make install INSTALLPREFIX=${PREFIX}

#    rm -rf build
#    mkdir -p build
#    cd build
#
#    cmake .. \
#        -DCMAKE_TOOLCHAIN_FILE=${PREFIX}/arm-musl.toolchain.cmake \
#        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
#        -DCMAKE_VERBOSE_MAKEFILE=${CMAKE_VERBOSE_MAKEFILE} \
#        -DCMAKE_PREFIX_PATH="${PREFIX}" \
#        -DCMAKE_INSTALL_PREFIX="${PREFIX}"
#
#    $MAKE
#    make install
#
#    cd ..

    touch __package_installed
fi
)

################################################################################
# miniupnpc-2.2.8
(
PKG_NAME=miniupnpc
PKG_VERSION=2.2.8
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://miniupnp.tuxfamily.org/files/download.php?file=${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="05b929679091b9921b6b6c1f25e39e4c8d1f4d46c8feb55a412aa697aee03a93"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "."

    $MAKE CC=${CC} CFLAGS="${CFLAGS}"
    make install INSTALLPREFIX=${PREFIX}

    touch __package_installed
fi
)

################################################################################
# zlib-1.3.1
(
PKG_NAME=zlib
PKG_VERSION=1.3.1
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/madler/zlib/releases/download/v${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    ./configure \
        --static \
        --prefix="${PREFIX}" \
    || handle_configure_error $?

    $MAKE
    make install

    touch __package_installed
fi
)

################################################################################
# lz4-1.10.0
(
PKG_NAME=lz4
PKG_VERSION=1.10.0
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/lz4/lz4/releases/download/v${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    make clean || true
    $MAKE lib
    make install PREFIX=${PREFIX}

    touch __package_installed
fi
)

################################################################################
# xz-5.8.2
(
PKG_NAME=xz
PKG_VERSION=5.8.2
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/tukaani-project/xz/releases/download/v${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="890966ec3f5d5cc151077879e157c0593500a522f413ac50ba26d22a9a145214"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    ./configure \
        --enable-year2038 \
        --enable-static \
        --disable-shared \
        --disable-nls \
        --disable-rpath \
        --disable-scripts \
        --disable-doc \
        --prefix="${PREFIX}" \
        --host="${HOST}" \
    || handle_configure_error $?

    $MAKE
    make install

    touch __package_installed
fi
)

################################################################################
# zstd-1.5.7
(
PKG_NAME=zstd
PKG_VERSION=1.5.7
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/facebook/zstd/releases/download/v${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3"

#PKG_NAME=zstd
#PKG_VERSION="1.5.7+git"
#PKG_SOURCE_URL="https://github.com/facebook/zstd.git"
#PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
#PKG_SOURCE_VERSION="f8745da6ff1ad1e7bab384bd1f9d742439278e99"
#PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-${PKG_SOURCE_VERSION}.tar.xz"
#PKG_HASH_VERIFY="tar_extract"
#PKG_HASH="ae83002690aba91a210f3efc2dbf00aee5266f9b68f47b1130c95dd6a1a48e4b"

mkdir -p "${SRC_ROOT}/${PKG_NAME}" && cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "." "${PKG_SOURCE_VERSION}" "${PKG_SOURCE_SUBDIR}"
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    $MAKE zstd \
        LDFLAGS="-static ${LDFLAGS}" \
        CFLAGS="${CFLAGS}" \
        LIBS="${PREFIX}/lib/libz.a ${PREFIX}/lib/liblzma.a ${PREFIX}/lib/liblz4.a"

    make install DESTDIR="" PREFIX="${PREFIX}"

    rm -f "${PREFIX}/lib/libzstd.so"*

    # strip and verify there are no dependencies for static build
    finalize_build "${PREFIX}/bin/zstd"

    touch __package_installed
fi
)

################################################################################
# libpsl-0.21.5
(
PKG_NAME=libpsl
PKG_VERSION=0.21.5
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/rockdaboot/libpsl/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="1dcc9ceae8b128f3c0b3f654decd0e1e891afc6ff81098f227ef260449dae208"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    ./configure \
        --enable-static \
        --disable-shared \
        --disable-nls \
        --disable-rpath \
        --disable-dependency-tracking \
        --without-libiconv-prefix \
        --without-libintl-prefix \
        --prefix="${PREFIX}" \
        --host="${HOST}" \
    || handle_configure_error $?

    $MAKE
    make install

    touch __package_installed
fi
)

################################################################################
# libutp-20230214+git
(
PKG_NAME=libutp
PKG_SOURCE_DATE="20230214"
PKG_VERSION="${PKG_SOURCE_DATE}+git"
PKG_SOURCE_VERSION="c95738b1a6644b919e5b64d3ea9736cfc5894e0b"
PKG_SOURCE_URL="https://github.com/transmission/libutp/archive/${PKG_SOURCE_VERSION}.tar.gz"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-${PKG_SOURCE_VERSION}.tar.gz"
PKG_HASH="d856fde68828d52eb39df40e15ad5dc4efaa9a51d4121bcbfbe47fed2163d20a"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    rm -rf build
    mkdir -p build
    cd build

    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE=${PREFIX}/arm-musl.toolchain.cmake \
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
        -DCMAKE_VERBOSE_MAKEFILE=${CMAKE_VERBOSE_MAKEFILE} \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DLIBUTP_SHARED=NO \
        -DLIBUTP_ENABLE_INSTALL=YES \
        -DLIBUTP_ENABLE_WERROR=OFF \
        -DLIBUTP_BUILD_PROGRAMS=NO \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON

    $MAKE
    make install

    cd ..

    touch __package_installed
fi
)

################################################################################
# libb64-20200908+git
(
PKG_NAME=libb64
PKG_SOURCE_DATE="20200908"
PKG_VERSION="${PKG_SOURCE_DATE}+git"
PKG_SOURCE_VERSION="b5edeafc89853c48fa41a4c16393a1fdc8638ab6"
PKG_SOURCE_URL="https://github.com/libb64/libb64/archive/${PKG_SOURCE_VERSION}.tar.gz"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-${PKG_SOURCE_VERSION}.tar.gz"
PKG_HASH="dcdd5923d61e7f9d0deab773490a3613afd94abc2ca15ccebdf59a848650182c"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "."

    mkdir -p ${PREFIX}/include/b64
    cp -p include/b64/*.h ${PREFIX}/include/b64/

    $MAKE all_src CC=${CC} CFLAGS="${CFLAGS}"

    mkdir -p ${PREFIX}/lib/
    cp -p src/*.a ${PREFIX}/lib/

    touch __package_installed
fi
)

################################################################################
# openssl-3.6.0
(
PKG_NAME=openssl
PKG_VERSION=3.6.0
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://github.com/openssl/openssl/releases/download/openssl-${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="b6a5f44b7eb69e3fa35dbf15524405b44837a481d43d81daddde3ff21fcbb8e9"

mkdir -p "${SRC_ROOT}/${PKG_NAME}" && cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    export LDFLAGS="-static ${LDFLAGS}"
    export LIBS="-lzstd -lz"

    ./Configure linux-armv4 \
        enable-zlib enable-zstd no-zlib-dynamic \
        no-shared no-tests no-fuzz-afl no-fuzz-libfuzzer no-gost no-err no-unit-test no-docs \
        no-err no-async \
        no-aria no-sm2 no-sm3 no-sm4 \
        no-dso no-ssl3 no-comp \
        enable-rc5 \
        --prefix="${PREFIX}" \
        --with-rand-seed=devrandom \
        -DOPENSSL_PREFER_CHACHA_OVER_GCM

    $MAKE
    make install DESTDIR="" PREFIX="${PREFIX}"

    # strip and verify there are no dependencies for static build
    finalize_build "${PREFIX}/bin/openssl"

    touch __package_installed
fi
)

################################################################################
# curl-8.17.0
(
PKG_NAME=curl
PKG_VERSION=8.17.0
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/curl/curl/releases/download/curl-$(echo "${PKG_VERSION}" | tr '.' '_')/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="955f6e729ad6b3566260e8fef68620e76ba3c31acf0a18524416a185acf77992"

mkdir -p "${SRC_ROOT}/${PKG_NAME}" && cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    export LIBS="-lssl -lcrypto -lzstd -lz"

    LDFLAGS="-static ${LDFLAGS}" \
    ./configure \
        --enable-static \
        --disable-shared \
        --prefix="${PREFIX}" \
        --host="${HOST}" \
        --disable-debug \
        --disable-curldebug \
        --enable-http \
        --disable-gopher \
        --disable-dict \
        --disable-telnet \
        --disable-manual \
        --disable-libcurl-option \
        --disable-threaded-resolver \
        --with-ca-bundle="/etc/ssl/certs/ca-certificates.crt" \
        --disable-dependency-tracking \
        --enable-optimize \
        --disable-silent-rules \
        --disable-rt \
        --disable-docs \
        --without-libpsl \
        --with-zlib="${PREFIX}" \
        --with-zstd="${PREFIX}" \
        --with-openssl="${PREFIX}" \
    || handle_configure_error $?

    $MAKE V=1 LDFLAGS="-static -all-static ${LDFLAGS}"
    make install DESTDIR="" PREFIX="${PREFIX}"

    # strip and verify there are no dependencies for static build
    finalize_build "${PREFIX}/bin/curl"

    touch __package_installed
fi
)

################################################################################
# libevent-2.1.12
(
PKG_NAME=libevent
PKG_VERSION=2.1.12
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-stable.tar.gz"
PKG_SOURCE_URL="https://github.com/libevent/libevent/releases/download/release-${PKG_VERSION}-stable/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"

mkdir -p "${SRC_ROOT}/${PKG_NAME}" && cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    export LIBS="-lssl -lcrypto"

    ./configure \
        --enable-static \
        --disable-shared \
        --prefix="${PREFIX}" \
        --host="${HOST}" \
        --disable-debug-mode \
        --disable-libevent-regress \
        --disable-samples \
        --enable-function-sections \
        --disable-dependency-tracking \
        --disable-doxygen-doc \
    || handle_configure_error $?

    $MAKE
    find . -name '*.la' -delete
    make install DESTDIR="" PREFIX="${PREFIX}"

    touch __package_installed
fi
)


if [ "$BUILD_TRANSMISSION_VERSION" = "3.00" ]; then
################################################################################
# transmission-3.00
(
PKG_NAME=transmission
PKG_VERSION=3.00
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/transmission/transmission/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="9144652fe742f7f7dd6657716e378da60b751aaeda8bef8344b3eefc4db255f2"

mkdir -p "${SRC_ROOT}/${PKG_NAME}" && cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "."

    export LIBS="-lcurl -lssl -lcrypto -levent -lzstd -lz -lm -lpthread -lrt"

    LDFLAGS="-static ${LDFLAGS}" \
    ./configure \
        --enable-static \
        --disable-shared \
        --disable-nls \
        --disable-silent-rules \
        --disable-dependency-tracking \
        --enable-daemon \
        --enable-cli \
        --without-gtk \
        --enable-largefile \
        --enable-lightweight \
        --with-crypto=openssl \
        --prefix="${PREFIX}" \
        --host="${HOST}" \
    || handle_configure_error $?

    $MAKE V=1 LDFLAGS="-static -all-static ${LDFLAGS}"
    make install DESTDIR="" PREFIX="${PREFIX}"

    # strip and verify there are no dependencies for static build
    finalize_build \
        "${PREFIX}/bin/transmission-cli" \
        "${PREFIX}/bin/transmission-create" \
        "${PREFIX}/bin/transmission-daemon" \
        "${PREFIX}/bin/transmission-edit" \
        "${PREFIX}/bin/transmission-remote" \
        "${PREFIX}/bin/transmission-show"

    touch __package_installed
fi
)
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "3.00" ]



if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6" ]; then
################################################################################
# transmission-4.0.6
(
PKG_NAME=transmission
PKG_VERSION=4.0.6
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/transmission/transmission/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="2a38fe6d8a23991680b691c277a335f8875bdeca2b97c6b26b598bc9c7b0c45f"

mkdir -p "${SRC_ROOT}/${PKG_NAME}"
cd "${SRC_ROOT}/${PKG_NAME}"

if [ ! -f "${PKG_SOURCE_SUBDIR}/__package_installed" ]; then
    rm -rf "${PKG_SOURCE_SUBDIR}"
    download_archive "${PKG_SOURCE_URL}" "${PKG_SOURCE}" "."
    verify_hash "${PKG_SOURCE}" "${PKG_HASH}"
    unpack_archive "${PKG_SOURCE}" "${PKG_SOURCE_SUBDIR}"
    cd "${PKG_SOURCE_SUBDIR}"

    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "."

    mkdir -p "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker"
    diff -u "./cli/CMakeLists.txt" "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/cli/CMakeLists.txt" >"${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/100-static-cli.patch" || true
    diff -u "./daemon/CMakeLists.txt" "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/daemon/CMakeLists.txt" >"${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/101-static-daemon.patch" || true
    diff -u "./utils/CMakeLists.txt" "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/utils/CMakeLists.txt" >"${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/102-static-utils.patch" || true

    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/daemon/CMakeLists.txt" "./daemon/"
    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/cli/CMakeLists.txt" "./cli/"
    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/utils/CMakeLists.txt" "./utils/"

    rm -rf build
    mkdir -p build
    cd build

    cmake .. \
        -DCMAKE_TOOLCHAIN_FILE=${PREFIX}/arm-musl.toolchain.cmake \
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} \
        -DCMAKE_VERBOSE_MAKEFILE=${CMAKE_VERBOSE_MAKEFILE} \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DHAVE_LIBQUOTA:BOOL=NO \
        -DHAVE_SENDFILE64:BOOL=NO \
        -DHAVE_HTONLL:BOOL=NO \
        -DHAVE_NTOHLL:BOOL=NO \
        -DENABLE_CLI:BOOL=YES \
        -DENABLE_GTK:BOOL=NO \
        -DENABLE_QT:BOOL=NO \
        -DENABLE_MAC:BOOL=NO \
        -DENABLE_TESTS:BOOL=NO \
        -DENABLE_NLS:BOOL=NO \
        -DENABLE_UTP:BOOL=YES \
        -DRUN_CLANG_TIDY:BOOL=NO \
        -DWITH_INOTIFY:BOOL=YES \
        -DWITH_KQUEUE:BOOL=NO \
        -DWITH_SYSTEMD:BOOL=NO

#    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/daemon/CMakeLists.txt" "../daemon/"
#    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/cli/CMakeLists.txt" "../cli/"
#    cp -p "${SCRIPT_DIR}/files/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/solartracker/utils/CMakeLists.txt" "../utils/"

    $MAKE
    make install

    cd ..

    touch __package_installed
fi
)
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6" ]




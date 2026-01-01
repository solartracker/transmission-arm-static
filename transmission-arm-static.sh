#!/bin/sh
################################################################################
# transmission-arm-static.sh
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
CACHED_DIR="${PARENT_DIR}/tomatoware-sources"
set -e
set -x

################################################################################
# Helpers

# If autoconf/configure fails due to missing libraries or undefined symbols, you
# immediately see all undefined references without having to manually search config.log
handle_configure_error() {
    #grep -R --include="config.log" --color=always "undefined reference" .
    find . -name "config.log" -exec grep -H "undefined reference" {} \;
    return 1
}

################################################################################
# Package management

# new files:       rw-r--r-- (644)
# new directories: rwxr-xr-x (755)
umask 022

# Checksum verification for downloaded file
verify_hash() {
    [ -n "$1" ] || return 1

    local file="$1"
    local expected="$2"
    local option="$3"
    local actual=""

    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file"
        return 1
    fi

    if [ -z "$option" ]; then
        # hash the compressed binary file. this method is best when downloading
        # compressed binary files.
        actual="$(sha256sum "$file" | awk '{print $1}')"
    elif [ "$option" == "tar_extract" ]; then
        # hash the data, file names, directory names. this method is best when
        # archiving Github repos. with Github repos, you are producing
        # the compressed binary archive. someone else may end up with a "different"
        # compressed binary archive that contains the same repo data.
        actual="$(tar -xJOf "$file" | sha256sum | awk '{print $1}')"
    elif [ "$option" == "xz_extract" ]; then
        # hash the data, file names, directory names, timestamps, permissions, and
        # tar internal structures. this method is not as "future-proof" for archiving
        # Github repos because it is possible that the tar internal structures
        # could change over time as the tar implementations evolve.
        actual="$(xz -dc "$file" | sha256sum | awk '{print $1}')"
    else
        return 1
    fi

    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA256 mismatch for $file"
        echo "Expected: $expected"
        echo "Actual:   $actual"
        return 1
    fi

    echo "SHA256 OK: $file"
    return 0
}

retry() {
    local max=$1
    shift
    local i=1
    while :; do
        if ! "$@"; then
            if [ "$i" -ge "$max" ]; then
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

    rm -f "$temp_path"
    if ! wget -O "$temp_path" --tries=9 --retry-connrefused --waitretry=5 "$source_url"; then
        rm -f "$temp_path"
        return 1
    else
        if ! mv -f "$temp_path" "$target_path"; then
            rm -f "$temp_path" "$target_path"
            return 1
        fi
    fi

    return 0
}

download() ( # BEGIN sub-shell
    [ -n "$1" ]          || return 1
    [ -n "$2" ]          || return 1
    [ -n "$3" ]          || return 1
    [ -n "$CACHED_DIR" ] || return 1

    local source_url="$1"
    local source="$2"
    local target_dir="$3"
    local cached_path="$CACHED_DIR/$source"
    local target_path="$target_dir/$source"
    local temp_path=""

    if [ ! -f "$cached_path" ]; then
        mkdir -p "$CACHED_DIR"
        if [ ! -f "$target_path" ]; then
            cleanup() { rm -f "$cached_path" "$temp_path"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            temp_path=$(mktemp "$cached_path.XXXXXX")
            if ! retry 100 wget_clean "$temp_path" "$source_url" "$cached_path"; then
                return 1
            fi
            trap - EXIT INT TERM
        else
            cleanup() { rm -f "$cached_path"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            if ! mv -f "$target_path" "$cached_path"; then
                return 1
            fi
            trap - EXIT INT TERM
        fi
    fi

    if [ ! -f "$target_path" ]; then
        if [ -f "$cached_path" ]; then
            ln -sfn "$cached_path" "$target_path"
        fi
    fi

    return 0
) # END sub-shell

clone_to_archive() ( # BEGIN sub-shell
    [ -n "$1" ]          || return 1
    [ -n "$2" ]          || return 1
    [ -n "$3" ]          || return 1
    [ -n "$4" ]          || return 1
    [ -n "$5" ]          || return 1
    [ -n "$CACHED_DIR" ] || return 1

    local source_url="$1"
    local source_version="$2"
    local source_subdir="$3"
    local source="$4"
    local target_dir="$5"
    local cached_path="$CACHED_DIR/$source"
    local target_path="$target_dir/$source"
    local temp_dir=""
    local timestamp=""

    if [ ! -f "$cached_path" ]; then
        umask 022
        mkdir -p "$CACHED_DIR"
        if [ ! -f "$target_path" ]; then
            cleanup() { rm -rf "$cached_path" "$temp_dir"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            temp_dir=$(mktemp -d "$target_dir/temp.XXXXXX")
            mkdir -p "$temp_dir"
            if ! retry 100 git clone "$source_url" "$temp_dir/$source_subdir"; then
                return 1
            fi
            cd "$temp_dir/$source_subdir"
            if ! retry 100 git checkout $source_version; then
                return 1
            fi
            if ! retry 100 git submodule update --init --recursive; then
                return 1
            fi
            timestamp="$(git log -1 --format='@%ct')"
            rm -rf .git
            cd ../..
            #chmod -R g-w,o-w "$temp_dir/$source_subdir"
            tar --numeric-owner --owner=0 --group=0 --sort=name --mtime="$timestamp" -cv -C "$temp_dir" "$source_subdir" | xz -zc -7e >"$cached_path"
            touch -d "$timestamp" "$cached_path"
            rm -rf "$temp_dir"
            trap - EXIT INT TERM
        else
            cleanup() { rm -f "$cached_path"; }
            trap 'cleanup; exit 130' INT
            trap 'cleanup; exit 143' TERM
            trap 'cleanup' EXIT
            if ! mv -f "$target_path" "$cached_path"; then
                return 1
            fi
            trap - EXIT INT TERM
        fi
    fi

    if [ ! -f "$target_path" ]; then
        if [ -f "$cached_path" ]; then
            ln -sfn "$cached_path" "$target_path"
        fi
    fi

    return 0
) # END sub-shell

apply_patch() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local patch_path="$1"
    local target_dir="$2"

    if [ -f "$patch_path" ]; then
        echo "Applying patch: $patch_path"
        if patch --dry-run --silent -p1 -d "$target_dir/" -i "$patch_path"; then
            if ! patch -p1 -d "$target_dir/" -i "$patch_path"; then
                echo "The patch failed."
                return 1
            fi
        else
            echo "The patch was not applied. Failed dry run."
            return 1
        fi
    else
        echo "Patch not found: $patch_path"
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

    if [ -d "$patch_dir" ]; then
        for patch_file in $patch_dir/*.patch; do
            if [ -f "$patch_file" ]; then
                if ! apply_patch "$patch_file" "$target_dir"; then
                    rc=1
                fi
            fi
        done
    fi

    return $rc
}

rm_safe() {
    [ -n "$1" ] || return 1
    local target_dir="$1"

    # Prevent absolute paths
    case "$target_dir" in
        /*)
            echo "Refusing to remove absolute path: $target_dir"
            return 1
            ;;
    esac

    # Prevent current/parent directories
    case "$target_dir" in
        "."|".."|*/..|*/.)
            echo "Refusing to remove . or .. or paths containing ..: $target_dir"
            return 1
            ;;
    esac

    # Finally, remove safely
    rm -rf -- "$target_dir"

    return 0
}

apply_patches() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local patch_dir="$1"
    local target_dir="$2"

    if ! apply_patch_folder "$patch_dir" "$target_dir"; then
        #rm_safe "$target_dir"
        return 1
    fi

    return 0
}

extract_package() {
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local source_path="$1"
    local target_dir="$2"

    case "$source_path" in
        *.tar.gz|*.tgz)
            tar xzvf "$source_path" -C "$target_dir"
            ;;
        *.tar.bz2|*.tbz)
            tar xjvf "$source_path" -C "$target_dir"
            ;;
        *.tar.xz|*.txz)
            tar xJvf "$source_path" -C "$target_dir"
            ;;
        *.tar.lz|*.tlz)
            tar xlvf "$source_path" -C "$target_dir"
            ;;
        *.tar)
            tar xvf "$source_path" -C "$target_dir"
            ;;
        *)
            echo "Unsupported archive type: $source_path" >&2
            return 1
            ;;
    esac

    return 0
}

unpack_archive() ( # BEGIN sub-shell
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1

    local source_path="$1"
    local target_dir="$2"
    local dir_tmp=""

    if [ ! -d "$target_dir" ]; then
        dir_tmp=$(mktemp -d "$target_dir.XXXXXX")
        cleanup() { rm -rf "$dir_tmp"; }
        trap 'cleanup; exit 130' INT
        trap 'cleanup; exit 143' TERM
        trap 'cleanup' EXIT
        mkdir -p "$dir_tmp"
        if extract_package "$source_path" "$dir_tmp"; then
            # try to rename single sub-directory
            if ! mv -f "$dir_tmp"/* "$target_dir"/; then
                # otherwise, move multiple files and sub-directories
                mkdir -p "$target_dir"
                mv -f "$dir_tmp"/* "$target_dir"/
            fi
        fi
    fi

    return 0
) # END sub-shell

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
    [ -n "$1" ] || return 1
    [ -n "$2" ] || return 1
    [ -n "$3" ] || return 1
    [ -n "$4" ] || return 1
    [ -n "$PARENT_DIR" ] || return 1
    [ -n "$SCRIPT_DIR" ] || return 1

    local git_commit="$1"
    local patches_dir="$2"
    local pkg_name="$3"
    local pkg_subdir="$4"
    local entware_packages_dir="$PARENT_DIR/entware-packages"

    if [ ! -d "$entware_packages_dir" ]; then
        cd "$PARENT_DIR"
        git clone https://github.com/Entware/entware-packages
    fi

    cd "$entware_packages_dir"
    git fetch origin
    git reset --hard "$git_commit"
    [ -d "$patches_dir" ] || return 1
    mkdir -p "${SCRIPT_DIR}/patches/${pkg_name}/${pkg_subdir}/entware"
    cp -pf "${patches_dir}"/* "${SCRIPT_DIR}/patches/${pkg_name}/${pkg_subdir}/entware/"
    cd ..

    return 0
}


################################################################################
# Install the build environment

TOMATOWARE_PKG_SOURCE_URL="https://github.com/lancethepants/tomatoware/releases/download/v5.0/arm-soft-mmc.tgz"
TOMATOWARE_PKG_HASH="ff490819a16f5ddb80ec095342ac005a444b6ebcd3ed982b8879134b2b036fcc"
TOMATOWARE_PKG="arm-soft-mmc-5.0.tgz"
TOMATOWARE_DIR="tomatoware-5.0"
TOMATOWARE_PATH="${PARENT_DIR}/${TOMATOWARE_DIR}"
TOMATOWARE_SYSROOT="/mmc" # or, whatever your tomatoware distribution uses for sysroot

# Check if Tomatoware exists and install it, if needed
if [ ! -d "$TOMATOWARE_PATH" ]; then
    echo "Tomatoware not found at $TOMATOWARE_PATH. Installing..."
    echo ""
    cd $PARENT_DIR
    TOMATOWARE_PKG_PATH="$CACHED_DIR/$TOMATOWARE_PKG"
    download "$TOMATOWARE_PKG_SOURCE_URL" "$TOMATOWARE_PKG" "$CACHED_DIR"
    verify_hash "$TOMATOWARE_PKG_PATH" "$TOMATOWARE_PKG_HASH"
    unpack_archive "$TOMATOWARE_PKG_PATH" "$TOMATOWARE_DIR"
fi

# Check if /mmc exists and is a symbolic link
if [ ! -L "$TOMATOWARE_SYSROOT" ] && ! grep -q " $TOMATOWARE_SYSROOT " /proc/mounts; then
    echo "Tomatoware $TOMATOWARE_SYSROOT is missing or is not a symbolic link."
    echo ""
    # try making a symlink
    if ! sudo ln -sfn "$TOMATOWARE_PATH" "$TOMATOWARE_SYSROOT"; then
        # otherwise, we are probably on a read-only filesystem and
        # the sysroot needs to be already baked into the firmware and
        # not in use by something else.
        # alternatively, you can figure out another sysroot to use.
        mount -o bind "$TOMATOWARE_PATH" "$TOMATOWARE_SYSROOT"
    fi
fi

# Check for required Tomatoware tools
if [ ! -x "$TOMATOWARE_SYSROOT/bin/gcc" ] || [ ! -x "$TOMATOWARE_SYSROOT/bin/make" ]; then
    echo "ERROR: Tomatoware installation appears incomplete."
    echo "Missing gcc or make in $TOMATOWARE_SYSROOT/bin."
    echo ""
    exit 1
fi

# Check shell
if [ "$BASH" != "$TOMATOWARE_SYSROOT/bin/bash" ]; then
    if [ -z "$TOMATOWARE_SHELL" ]; then
        export TOMATOWARE_SHELL=1
        exec "$TOMATOWARE_SYSROOT/bin/bash" "$PATH_CMD" "$@"
    else
        echo "ERROR: Not Tomatoware shell: $(readlink /proc/$$/exe)"
        echo ""
        exit 1
    fi
fi

# ---- From here down, you are running under /mmc/bin/bash ----
echo "Now running under: $(readlink /proc/$$/exe)"

################################################################################
# General

PKG_ROOT=transmission
REBUILD_ALL=false
BUILD_TRANSMISSION_VERSION="3.00"
SRC="$TOMATOWARE_SYSROOT/src/$PKG_ROOT"
mkdir -p "$SRC"
MAKE="make -j$(grep -c ^processor /proc/cpuinfo)" # parallelism
#MAKE="make -j1"                                  # one job at a time
export PATH="$TOMATOWARE_SYSROOT/usr/bin:$TOMATOWARE_SYSROOT/usr/local/sbin:$TOMATOWARE_SYSROOT/usr/local/bin:$TOMATOWARE_SYSROOT/usr/sbin:$TOMATOWARE_SYSROOT/sbin:$TOMATOWARE_SYSROOT/bin"
export PKG_CONFIG_PATH="$TOMATOWARE_SYSROOT/lib/pkgconfig"
#export PKG_CONFIG="pkg-config --static"

# get patches (only needs to be run once by me, then keep it commented out)
#update_patch_library "3895f460ea7e7a99eeff7ed65447e70a34a8eda6" "net/transmission/patches" "transmission" "transmission-3.00"
#ln -sfn "transmission-3.00" "${SCRIPT_DIR}/patches/transmission/transmission-3.00+git" 
#update_patch_library "594346b9325c7f5d07c60c2e9727cfe83e768067" "net/transmission/patches" "transmission" "transmission-4.0.6"
#ln -sfn "transmission-4.0.6" "${SCRIPT_DIR}/patches/transmission/transmission-4.0.6+git" 



if [ "$BUILD_TRANSMISSION_VERSION" = "3.00" ]; then
################################################################################
# transmission-3.00

PKG_NAME=transmission
PKG_VERSION=3.00
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/transmission/transmission/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="9144652fe742f7f7dd6657716e378da60b751aaeda8bef8344b3eefc4db255f2"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR" && make uninstall && cd ..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    download "$PKG_SOURCE_URL" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "$PKG_SOURCE_SUBDIR"

    cd "$PKG_SOURCE_SUBDIR"

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
        --prefix="/opt/static" \
        --with-sysroot="$TOMATOWARE_SYSROOT" \
    || handle_configure_error $?

    $MAKE
    make DESTDIR="$TOMATOWARE_SYSROOT/install/${PKG_SOURCE_SUBDIR}" install

    cd "/$TOMATOWARE_SYSROOT/install/${PKG_SOURCE_SUBDIR}/opt/static/bin"
    mv -f transmission-cli transmission-cli.static
    mv -f transmission-create transmission-create.static
    mv -f transmission-cli-static transmission-cli.static
    mv -f transmission-daemon transmission-daemon.static
    mv -f transmission-edit transmission-edit.static
    mv -f transmission-remote transmission-remote.static
    mv -f transmission-show transmission-show.static
    cd $OLDPWD

    touch __package_installed
fi
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "3.00" ]



if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6" ]; then
################################################################################
# transmission-4.0.6

PKG_NAME=transmission
PKG_VERSION=4.0.6
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_SOURCE_URL="https://github.com/transmission/transmission/releases/download/${PKG_VERSION}/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="2a38fe6d8a23991680b691c277a335f8875bdeca2b97c6b26b598bc9c7b0c45f"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/build/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR/build" && make uninstall && cd ../..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    download "$PKG_SOURCE_URL" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "$PKG_SOURCE_SUBDIR"
    cd "$PKG_SOURCE_SUBDIR"

    rm -rf build && mkdir -p build && cd build

    cmake \
      -DCMAKE_INSTALL_PREFIX="$TOMATOWARE_SYSROOT" \
      -DCMAKE_PREFIX_PATH="$TOMATOWARE_SYSROOT" \
      -DENABLE_STATIC=ON \
      -DENABLE_SHARED=OFF \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      ../

    $MAKE
    make install

    cd ..

    touch __package_installed
fi
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6" ]



if is_version_git "$BUILD_TRANSMISSION_VERSION"; then
################################################################################
# XML-Parser-2.47

PKG_NAME=XML-Parser
PKG_VERSION=2.47
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://cpan.metacpan.org/authors/id/T/TO/TODDR/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="ad4aae643ec784f489b956abe952432871a622d4e2b5c619e8855accbfc4d1d8"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR" && make uninstall && cd ..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    download "$PKG_SOURCE_URL" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    cd "$PKG_SOURCE_SUBDIR"

    perl Makefile.PL \
        EXPATLIBPATH=/mmc/lib \
        EXPATINCPATH=/mmc/include

    $MAKE
    make test
    make install

    touch __package_installed
fi

################################################################################
# intltool-0.51.0

PKG_NAME=intltool
PKG_VERSION=0.51.0
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_SOURCE_URL="https://launchpad.net/intltool/trunk/${PKG_VERSION}/+download/${PKG_SOURCE}"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_HASH="67c74d94196b153b774ab9f89b2fa6c6ba79352407037c8c14d5aeb334e959cd"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR" && make uninstall && cd ..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    download "$PKG_SOURCE_URL" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    cd "$PKG_SOURCE_SUBDIR"

    ./configure \
        --prefix="$TOMATOWARE_SYSROOT" \
    || handle_configure_error $?

    $MAKE
    make install

    touch __package_installed
fi
fi # if is_version_git "$BUILD_TRANSMISSION_VERSION"



if [ "$BUILD_TRANSMISSION_VERSION" = "3.00+git" ]; then
################################################################################
# transmission-3.00+git

PKG_NAME=transmission
PKG_VERSION="3.00+git"
PKG_SOURCE_URL="https://github.com/transmission/transmission.git"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_SOURCE_VERSION="bb6b5a062ee594dfd4b7a12a6b6e860c43849bfd"
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-${PKG_SOURCE_VERSION}.tar.xz"
PKG_HASH_VERIFY="tar_extract"
PKG_HASH="84bf5f638e6cb20f63a037f7c29695576d786c35e3d8be2e21f4cdf6a0e419f4"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR" && make uninstall && cd ..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    clone_to_archive "$PKG_SOURCE_URL" "$PKG_SOURCE_VERSION" "$PKG_SOURCE_SUBDIR" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH" "$PKG_HASH_VERIFY"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "$PKG_SOURCE_SUBDIR"
    cd "$PKG_SOURCE_SUBDIR"

    ./autogen.sh

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
        --prefix="/opt/static" \
        --with-sysroot="$TOMATOWARE_SYSROOT" \
    || handle_configure_error $?

    $MAKE
    make DESTDIR="$TOMATOWARE_SYSROOT/install/${PKG_SOURCE_SUBDIR}" install

    cd "/$TOMATOWARE_SYSROOT/install/${PKG_SOURCE_SUBDIR}/opt/static/bin"
    mv -f transmission-cli transmission-cli.static
    mv -f transmission-create transmission-create.static
    mv -f transmission-cli-static transmission-cli.static
    mv -f transmission-daemon transmission-daemon.static
    mv -f transmission-edit transmission-edit.static
    mv -f transmission-remote transmission-remote.static
    mv -f transmission-show transmission-show.static
    cd $OLDPWD

    touch __package_installed
fi
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "3.00+git" ]



if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6+git" ]; then
################################################################################
# transmission-4.0.6+git

PKG_NAME=transmission
PKG_VERSION="4.0.6+git"
PKG_SOURCE_URL="https://github.com/transmission/transmission.git"
PKG_SOURCE_SUBDIR="${PKG_NAME}-${PKG_VERSION}"
PKG_SOURCE_VERSION="38c164933e9f77c110b48fe745861c3b98e3d83e"
PKG_SOURCE="${PKG_NAME}-${PKG_VERSION}-${PKG_SOURCE_VERSION}.tar.xz"
PKG_HASH_VERIFY="tar_extract"
PKG_HASH="08ed7249432db3ed8cf9ad57eac0cf0ece81f53fcf8952248bc0e0ddd48419e4"

mkdir -p "${SRC}/${PKG_NAME}" && cd "${SRC}/${PKG_NAME}"

if $REBUILD_ALL; then
    if [ -f "$PKG_SOURCE_SUBDIR/build/Makefile" ]; then
        cd "$PKG_SOURCE_SUBDIR/build" && make uninstall && cd ../..
    fi
    rm -rf "$PKG_SOURCE_SUBDIR"
fi

if [ ! -f "$PKG_SOURCE_SUBDIR/__package_installed" ]; then
    clone_to_archive "$PKG_SOURCE_URL" "$PKG_SOURCE_VERSION" "$PKG_SOURCE_SUBDIR" "$PKG_SOURCE" "."
    verify_hash "$PKG_SOURCE" "$PKG_HASH" "$PKG_HASH_VERIFY"
    unpack_archive "$PKG_SOURCE" "$PKG_SOURCE_SUBDIR"
    apply_patches "${SCRIPT_DIR}/patches/${PKG_NAME}/${PKG_SOURCE_SUBDIR}/entware" "$PKG_SOURCE_SUBDIR"
    cd "$PKG_SOURCE_SUBDIR"

    rm -rf build && mkdir -p build && cd build

    cmake \
      -DCMAKE_INSTALL_PREFIX="$TOMATOWARE_SYSROOT" \
      -DCMAKE_PREFIX_PATH="$TOMATOWARE_SYSROOT" \
      -DENABLE_STATIC=ON \
      -DENABLE_SHARED=OFF \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      ../

    $MAKE
    make install

    cd ..

    touch __package_installed
fi
fi # if [ "$BUILD_TRANSMISSION_VERSION" = "4.0.6+git" ]


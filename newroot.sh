#!/usr/bin/env sh

usage()
{
    ee "usage: ${0} distdir rootdir"
    ee
    ee "creates a directory structure mostly similar to an actual 2.11-BSD install"
    ee "for the purpose of being used as the base commit of a git repository."
    ee
    ee "  distdir       the location of 2.11-BSD distribution files"
    ee "  rootdir       where to create the root tree and repository"
    ee
    exit 1
}

_CWD=$(pwd)

# naive attempt at figuring out where to find common.sh
_SCRIPT_DIR=$(dirname "${0}")

if [ ! -r "${_SCRIPT_DIR}/common.sh" ]; then
    echo "can't find common.sh" 1>&2
    exit 127
fi

. "${_SCRIPT_DIR}/common.sh"

if [ -z "${1}" ] || [ -z "${2}" ]; then
    usage
fi

_DIST_DIR="${1}"
_ROOT_DIR="${2}"

shift
shift

_USR_DIR="${_ROOT_DIR}/usr"
_SRC_DIR="${_ROOT_DIR}/usr/src"

if [ -e "${_ROOT_DIR}" ] \
       && [ $(( $(ls "${_ROOT_DIR}" | wc -l) )) -gt 0 ]; then
    fail "won't overwrite ${_ROOT_DIR}"
fi

mkdir -p "${_ROOT_DIR}" > /dev/null

is_readable_dir "${_DIST_DIR}"

_ROOTDUMP="${_DIST_DIR}/root.afio.gz"
is_readable "${_ROOTDUMP}"

ee_nonl "extracting root dump... "

cd "${_ROOT_DIR}"

gzcat "${_ROOTDUMP}" | cpio -idm > /dev/null 2>&1

ee "done."

# quick sanity check
is_directory "${_ROOT_DIR}"/bin

_FILE6="${_DIST_DIR}/file6.tar.gz"
_FILE7="${_DIST_DIR}/file7.tar.gz"
_FILE8="${_DIST_DIR}/file8.tar.gz"

mkdir -p "${_USR_DIR}" > /dev/null
mkdir -p "${_SRC_DIR}" > /dev/null

is_writable_dir "${_USR_DIR}"
is_writable_dir "${_SRC_DIR}"

ee_nonl "extracting file6... "
tar -C "${_USR_DIR}" -xzf "${_FILE6}"
ee "done."

ee_nonl "extracting file7... "
tar -C "${_SRC_DIR}" -xzf "${_FILE7}" 
ee "done."

ee_nonl "extracting file8... "
tar -C "${_SRC_DIR}" -xzf "${_FILE8}" 
ee "done."

chmod -R u+w "${_ROOT_DIR}"

_EXECUTABLES=$(mktemp)

ee_nonl "cleaning up binaries... "
find "${_ROOT_DIR}" -type f -perm -0100 > "${_EXECUTABLES}"
for _file in $(cat "${_EXECUTABLES}"); do
    chmod u+r "${_file}"
    file "${_file}"
done | grep 'PDP-11.*executable' | cut -d: -f1 | xargs rm -f
ee "done."

rm -f "${_ROOT_DIR}"/lib/crt0.o \
   "${_ROOT_DIR}"/lib/mcrt0.o \
   "${_ROOT_DIR}"/lib/libc.a \
   "${_ROOT_DIR}"/usr/lib/*.a \
   "${_ROOT_DIR}"/vmunix

get_version
now_at

_PATCH_NUM="${_VERSION}"
_GIT_BRANCH="${_GIT_BRANCH_PREFIX}${_PATCH_NUM}"

cd "${_ROOT_DIR}"

git init .
git add .
git checkout -B ${_GIT_BRANCH}

set_git_author_date "${_ROOT_DIR}/VERSION"

if ! git commit --cleanup=whitespace -qF "${_ROOT_DIR}"/VERSION; then
    fail "could not create the initial commit"
fi

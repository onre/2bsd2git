#!/usr/bin/env sh

# this script attempts to semi-automatically turn 2.11-BSD patches
# from pl450 onwards into 'git' commits. it is written for NetBSD
# /bin/sh so it should be rather portable.

_CWD=$(pwd)

# path to the dir containing the tree to patch
_TREE_DIR="${_CWD}/root"
# 'git' repository dir
_REPO_DIR="${_TREE_DIR}/usr/src"

_PATCH_NUM=$(basename "${1}")

# the work area, mostly a glorified temporary directory
_WORK_DIR="${_CWD}/tmp/${_PATCH_NUM}"

# path to patchsplit utility (gcc -o patchsplit patchsplit.c)
_PATCHSPLIT="${_CWD}/patchsplit"

_PATCH_FILE="${_WORK_DIR}/patch"
_MESSAGE_FILE="${_WORK_DIR}/message"
_PATCH_LOG_FILE="${_WORK_DIR}/patch.log"

# naming convention for per-patch branches
_GIT_BRANCH_SUFFIX="pl"
_GIT_BRANCH="${_GIT_BRANCH_SUFFIX}${_PATCH_NUM}"

# options to 'patch' command.  it's worth noting that some patches
# (#432, for example) fail the dress rehearsal because they patch the
# same file twice.

#_PATCH_FLAGS="--dry-run"		# GNU
#_PATCH_FLAGS="--check"			# BSD
_PATCH_FLAGS="-s -F 3 -l -V none"

usage()
{
    stderr_echo "usage: patch2commit.sh patch"
    exit 1
}

stderr_echo()
{
    echo "$@" 1>&2
}

stderr_echo_nonl()
{
    echo -n "$@" 1>&2
}

fail()
{
    exec 8>&-
    stderr_echo "$@"
    exit 127
}

is_writable_dir()
{
    if [ ! -d "${1}" ]; then
	fail "not a directory: ${1}"
    fi
    if [ ! -w "${1}" ] || [ ! -x "${1}" ]; then
	fail "not writable: ${1}"
    fi
}

cleanup_orig_rej()
{
    is_writable_dir "${1}"
    find "${1}" -name \*.orig -exec rm {} \; -or -name \*.rej -exec rm {} \;
}

cleanup_file()
{
    if [ -f "${1}" ]; then
	stderr_echo "cleaning up ${1}"
	if ! rm -f "${1}"; then
	    fail "could not remove ${1}"
	fi 
    fi
}

cleanup_dir()
{
    _prevdir=$(pwd)
    is_writable_dir "${1}"

    cd "${1}"

    # sanity or paranoia check? you decide.
    if [ $(pwd) != "${1}" ]; then
	fail "could not cd to ${1}"
    fi

    rm *
    
    cd "${_prevdir}"
}

reset_repo()
{
    _prevdir=$(pwd)
    cd "${_REPO_DIR}"
    _prevbranch="${_GIT_BRANCH_SUFFIX}$((_PATCH_NUM - 1))"
    stderr_echo "checking out ${_prevbranch} and resetting"
    if ! git checkout "${_prevbranch}" \
	 2>> "${_PATCH_LOG_FILE}" 1>&2; then
	fail "could not checkout ${_prevbranch}"
    fi
    if ! git reset --hard \
	 2>> "${_PATCH_LOG_FILE}" 1>&2; then
	fail "could not reset ${_prevbranch}"
    fi
    cd "${_prevdir}"
}

now_at()
{
    stderr_echo
    head -2 "${_TREE_DIR}/VERSION" 1>&2
    stderr_echo
}

if [ -z "${1}" ]; then
    usage
fi

if [ ! -r "${1}" ]; then
    stderr_echo "${1} not readable"
    exit 127
fi

mkdir -p "${_WORK_DIR}"

if [ ! -d "${_WORK_DIR}" ]; then
    fail "could not mkdir ${_WORK_DIR}"
fi

cleanup_dir "${_WORK_DIR}"

reset_repo
now_at

if ! "${_PATCHSPLIT}" "${1}" "${_MESSAGE_FILE}" "${_PATCH_FILE}"; then
    # patchsplit should produce an error message with enough information
    exit $?
fi

cd "${_REPO_DIR}"

diff_apply()
{
    if ! patch ${_PATCH_FLAGS} -p0 < "${1}" \
	 1>&2 2>> "${_PATCH_LOG_FILE}"; then
	fail "patch failed to apply, see ${_PATCH_LOG_FILE}"
    fi
}

stderr_echo "creating git branch ${_GIT_BRANCH}"
if ! git checkout -B "${_GIT_BRANCH}" 1>&2 2>> "${_PATCH_LOG_FILE}"; then
    fail "could not checkout ${_GIT_BRANCH}, see ${_PATCH_LOG_FILE}"
fi


if file "${_PATCH_FILE}" | grep -q 'context diff output'; then
    stderr_echo "patch #${_PATCH_NUM} is a context diff"
    stderr_echo "applying patch #${_PATCH_NUM} to ${_TREE_DIR}"
    cd "${_TREE_DIR}"
    diff_apply "${_PATCH_FILE}"
elif file "${_PATCH_FILE}" | grep -q 'POSIX shell script'; then
    stderr_echo "patch #${_PATCH_NUM} is a shell archive,"\
		"running it in ${_WORK_DIR}"
    cd "${_WORK_DIR}"
    # the only way of getting 2BSD shell archives to not try to expand
    # parameters in the here-document part was to use ksh with the -u
    # option and additionally enclose the here-doc EOF marker in
    # quotes, as instructed in the ksh(1) manual page.
    _T=$(mktemp)
    sed "s,<< SHAR_EOF >,<< 'SHAR_EOF' >,g" < "${_PATCH_FILE}" > "${_T}"
    cat "${_T}" > "${_PATCH_FILE}"
    rm -f "${_T}"
    ksh -us < "${_PATCH_FILE}"
    # we know something about certain patches and this is where the special
    # application steps can be taken.
    case "${_PATCH_NUM}" in
	452)
	    _T=$(mktemp)
	    cd "${_TREE_DIR}"
	    stderr_echo "running script 452-rm"
	    sh "${_WORK_DIR}"/452-rm
	    stderr_echo "applying patch #${_PATCH_NUM} to ${_TREE_DIR}"
	    sed 's,X!,\\\n!,g' < "${_WORK_DIR}"/452-diffs > "${_T}"
	    cat "${_T}" > "${_WORK_DIR}"/452-diffs
	    diff_apply "${_WORK_DIR}"/452-diffs
	    ;;
	*)
	    stderr_echo "unknown shell archive patch, "\
			"better to continue manually."
	    stderr_echo "see the patch notes at: ${_MESSAGE_FILE}"
	    exit 0
	    ;;
    esac
else
    stderr_echo "don't know what to do with this:"
    file "${_PATCH_FILE}" 1>&2
    fail "add support manually and try again."
fi

stderr_echo "patch applied cleanly, committing"
cd "${_REPO_DIR}"
if ! git commit --cleanup=whitespace -aF "${_MESSAGE_FILE}"\
     2>> "${_PATCH_LOG_FILE}" 1>&2; then
    fail "could not commit changes, see ${_PATCH_LOG_FILE}"
fi
stderr_echo "all done"

exec 8>&-

#!/usr/bin/env sh

# this script attempts to semi-automatically turn 2.11-BSD patches
# from pl450 onwards into 'git' commits. it is written for NetBSD
# /bin/sh so it should be rather portable.

_CWD=$(pwd)

# naive attempt at figuring out where to find common.sh
_SCRIPT_DIR=$(dirname "${0}")

if [ ! -z "${ROOT_DIR}" ]; then
    _ROOT_DIR="${ROOT_DIR}"
else
    _ROOT_DIR="${_CWD}/root"
fi

if [ ! -z "${PATCH_DIR}" ]; then
    _PATCH_DIR="${PATCH_DIR}"
else
    _PATCH_DIR="${_CWD}/patches"
fi

if [ ! -z "${TMP_DIR}" ]; then
    _TMP_DIR="${TMP_DIR}"
else
    _TMP_DIR="${_CWD}/tmp"
fi

# figure out patch number here to make setting the following variables
# easier.
_PATCH_NUM=$(basename "${1}")

# the work area, mostly a glorified temporary directory.
_WORK_DIR="${_TMP_DIR}/${_PATCH_NUM}"

# path to patchsplit utility (gcc -o patchsplit patchsplit.c)
_PATCHSPLIT="${_CWD}/patchsplit"

_ORIG_PATCH_FILE="${_PATCH_DIR}/${1}"
_PATCH_FILE="${_WORK_DIR}/patch"
_MESSAGE_FILE="${_WORK_DIR}/message"
_PATCH_LOG_FILE="${_WORK_DIR}/patch.log"

# automatically hard-reset the repo to the branch name of previous
# patch derived as above.
_AUTO_RESET=true

# options to 'patch' command.  
if [ -z "${V}" ] || [ "${V}" -eq 0 ] ; then
    # silent, never reverse, more fuzz, ignore whitespace, no backups
    _PATCH_FLAGS="-s -N -F 3 -l -V none"
else
    # same but not silent
    _PATCH_FLAGS="-N -F 3 -l -V none"
fi

# options to git commit. patch 437 adds --allow-empty to this.
_GIT_COMMIT_FLAGS=""

# code begins.

if [ ! -r "${_SCRIPT_DIR}/common.sh" ]; then
    echo "can't find common.sh" 1>&2
    exit 127
fi

. "${_SCRIPT_DIR}/common.sh"

# naming convention for per-patch branches.
_GIT_BRANCH="${_GIT_BRANCH_PREFIX}${_PATCH_NUM}"

# show some kind of help and give up
usage()
{
    ee "usage: ${0} patch"
    exit 1
}

# delete all .orig and .rej files from the tree
cleanup_orig_rej()
{
    is_writable_dir "${1}"
    find "${1}" -name \*.orig -exec rm {} \; -or -name \*.rej \
	 -exec rm {} \; > /dev/null 2>&1
}

# delete the file
# $1 the file path
cleanup_file()
{
    if [ -f "${1}" ]; then
	vee "cleaning up ${1}"
	if ! rm -f "${1}"; then
	    fail "could not remove ${1}"
	fi 
    fi
}

# delete everything in the directory
# $1 the directory path
cleanup_dir()
{
    _prevdir=$(pwd)
    is_writable_dir "${1}"

    cd "${1}"

    # sanity or paranoia check? you decide.
    if [ $(pwd) != "${1}" ]; then
	fail "could not cd to ${1}"
    fi

    rm -f *
    
    cd "${_prevdir}"
}

# checkout the branch of the preceding patch and hard-reset the
# repository if $_AUTO_RESET is set to true
reset_repo()
{
    if ${_AUTO_RESET}; then
	_prevdir=$(pwd)
	cd "${_ROOT_DIR}"
	_prevbranch="${_GIT_BRANCH_PREFIX}$((_PATCH_NUM - 1))"
	vee "checking out ${_prevbranch} and resetting"
	if ! git checkout "${_prevbranch}" \
	     2>> "${_PATCH_LOG_FILE}" 1>&2; then
	    fail "could not checkout ${_prevbranch}"
	fi
	if ! git reset --hard \
	     2>> "${_PATCH_LOG_FILE}" 1>&2; then
	    fail "could not reset ${_prevbranch}"
	fi
	cd "${_prevdir}"
    fi
}

# apply a diff to the tree
# $1 the diff file
# $2 ignore failure for this particular file
diff_apply()
{
    if ! patch ${_PATCH_FLAGS} -p0 < "${1}" \
	 1>&2 2>> "${_PATCH_LOG_FILE}"; then
	if [ -z "${2}" ]; then
	    echo $?
	    fail "patch failed to apply, see ${_PATCH_LOG_FILE}"
	else
	    if [ $(grep -c "${2}" "${_PATCH_LOG_FILE}") -eq 1 ]; then
		ee "expected failure for ${2} ignored"
	    fi
	fi
    fi
}

# modify a shell script to use relative paths
script_to_relative_path()
{
    _T=$(mktemp)
    for _script in "$@"; do
	vee "altering ${_script} to use relative paths"
	sed s,/usr/,usr/,g < "${_script}" > "${_T}"
	cat "${_T}" > "${_script}"
    done
    rm -f "${_T}"
}

# modify a diff to use relative paths
diff_to_relative_path()
{
    _T=$(mktemp)
    for _diff in "$@"; do
	vee "altering ${_diff} to use relative paths"
	sed "s,--- /,--- ,g" < "${_diff}" > "${_T}"
	sed "s,\*\*\* /,*** ,g" < "${_T}" > "${_diff}"
    done
    rm -f "${_T}"
}

if [ -z "${1}" ]; then
    usage
fi

is_executable "${_PATCHSPLIT}"

is_readable "${_ORIG_PATCH_FILE}"

set_git_author_date "${_ORIG_PATCH_FILE}"

mkdir -p "${_WORK_DIR}" > /dev/null 2>&1
is_directory "${_WORK_DIR}"
cleanup_dir "${_WORK_DIR}"

reset_repo
cleanup_orig_rej "${_ROOT_DIR}"

# some postings don't have a 'cut here' line to separate the message
# from the patch. the -v option makes patchsplit look for the string
# '*** VERSION.orig' instead of 'cut here'
if [ "${_PATCH_NUM}" -eq 448 ]; then
    _PATCHSPLIT="${_PATCHSPLIT} -v"
fi

if ! ${_PATCHSPLIT} "${_ORIG_PATCH_FILE}" \
     "${_MESSAGE_FILE}" "${_PATCH_FILE}"; then
    exit $?
fi

cd "${_ROOT_DIR}"

vee "creating git branch ${_GIT_BRANCH}"
if ! git checkout -B "${_GIT_BRANCH}" 1>&2 2>> "${_PATCH_LOG_FILE}"; then
    fail "could not checkout ${_GIT_BRANCH}, see ${_PATCH_LOG_FILE}"
fi

# NetBSD file(1) fails to identify some diffs...
if file "${_PATCH_FILE}" | grep -q 'context diff output' \
    || head -1 "${_PATCH_FILE}" | grep -q '^*** ./' ; then

    vee "patch #${_PATCH_NUM} is a context diff"
    if grep -q '^*** /' "${_PATCH_FILE}"; then
	diff_to_relative_path "${_PATCH_FILE}"
    fi
    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"

    # PER-PATCH ALLOWED FAILURES GO HERE
    case  "${_PATCH_NUM}" in
	445)

	    # this one is already patched on the pl431 dist at TUHS,
	    # probably because of the reasons mentioned in the patch
	    # message.
	    
	    diff_apply "${_PATCH_FILE}" "usr/src/local/mp/Makefile"
	    ;;
	475)

	    # no idea what happened here. 'Current' is '$urrent' from
	    # 470 to 474...

	    _T=$(mktemp)
	    sed 's,Current Patch Level: 474,$urrent Patch Level: 474,' \
		< "${_PATCH_FILE}" > "${_T}"
	    cat "${_T}" > "${_PATCH_FILE}"
	    rm -f "${_T}"
	    diff_apply "${_PATCH_FILE}"
	    ;;
	*)
	    diff_apply "${_PATCH_FILE}"
	    ;;
    esac

elif file "${_PATCH_FILE}" | grep -q 'POSIX shell script'; then

    vee "patch #${_PATCH_NUM} is a shell archive,"\
	"running it in ${_WORK_DIR}"
    cd "${_WORK_DIR}"

    # the only way of getting some of the older 2BSD patch shell
    # archives to not try to expand parameters in the here-document
    # part was to use ksh with the -u option and additionally enclose
    # the here-doc EOF marker in quotes, as instructed in the ksh(1)
    # manual page. later ones seem to have used \SHAR_EOF and wouldn't
    # need this, but ... it does not break anything?

    _T=$(mktemp)
    sed "s,<< SHAR_EOF >,<< 'SHAR_EOF' >,g" < "${_PATCH_FILE}" > "${_T}"
    cat "${_T}" > "${_PATCH_FILE}"
    rm -f "${_T}"
    ksh -us < "${_PATCH_FILE}"

    # PER-PATCH SPECIAL RECIPES FOR SHELL ARCHIVE PATCHES ARE HERE
    #
    # at this point the shell archive has been extracted into
    # ${_WORK_DIR}, which is also the current working directory.
    
    case "${_PATCH_NUM}" in
	432)
	    script_to_relative_path 432.sh 432.rm
	    diff_to_relative_path 432.patch

	    cd "${_ROOT_DIR}"
	    
	    vee "following the recipe for patch #432"
	    vee "running script 432.sh"
	    sh "${_WORK_DIR}"/432.sh
	    vee "running script 432.rm"
	    sh "${_WORK_DIR}"/432.rm
	    
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    sed 's,X!,\\\n!,g' < "${_WORK_DIR}"/432.patch > "${_T}"
	    cat "${_T}" > "${_WORK_DIR}"/432.patch
	    diff_apply "${_WORK_DIR}"/432.patch
	    ;;
	440)
	    diff_to_relative_path 440.patch

	    cd "${_ROOT_DIR}"

	    # skipping the binary copying step deliberately
	    
	    vee "following the recipe for patch #440"
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    diff_apply "${_WORK_DIR}"/440.patch
	    ;;
	441)
	    script_to_relative_path 441.sh
	    script_to_relative_path 441.shar
	    diff_to_relative_path 441.patch

	    cd "${_ROOT_DIR}"
	    
	    vee "following the recipe for patch #441"
	    sh "${_WORK_DIR}"/441.sh
	    ksh -us < "${_WORK_DIR}"/441.shar
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    diff_apply "${_WORK_DIR}"/441.patch
	    ;;
	442)
	    script_to_relative_path 442.shar
	    diff_to_relative_path 442.patch

	    cd "${_ROOT_DIR}"
	    
	    vee "following the recipe for patch #442"
	    vee "extracting 442.shar"
	    ksh -us < "${_WORK_DIR}"/442.shar
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    diff_apply "${_WORK_DIR}"/442.patch
	    ;;
	452)
	    _T=$(mktemp)
	    cd "${_ROOT_DIR}"
	    vee "following the recipe for patch #452"
	    vee "running script 452-rm"
	    sh "${_WORK_DIR}"/452-rm
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    sed 's,X!,\\\n!,g' < "${_WORK_DIR}"/452-diffs > "${_T}"
	    cat "${_T}" > "${_WORK_DIR}"/452-diffs
	    diff_apply "${_WORK_DIR}"/452-diffs "usr/src/share/lint/llib-lc"
	    rm -f "${_T}"
	    ;;
	459)
	    _T=$(mktemp)
	    cd "${_ROOT_DIR}"
	    vee "following the recipe for patch #459"
	    cp "${_WORK_DIR}/stdarg.h" \
	       "${_ROOT_DIR}/usr/include"
	    git rm -r "${_ROOT_DIR}/usr/include/vaxuba"
	    git rm -r "${_ROOT_DIR}/usr/include/sys/vaxuba"
	    git rm "${_ROOT_DIR}/usr/src/asm.sed*"
	    git rm -r "${_ROOT_DIR}/usr/src/include"
	    vee "applying patch #${_PATCH_NUM} to ${_ROOT_DIR}"
	    diff_apply "${_WORK_DIR}"/459.patch
	    ;;
	460)
	    cd "${_ROOT_DIR}"
	    vee "following the recipe for patch #460"
	    diff_apply "${_WORK_DIR}"/ccom.patch
	    uudecode -p < "${_WORK_DIR}/cpp.tar.Z.uu" | uncompress | tar xpf -
	    diff_apply "${_WORK_DIR}"/src.patch "./usr/src/sys/pdp/net_csv.s"
	    ;;
	465)
	    vee "following the recipe for patch #465"
	    script_to_relative_path "${_WORK_DIR}/top.shar"
	    cd "${_ROOT_DIR}"
	    sh "${_WORK_DIR}/top.shar"
	    diff_apply "${_WORK_DIR}"/465.patch
	    ;;
	471)
	    vee "following the recipe for patch #471"
	    cd "${_ROOT_DIR}"
	    uudecode -p < "${_WORK_DIR}"/471.uu | uncompress | tar xvpf -
	    chmod u+w usr/src/ucb/more/more.c
	    diff_apply "${_WORK_DIR}"/471.diffs
	    ;;
	*)
	    ee "*** no special recipe for #${_PATCH_NUM}, trying the"\
			"easy way"
	    ee "*** check the patch notes at ${_MESSAGE_FILE}"
	    ee "*** and, if necessary, add the recipe to patch2commit.sh"

	    if [ -r "${_WORK_DIR}/${_PATCH_NUM}-patch" ]; then
		_SUB_PATCH_FILE="${_WORK_DIR}/${_PATCH_NUM}-patch"
	    elif [ -r "${_WORK_DIR}/${_PATCH_NUM}.patch" ]; then
		_SUB_PATCH_FILE="${_WORK_DIR}/${_PATCH_NUM}.patch"
	    elif [ -r "${_WORK_DIR}/${_PATCH_NUM}.diffs" ]; then
		_SUB_PATCH_FILE="${_WORK_DIR}/${_PATCH_NUM}.diffs"
	    else
		ee "tried ${_PATCH_NUM}-patch, ${_PATCH_NUM}.patch or ${_PATCH_NUM}.diffs,"
		fail "but none matched - see the notes and write a recipe."
	    fi
		
	    diff_to_relative_path "${_SUB_PATCH_FILE}"

	    cd "${_ROOT_DIR}"

	    diff_apply "${_SUB_PATCH_FILE}"
	    ;;
    esac
    
elif file "${_PATCH_FILE}" | grep -q 'uuencoded text.*\.tar\.Z"'; then

    # this one sorely needs some sort of "confirmation mechanism"
    
    ee "*** patch #${_PATCH_NUM} is an uuencoded tape archive,"
    ee "*** extracting it to ${_ROOT_DIR}"
    cd "${_ROOT_DIR}"
    uudecode -p < "${_PATCH_FILE}" | uncompress | tar xvpf -
    
elif [ "${_PATCH_NUM}" -eq 437 ]; then
	
    # 437 is a placeholder without diff, but we'll create the
    # branch and commit nonetheless
    
    vee "patch #437 is a placeholder w/o diff, committing only the message"

    _GIT_COMMIT_FLAGS="${_GIT_COMMIT_FLAGS} --allow-empty"
    
elif [ "${_PATCH_NUM}" -eq 470 ]; then

    # this is an interesting one, see the patch message.
    
    vee "following the recipe for patch #470"

    cd "${_WORK_DIR}"

    uudecode -p < "${_PATCH_FILE}" | tar xvpf -

    # oversimplifying, but git does not save file ownership information.
    
    cp -p "${_WORK_DIR}/makewhatis.sed" \
       "${_ROOT_DIR}/usr/src/man"

    cd "${_ROOT_DIR}"

    diff_apply "${_WORK_DIR}/470.patch"
    
else
    
    ee "don't know what to do with this file:"
    file "${_PATCH_FILE}" 1>&2
    fail "add a recipe to patch2commit.sh and try again."
    
fi

cleanup_orig_rej "${_ROOT_DIR}"
git add "${_ROOT_DIR}"
ee "patch #${_PATCH_NUM} applied cleanly, committing"
cd "${_ROOT_DIR}"
if ! git commit ${_GIT_COMMIT_FLAGS} --cleanup=whitespace \
     -aF "${_MESSAGE_FILE}" 2>> "${_PATCH_LOG_FILE}" 1>&2; then
    fail "could not commit changes, see ${_PATCH_LOG_FILE}"
fi
now_at
vee "all done"

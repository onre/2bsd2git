#!/usr/bin/env sh
#
# NOTE - there are sanity checks at the _end_ of this file

# commits will appear as they were authored by this entity.
GIT_AUTHOR_NAME="2BSD contributors"
GIT_AUTHOR_EMAIL="patches-2bsd@example.com"

export GIT_AUTHOR_NAME
export GIT_AUTHOR_EMAIL

# the suffix to use for per-patch branches
_GIT_BRANCH_SUFFIX="pl"

# the timezone offset for commits, see git-commit(1) (search for DATE)
_GIT_TZ_OFFSET="0000"

# echo to stderr
stderr_echo()
{
    echo "$@" 1>&2
}

# echo to stderr without newline
stderr_echo_nonl()
{
    echo -n "$@" 1>&2
}

# print error and give up
fail()
{
    stderr_echo "$@"
    exit 127
}

# a bunch of instant-fail test(1) wrappers

# does the path exist
is_existent()
{
    if [ -z "${1}" ]; then
	fail "is_existent(): empty argument supplied"
    fi
    if [ ! -e "${1}" ]; then
	fail "not found: ${1}"
    fi
}

# is it a regular file
is_file()
{
    is_existent "${1}"
    if [ ! -f "${1}" ]; then
	fail "not a regular file: ${1}"
    fi
}

# is it a directory
is_directory()
{
    is_existent "${1}"
    if [ ! -d "${1}" ]; then
	fail "not a directory: ${1}"
    fi
}

# check for file read access
is_readable()
{
    if [ ! -r "${1}" ]; then
	fail "not readable: ${1}"
    fi
}

# can it be written to
is_writable()
{
    if [ ! -w "${1}" ]; then
	fail "not writable: ${1}"
    fi
}

# does it have the executable bit set 
is_executable()
{
    if [ ! -x "${1}" ]; then
	fail "not executable: ${1}"
    fi
}

# check for directory write access
is_writable_dir()
{
    is_directory "${1}"
    is_executable "${1}"
    is_writable "${1}"
}

# check for directory read access
is_readable_dir()
{
    is_directory "${1}"
    is_executable "${1}"
    is_readable "${1}"
}

# show current /VERSION contents
now_at()
{
    if [ -z "${_ROOT_DIR}" ]; then
	fail "_ROOT_DIR not set, can't read version information"
    fi
    
    stderr_echo
    head -2 "${_ROOT_DIR}/VERSION" 1>&2
    stderr_echo
}

# get the directory tree version
get_version()
{
    if [ -z "${_ROOT_DIR}" ]; then
	fail "_ROOT_DIR not set, can't read version information"
    fi
    
    _VERSION=$(( $( head -1 "${_ROOT_DIR}/VERSION" | cut -d: -f2 ) ))
    if [ ! "${_VERSION}" -gt 1 ]; then
	fail "can't read version information from ${_ROOT_DIR}/VERSION"
    fi
}

# sets git author date to mtime of first argument
set_git_author_date()
{
    is_existent "${1}"
    GIT_AUTHOR_DATE=$(stat -f '%m' "${1}")" ${_GIT_TZ_OFFSET}"
    export GIT_AUTHOR_DATE 
}

for _requirement in git patch ksh cpio; do
    if ! which ${_requirement} > /dev/null; then
	fail "missing dependency: ${_requirement}"
    fi
done


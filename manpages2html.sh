#!/usr/bin/env bash

_SCRIPT_DIR=$(dirname "${0}")
. "${_SCRIPT_DIR}/common.sh"

# TODO: 3f
_SECTIONS="1 2 3 4 5 6 7 8"

# adjust to point to your own custom file or the one supplied with mandoc
_CSS="../man.css"

_MANDOC_FLAGS="-I os=2.11-BSD -O toc,style=${_CSS},man=%N.%S.html;../man%S/%N.%S.html"

# make(1) passes these from Makefile
_MAN_SRC_DIR="${ROOT_DIR}/usr/src/man"
_HTML_MAN_DIR="${HTML_MAN_DIR}"

test -d "${_MAN_SRC_DIR}" || fail "can't open ${_MAN_SRC_DIR}"

for S in ${_SECTIONS}; do
    cd "${_MAN_SRC_DIR}/man${S}/" || fail "${_MAN_SRC_DIR}/man${S}"

    ee_nonl "converting section ${S} to HTML"
    
    for N in "${_MAN_SRC_DIR}/man${S}/"*".${S}"; do
	NAME=$( basename "${N}" )

	test -d "${_HTML_MAN_DIR}/man${S}" \
	    || mkdir -p "${_HTML_MAN_DIR}/man${S}"

	mandoc -T html ${_MANDOC_FLAGS} \
	       < "${N}" \
	       > "${_HTML_MAN_DIR}/man${S}/${NAME}.html" || exit $?
	vee "wrote ${_HTML_MAN_DIR}/man${S}/${NAME}.html" 1>&2
	ee_nonl "."
    done

    ee " done."
done

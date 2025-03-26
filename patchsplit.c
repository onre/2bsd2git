#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define eprintf(...) fprintf(stderr, __VA_ARGS__); fflush(stderr);

void usage(void) {
    eprintf("usage: patchsplit [ -v ] patchfile message diff\n\n");
    eprintf("  -v\tuse the string \"VERSION.orig\" as the split point\n\n");
    exit(-1);
}

int main(int argc, char **argv) {
    FILE *patchp;
    FILE *msgp;
    FILE *diffp;
    char *line = NULL;
    int to_diffp, look_for_version;
    size_t len, linelen, msglines, difflines;

    to_diffp = 0;
    look_for_version = 0;
    msglines = 0;
    difflines = 0;

    if (argc < 4 || argc > 5)
	usage();

    if (!strncmp("-v", argv[1], 2)) {
	look_for_version = 1;
	argv++;
    }
    
    patchp = fopen(argv[1], "r");

    if (patchp == NULL) {
	perror(argv[1]);
	exit(-1);
    }

    msgp = fopen(argv[2], "w");

    if (msgp == NULL) {
	perror(argv[2]);
	exit(-1);
    }

    diffp = fopen(argv[3], "w");

    if (diffp == NULL) {
	perror(argv[3]);
	exit(-1);
    }

    while ((linelen = getline(&line, &len, patchp)) != -1) {
	/* constructing this 'if' exactly like this makes the 'cut here'
	 * line not end up in either of the files.
	 */
	if (!look_for_version && strstr(line, "cut here") != NULL) {
	    to_diffp = 1;
	} else {
	    if (look_for_version && strstr(line, "*** VERSION.orig") != NULL)
		to_diffp = 1;
	    if (to_diffp) {
		fwrite(line, linelen, 1, diffp);
		difflines++;
	    } else {
		fwrite(line, linelen, 1, msgp);
		msglines++;
	    }
	}
    }
    if (!msglines) {
	eprintf("something is amiss - 0 message lines\n");
	exit(-2);
    }
#ifdef VERBOSE
    if (!difflines) {
	eprintf("%s: %ld lines\nno diff found\n",
		argv[2], msglines);
    } else {
	eprintf("%s: %ld lines\n%s: %ld lines\n",
		argv[2], msglines,
		argv[3], difflines);
    }
#endif
    return 0;
}

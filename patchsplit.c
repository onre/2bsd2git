#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define eprintf(...) fprintf(stderr, __VA_ARGS__); fflush(stderr);

void usage(void) {
    eprintf("usage: patchsplit patchfile message diff\n");
    exit(-1);
}

int main(int argc, char **argv) {
    FILE *patchp;
    FILE *msgp;
    FILE *diffp;
    char *line = NULL;
    int to_diffp;
    size_t len, linelen, msglines, difflines;

    to_diffp = 0;
    msglines = 0;
    difflines = 0;

    if (argc != 4)
	usage();

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
	if (strstr(line, "cut here") != NULL) {
	    to_diffp = 1;
	} else {
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
    if (!difflines) {
	eprintf("something is amiss - 0 diff lines\n");
	exit(-3);
    }
    eprintf("%s: %ld lines\n%s: %ld lines\n",
	    argv[2], msglines,
	    argv[3], difflines);
    return 0;
}

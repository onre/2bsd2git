ROOT_DIR	:= $(.CURDIR)/md/root
DIST_DIR	:= $(.CURDIR)/newdist
PATCH_DIR	:= $(.CURDIR)/patches
TMP_DIR		:= $(.CURDIR)/md/tmp

.export ROOT_DIR
.export DIST_DIR
.export PATCH_DIR
.export TMP_DIR

all: patchlevel-486

sanity:
	./common.sh

$(ROOT_DIR):
	mkdir -p $(ROOT_DIR)

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

$(PATCH_DIR):
	mkdir -p $(PATCH_DIR)

$(TMP_DIR):
	mkdir -p $(TMP_DIR)

$(DIST_DIR)/VERSION: $(DIST_DIR)
	rsync -avz www.tuhs.org::UA_Distributions/UCB/2.11BSD/ $(DIST_DIR)

$(PATCH_DIR)/440: $(DIST_DIR)/VERSION $(PATCH_DIR)
	for i in $(DIST_DIR)/Patches/???-???.tar.bz2; do \
		tar -C $(PATCH_DIR) -xpjf "$$i"; \
	done
	cp -p $(DIST_DIR)/Patches/??? $(PATCH_DIR)
	chmod u+w $(PATCH_DIR)/*

$(ROOT_DIR)/.git: $(ROOT_DIR) $(DIST_DIR)/VERSION
	./newroot.sh $(DIST_DIR) $(ROOT_DIR)

realclean: clean
	rm -f patchsplit
	rm -rf $(DIST_DIR)

clean:
	rm -f $(PATCH_DIR)/*
	rm -rf $(ROOT_DIR)

patchlevel-486: patchsplit $(ROOT_DIR)/.git $(PATCH_DIR)/440
	_CURRENT_PATCHLEVEL=$$(( $$(head -1 md/root/VERSION | \
		cut -d: -f2) )); \
	while [ $${_CURRENT_PATCHLEVEL} -lt 486 ]; do \
		_CURRENT_PATCHLEVEL=$$(( _CURRENT_PATCHLEVEL + 1 )); \
		./patch2commit.sh $${_CURRENT_PATCHLEVEL} || exit 1; \
	done

singleshot:
	./patch2commit.sh $(PATCH)

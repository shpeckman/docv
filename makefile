# makefile
INSTDIR = ~/.local/bin
MANDIR  = ~/.local/share/man
THREADS = 2

.PHONY: all help build release spec docs format install clean

all: help

help:               ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36mmake %-18s\033[0m \033[2;37m%s\033[0m\n", $$1, $$2}'

build:              ## Build bin/docv (debug)
	@mkdir -p bin
	crystal build --threads $(THREADS) src/cli.cr -o bin/docv

release:            ## Build bin/docv (release)
	@mkdir -p bin
	crystal build --threads $(THREADS) --release --no-debug src/cli.cr -o bin/docv

spec:               ## Run spec suite
	crystal spec --threads $(THREADS)

docs:               ## Generate API documentation into docs/
	crystal docs --threads $(THREADS)

format:             ## Format sources and specs
	crystal tool format src spec

install: release    ## Install bin/docv into INSTDIR and the man pages into MANDIR
	install -m 755 bin/docv $(INSTDIR)/docv
	install -D -m 644 man/man1/docv.1 $(MANDIR)/man1/docv.1
	install -D -m 644 man/man5/docv-config.5 $(MANDIR)/man5/docv-config.5

clean:              ## Remove build output
	rm -rf bin docs

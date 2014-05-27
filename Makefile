
BIN ?= dbu
PREFIX ?= /usr/local

install:
	install ./dropbox_uploader.sh $(PREFIX)/bin/$(BIN)
	install ./dropShell.sh $(PREFIX)/bin/$(BIN)-shell

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)
	rm -f $(PREFIX)/bin/$(BIN)-shell


all:
	@echo "Run 'make install' for installation."
	@echo "Run 'make uninstall' for uninstallation."

install:
	cp dropbox_uploader.sh /usr/bin/dropbox_uploader.sh
	cp dropShell.sh /usr/bin/dropShell.sh

uninstall:
	rm /usr/bin/dropbox_uploader.sh
	rm /usr/bin/dropShell.sh

all:
	@echo "Run 'make install' for installation."
	@echo "Run 'make uninstall' for uninstallation."

install:
	install -vb -m 755 drop{box_uploader,Shell}.sh /usr/local/bin

uninstall:
	rm /usr/local/bin/drop{box_uploader,Shell}.sh

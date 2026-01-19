################################################################################
#
# host-gcc-final override - Disable NLS to avoid ISO-8859-1 msgfmt errors
#
################################################################################

# GCC 15.2.0 has .po files with ISO-8859-1 encoding that fail msgfmt
# Disable NLS for host GCC (we don't need translated compiler messages)
HOST_GCC_FINAL_CONF_OPTS += --disable-nls

$(eval $(host-autotools-package))

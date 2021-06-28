#TODO clean up environment before setup
#!/bin/bash

# Freesurfer Processing Pipeline (FPP)
# Correct the APP_FREESURFER path for your setup if necessary
SRCDIR="$(dirname $(readlink -f ${BASH_SOURCE[0]:-$0}))"

export APPDIR="$(dirname ${SRCDIR})"
if [[ -z "${APPDIR}" ]]; then
    export APPDIR="${HOME}/proj/app-freesurfer"
fi

# CLI, log functions and error handler for bash scripts
# Correct the UTILS setting for your setup if necessary
export UTILS=
if [[ -z "${UTILS}" ]]; then
    export UTILS="${APPDIR}/lib"
fi

# Source freesurfer enviroment settings
APP_ENV="${APPDIR}/etc/environment"
source $APP_ENV

# Generate license file
rm -f "${APPDIR}/etc/license.txt"
echo $FREESURFER_LICENSE > "${APPDIR}/etc/license.txt"

# Source app configs
# Correct the APP_CONFIG path for your setup if necessary
APP_CONFIG=
if [[ -z "${APP_CONFIG}" ]]; then
    APP_CONFIG="$APPDIR/etc/app.conf"
fi
source $APP_CONFIG

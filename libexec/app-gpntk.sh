#!/bin/bash

#U .TH app-freesurfer 1
#U .SH NAME
#U app-freesurfer \- simple wrapper for freesurfer with support to computing clusters
#U .SH SYNOPSIS
#U .B app-freesurfer
#U command [command options]
#U .SH DESCRIPTION
#U .B app-freesurfer
#U is a convenience wrapper for using freesurfer in computing clusters
#U .sp 1
#U [command options] are passed on to the app-freesurfer command.
#U .SH COMMANDS
#U .IP man 12
#U display this manual page
#U .IP help 12
#U display the config.json keys supported by this application
#U .IP run 12
#U run [jobname] run a freesurfer job, where [jobname] is the name of a folder inside the jobs directory
#U .SH EXAMPLE
#U .B app-freesurfer run bert
#U .SH AUTHOR
#U Eduardo Diniz. Contact edd32@pitt.edu for help.

# ------------------------------------------------------------------------------
# Process groff input to create manual page
# ------------------------------------------------------------------------------
function usage() {
    grep '^#U ' "${BASH_SOURCE[0]}" \
        | cut -c4- \
        | groff -Tascii -man \
        | less -e
}

# ------------------------------------------------------------------------------
# If no arguments are passed, show help
# ------------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

# ------------------------------------------------------------------------------
# Set environment
# ------------------------------------------------------------------------------
# readlink -f gets read of any simlinks
# ${BASH_SOURCE[0]} gets the full path to this shell script
LIBDIR="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
APPDIR="$(dirname $LIBDIR)"

# ------------------------------------------------------------------------------
# API bash script
# ------------------------------------------------------------------------------
API_PATH="${APPDIR}/src/API_GPNTK.sh"
SPM_PATH="${APPDIR}/src/API_SPM.sh"
# ------------------------------------------------------------------------------
# Get FreeSurfer command arguments
# ------------------------------------------------------------------------------
# $0 -> app-freesurfer, $1 -> command
# the 'shift' will $1 -> $0, $0 -> $1, and so on
app_cmd=$1; shift # Remove `app-freesurfer` from the argument list

jobdir="$1"

# Parse command
while true; do
    case "$app_cmd" in
        man )
            cmd="man"
            shift
            break
            ;;
        help )
            cmd="help"
            shift
            break
            ;;
        run )
            cmd="run"
            shift
            break
            ;;
        run_spm )
            cmd="run_spm"
            shift
            break
            ;;
        * )
            usage
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Execute command
# ------------------------------------------------------------------------------
case "$cmd" in
    help )
        bash $API_PATH --help 
        bash $SPM_PATH --help
        ;;
    run )
        if [ -s $APPDIR/jobs/$jobdir/config.json ] ; then
            bash $API_PATH "$APPDIR/jobs/$jobdir/config.json"
        else
            usage
            exit 1
        fi
        ;;
    run_spm )
        if [ -s $APPDIR/jobs/$jobdir/config.json ] ; then
            bash $SPM_PATH "$APPDIR/jobs/$jobdir/config.json"
        else
            usage
            exit 1
        fi
        ;;
    man )
        usage
        exit 0
        ;;
esac

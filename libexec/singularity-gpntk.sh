#!/bin/bash

#U .TH gpntk 1
#U .SH NAME
#U gpntk \- simple wrapper around a gpntk 7.1.1 singularity container
#U .SH SYNOPSIS
#U .B gpntk
#U  [-L licensepath] [-B bindpath] command [command options]
#U .SH DESCRIPTION
#U .B gpntk
#U is a convenience wrapper around the singularity container
#U with gpntk 7.1.1.
#U -L is a path to a gpntk license in the host
#U -B is a bindpath string passed to singularity
#U [command options] are passed on to the gpntk command.
#U .SH COMMANDS
#U .IP help 12
#U display this help message
#U .IP recon-all 12
#U Performs gpntk 7.1.1 cortical reconstruction process
#U .IP recon-all.mask 12
#U Performs gpntk 7.1.1 cortical reconstruction process
#U with the ability to specify a mask for mri_em_register
#U .IP shell 12
#U get a bash shell inside the container
#U .IP hello 12
#U Echoes hello world from inside the container
#U .SH EXAMPLES
#U .B gpntk recon-all
#U -i <one slice in the dicom series> -s <subject id> -all
#U .P
#U .B gpntk recon-all.mask
#U .P
#U .B gpntk help
#U .P
#U .B gpntk shell
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
LIBEXECDIR="$(dirname $(readlink -f ${BASH_SOURCE[0]}))"
APPDIR="$(dirname ${LIBEXECDIR})"

# ------------------------------------------------------------------------------
# Singularity Image
# ------------------------------------------------------------------------------
SIF_PATH="${LIBEXECDIR}/gpntk.sif"

# ------------------------------------------------------------------------------
# Get SINGULARITY_BINDPATH and Freesurfer license
# ------------------------------------------------------------------------------
BINDPATH=""
echo $APPDIR
APP_LICENSE="${APPDIR}/etc/license.txt"
while getopts ":B:L:S:" opt; do
    case $opt in
        B )
            BINDPATH+=",${OPTARG}"
            ;;
        L )
            APP_LICENSE="${OPTARG}"
            ;;
        S )
            SIF_PATH="$SIF_PATH"
            ;;
        \? )
            echo "Invalid option: -$opt" >&2
            usage
            exit 1
            ;;
        : )
            echo "$opt requires an argument" >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# ------------------------------------------------------------------------------
# FreeSurfer Licence
# ------------------------------------------------------------------------------
APP_LICENSE="${APP_LICENSE}:/usr/local/freesurfer/license.txt"

# ------------------------------------------------------------------------------
# Get gpntk command arguments
# ------------------------------------------------------------------------------
# $0 -> gpntk, $1 -> command
# the 'shift' will $1 -> $0, $0 -> $1, and so on
gpntk_cmd=$1; shift # Remove `gpntk` from the argument list

args="$@"

# Parse command
while true; do
    case "$gpntk_cmd" in
        bash )
            cmd="bash"
            shift
            break
            ;;
        shell )
            cmd="shell"
            shift
            break
            ;;
        help )
            cmd="help"
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
# Execute command inside container
# ------------------------------------------------------------------------------
# -e, --cleanenv: remove the host environment and execute a container with a
# minimal environment
# --app all: for now, run image with both FreeSurfer and FSL loaded
#-c, --contain: use minimal /dev and empty other directories
# (e.g. /tmp and $HOME) instead of sharing filesystems from your host
case "$cmd" in
    bash )
        echo "singularity run -c -e -B $APP_LICENSE -B $BINDPATH $SIF_PATH /bin/bash --rcfile /etc/profile $args"
        singularity run -c -e \
            -B $APP_LICENSE -B $BINDPATH $SIF_PATH $args
        ;;
    shell )
        singularity exec -c -e \
            -B $APP_LICENSE $SIF_PATH /bin/bash --rcfile /etc/profile $args
        ;;
    help )
        usage
        exit 0
        ;;
esac

#!/bin/bash

trap 'halt' SIGINT SIGKILL SIGTERM SIGSEGV EXIT

# Setup this script such that if any command exits with a
# non-zero value, the script itself exits and does not
# attempt any further processing (-e). Also, treat unset
# variables as an error when substituting (-u). Finally, export all
# variables and functions (-a). -a used because of parallel.
set -eua

# In case it is a slurm job
if [ ! -z ${SLURM_SUBMIT_DIR:-} ] ; then
    SERVERDIR=$SLURM_SUBMIT_DIR
    SERVER_APPDIR=$(dirname $SERVERDIR)
    UTILS=$SERVER_APPDIR/lib
fi

# This function gets called by opts_ParseArguments when --help is specified
usage()
{
    echo "
$log_ToolName: API script for running freesurfer on Slurm managed computing clusters

Usage: $log_ToolName

                Freesurfer Options
                    --subjects=<path or list>
                    --studydir=<study directory>                   Default: None
                    --subjectsdir=<subjects directory>             Default: None
                    [--input=<path to DICOM or NIFTI>]             Default: None
                    [--directives=<freesurfer directives list>]    Default: -autorecon-all
                    [--expert_opts=<freesurfer xopts list>]        Default: None
                    [--expert_opts_file=<freesurfer xopts file>]   Default: None
                    [--T2=<path to DICOM or NIFTI>]                Default: None
                    [--FLAIR=<path to DICOM or NIFTI>]             Default: None

                Miscellaneous Options
                    [--job_name=<name for job allocation>]         Default: GPN
                    [--location=<name of the HCP>]                 Default: psc_bridges2
                    [--job_slots=<max number of active jobs>]      Default: Unlimited
                    [--output=<name of output file>]               Default: <APP_LOGDIR>/*.out
                    [--error=<name of error file>]                 Default: <APP_LOGDIR>/*.err
                    [--timestamp=<job execution timestamp>]        Default: current date time
                    [--print=<print command>]                      Default: None

        PARAMETERs are [ ] = optional; < > = user supplied value

        Slurm values default to running FreeSurfer at PSC Bridges-2.
    "
    # automatic argument descriptions
    opts_ShowArguments

}

# ##############################################################################
#                                   CODE START
# ##############################################################################
input_parser()
{
    # Load input parser functions
    #SRC="$(dirname $(readlink -f ${BASH_SOURCE[0]:-$0}))"
    #APPDIR=$(dirname $SRC)
    #UTILS=$APPDIR/lib

    set -a
    . ${UTILS}/log.shlib       # Logging related functions
    . ${UTILS}/opts.shlib "$@" # Command line option functions

    # Freesurfer Options
    opts_AddMandatory '--subjects' 'subjects' 'path to file with subject IDs or space-delimited list of subject IDs (identification strings) upon which to operate' "a required argument; path to a file with the IDs (identification strings) of the subjects to be processed (e.g. /data/ADNI/subjid_list.txt) or a space-delimited list of subject IDs (e.g., 'bert berta') upon which to operate. If subject directory doesn't exist in SUBJECTDIR, creates analysis directory SUBJECTSDIR/<SUBJECT_ID> and converts one or more input volumes to MGZ format in SUBJECTDIR/<SUBJECT_ID>/mri/orig" "--s" "--sid" "--subjid"  "--subject" "--subjects_list" "--subjid_list"
    opts_AddMandatory '--studydir' 'studydir' 'specify study directory' "a required argument; is the path to the study directory (e.g. /data/ADNI)." "--ds"
    opts_AddMandatory '--subjectsdir' 'subjectsdir' 'specify subjects directory' "a required argument; is the path to the subjects directory (e.g. /data/ADNI)." "--sd"
    opts_AddOptional  '--input' 'input' 'path relative to <subjectsdir>/<SUBJID> to single DICOM file from a T1 MRI series or a single NIFTI file from a series' "an optional argument; <subjectsdir>/<SUBJID> single DICOM file from a T1 MRI series or a single NIFTI file from a series. If no input volumes are given, then it is assumed that the subject directory has already been created and that the data already exists in MGZ format in <subjectsdir>/<SUBJID>/mri/orig as XXX.mgz where XXX is a 3-digit, zero-padded number.Default: None." "" "--i"
    opts_AddOptional  '--T2' 'T2' 'path relative to <DATASETDIR>/<SUBJID> to single DICOM file from a T2 MRI series or a single NIFTI file from a T2 series' "an optional argument; path relative to <DATASETDIR>/<SUBJID> to single DICOM file from a T2 MRI series or a single NIFTI file from a T2 series. If no T2 volumes are given and both t2_dirname and t2_filename are None, then it is assumed that no T2 volume is available. If t2_dirname is supplied, T2 is assumed to be <DATASETDIR>/<SUBJID>/t2_dirname/t2w.nii.gz. If t2_filename is supplied, then T2 is assumed to be <DATASETDIR>/<SUBJID>/<t2_filename>. If both <t2_dirname> and <t2_filename> are supplied, then T2 is assumed to be <DATASETDIR>/<SUBJID>/<t2_dirname>/<t2_filename>. Default: None." "" "--t2"
    opts_AddOptional  '--FLAIR' 'FLAIR' 'path relative to <DATASETDIR>/<SUBJID> to single DICOM file from a FLAIR MRI series or a single NIFTI file from a FLAIR series' "an optional argument; path relative to <DATASETDIR>/<SUBJID> to single DICOM file from a FLAIR MRI series or a single NIFTI file from a FLAIR series. If no FLAIR volume is given and both flair_dirname and flair_filename are None, then it is assumed no FLAIR volume is available. If input_dirname is supplied, FLAIR is assumed to be <DATASETDIR>/<SUBJID>/flair_dirname/flair.nii.gz. If flair_filename is supplied, then FLAIR is assumed to be <DATASETDIR>/<SUBJID>/<flair_filename>. If both <flair_dirname> and <flair_filename> are supplied, then FLAIR is assumed to be <DATASETDIR>/<SUBJID>/<flair_dirname>/<flair_filename>. Default: None." "" "--flair"
    opts_AddOptional '--directives' 'directives' 'space-delimited list of freesurfer directives' 'an optional argument; space-delimited list of freesurfer directives to instruct recon-all which part(s) of the reconstruction stream to run (e.g., "-autorecon-all -notalairach"). Default: -autorecon-all.' "-autorecon-all"
    opts_AddOptional '--expert_opts' 'expert_opts' 'space-delimited list of freesurfer expert options' 'an optional argument; space-delimited list of freesurfer expert options (e.g., "-normmaxgrad maxgrad"; passes "-g maxgrad to mri_normalize"). The expert preferences flags supported by recon-all to be passed to a freesurfer binary. Default: None.' ""
    opts_AddOptional '--expert_opts_file' 'expert_opts_file' 'path to file containing special options to include in the command string' 'an optional argument; path to file containing special options to include in the command string (in addition to, not in place of the expert options flags already set). The file should contain as the first item the name of the command, and the items following it on rest of the line will be passed as the extra options (e.g., "mri_em_register -p .5"). Default: None.' "" "--expert"

    # Miscellaneous Options
    opts_AddOptional '--job_name' 'job_name' 'name for job allocation' "an optional argument; specify a name for the job allocation. Default: GPN (RFLab)" "GPN"
    opts_AddOptional  '--location' 'location' 'name of the HCP' "an optional argument; is the name of the High Performance Computing (HCP) cluster. Default: bridges2. Supported: psc_bridges2 | pitt_crc | rflab_workstation | rflab_cluster | gpn_paradox" "psc_bridges2"
    opts_AddOptional  '--job_slots' 'job_slots' 'max number of active jobs' "an optional argument; The maximum number of jobs active at once  Default: unlimited" ""
    opts_AddOptional  '--output' 'output' 'Name of output file' "an optional argument; the name of the output file. Default: ./log/app-freesurfer/<timestamp>_<job_name>_-_<SUBJID>.out" ""
    opts_AddOptional  '--error' 'error' 'Name of error file' "an optional argument; the name of the error file. Default: ./log/app-freesurfer/<timestamp>_<job_name>_-_<SUBJID>.err" ""
    opts_AddOptional  '--timestamp' 'timestamp' 'date and time job execution started' "an optional argument; the date and time the job execution started (YYYYMMDDHHMMSSZ). Default: current date time" "$(date -u +%Y%m%d%H%M%S%Z)"
    opts_AddOptional  '--print' 'print' 'Perform a dry run' "an optional argument; If print is not a null or empty string variable, then this script and other scripts that it calls will simply print out the commands and with options it otherwise would run. This printing will be done using the command specified in the print variable, e.g., echo" ""

    opts_ParseArguments "$@"
    set +a

    subjects="${subjects//,/ }"
}

# --------------------------------------------------------------
# Setup Functions
# --------------------------------------------------------------
setup()
{
    set -a
    . ${UTILS}/log.shlib       # Logging related functions
    set +a

    log_Msg "# START: setup"

    # Setup this script such that if any command exits with a
    # non-zero value, the script itself exits and does not
    # attempt any further processing. Also, treat unset
    # variables as an error when substituting.

    # Display the parsed/default values
    opts_ShowValues

    log_Msg "location: $location"
    case "$location" in
        psc_bridges2 ) setup_slurm ;;
        pitt_crc ) setup_slurm ;;
        rflab_cluster_old ) setup_slurm ;;
        rflab_cluster_new ) setup_slurm ;;
        rflab_cluster ) setup_slurm ;;
        rflab_workstation ) setup_slurm ;;
        gpn_paradox ) SUBJID=$1 ; output=$2 ; error=$3; setup_parallel $SUBJID ;;
        no_slurm_parallel ) SUBJID=$1 ; output=$2 ; error=$3; setup_parallel $SUBJID ;;
        no_slurm_serial ) SUBJID=$1 ; setup_serial $SUBJID ;;
    esac

    log_Msg "# END: setup"
}

setup_slurm()
{
    log_Msg "## START: setup_slurm"

    # The hostname from which sbatch was invoked (e.g. brXXX.ib.bridges2.psc.edu)
    SERVER=$SLURM_SUBMIT_HOST

    # The name of the node running the job script (e.g. rXXX)
    NODE=$SLURMD_NODENAME

    # SLURM_SUBMIT_DIR is the directory from which the script was invoked
    # (e.g. /ocean/projects/med200002p/shared/app-freesurfer/src)
    # (e.g. /bgfs/tibrahim/edd32/proj/app-freesurfer/src)
    # SERVER_APPDIR is the parent directory from which the script was invoked
    # (e.g. /ocean/projects/med200002p/shared/app-freesurfer)
    # (e.g. /bgfs/tibrahim/edd32/proj/app-freesurfer)
    SERVER_APPDIR="$(dirname $SLURM_SUBMIT_DIR)"

    # Looks in the list of IDs and get the correspoding subject ID for this job
    subjects_array=($subjects)

    #SUBJID="$(head -n $SLURM_ARRAY_TASK_ID "$subjects" | tail -n 1)"
    SUBJID="${subjects_array[$(($SLURM_ARRAY_TASK_ID-1))]}"

    # replace %a with task ID
    output=$(echo "${output/\%a/$SLURM_ARRAY_TASK_ID}")
    error=$(echo "${error/\%a/$SLURM_ARRAY_TASK_ID}")

    case "$location" in
        psc_bridges2 ) setup_bridges2 ;;
        pitt_crc ) setup_crc ;;
        rflab_cluster ) setup_rflab ;;
        rflab_workstation ) setup_rflab ;;
    esac

    echo "----------------------------------------------------------"
    echo "Report major SLURM control variables:"
    echo "----------------------------------------------------------"
    NNODE=$(scontrol show hostnames $SLURM_JOB_NODELIST | wc -l)
    NCPU=$(echo ${SLURM_CPUS_ON_NODE[@]} | tr , + | bc)
    log_Msg "Job name is $SLURM_JOB_NAME"
    log_Msg "This job is allocated on $NNODE node(s)"
    log_Msg "This job is allocated on $NCPU cpu(s)"
    log_Msg "sbatch is running on $SERVER"
    log_Msg "Server calling directory is $SERVER_APPDIR"
    log_Msg "Node is $NODE"
    log_Msg "Node working directory is $NODEDIR"
    log_Msg "Master job identifier of the job array is $SLURM_ARRAY_JOB_ID"
    log_Msg "Job array index identifier is $SLURM_ARRAY_TASK_ID"
    log_Msg "Job identifier, master job ID plus job array index, is $SLURM_JOB_ID"

    echo "----------------------------------------------------------"
    echo "Report major script control variables:"
    echo "----------------------------------------------------------"
	log_Msg "Subject ID: $SUBJID"
	log_Msg "Subject directory: $NODE_SUBJECTDIR"
	log_Msg "APP directory: $NODE_APPDIR"
	log_Msg "environment Script: $NODE_APPDIR/src/SETUP_fs.sh"
	log_Msg "Log directory: $NODE_LOGDIR"
	log_Msg "print: $print"

    log_Msg "## END: setup_slurm"
}

# All variable definitions starting with SLURM_* are surrogate for
# conventional slurm environment variables. We do this so the other
# functions (e.g., main, clean) can be called without adaptation.
setup_parallel()
{
    log_Msg "## START: setup_parallel"

    echo "----------------------------------------------------------"
    echo "Platform Information Follows: "
    echo "----------------------------------------------------------"
    uname -a

    SUBJID=$1

    # The hostname from which sbatch was invoked (e.g. acct.upmchs.net)
    SERVER=$HOSTNAME

    # The name of the node running the job script (e.g. dinize@acct.upmchs.net)
    NODE=$USER

    SLURM_JOB_NAME=$job_name

    # Use the process ID for the shell as surrogate
    SLURM_ARRAY_JOB_ID=$$
    # SLURM_SUBMIT_DIR is the directory from which the script was invoked
    # (e.g. /home/dinize@acct.upmchs.net/proj/app-freesurfer/src)
    # SERVER_APPDIR is the parent directory from which the script was invoked
    # (e.g. /home/dinize@acct.upmchs.net/proj/app-freesurfer)
    SLURM_SUBMIT_DIR="$APPDIR/src"
    SERVER_APPDIR="$(dirname $SLURM_SUBMIT_DIR)"

    # ----------------------------------------------------------
    #  Load Function Libraries
    # ----------------------------------------------------------
    SRC=$SERVER_APPDIR/src
    FREESURFER=$SERVER_APPDIR/bin/freesurfer
    UTILS=$SERVER_APPDIR/lib

    if [[ ! -L $FREESURFER ]] || [[ ! -e $FREESURFER ]] ; then
        unset FREESURFER
    fi

    echo "----------------------------------------------------------"
    echo "Verify required environment variables are set:"
    echo "----------------------------------------------------------"
    SSH=$(which ssh)
    RSYNC=$(which rsync)
    PARALLEL=$(which parallel)
    SINGULARITY=$(which singularity)

    log_Check_Env_Var SRC
    log_Check_Env_Var UTILS
    log_Check_Env_Var RSYNC
    log_Check_Env_Var PARALLEL
    log_Check_Env_Var SINGULARITY
    log_Check_Env_Var FREESURFER

    echo "----------------------------------------------------------"
    echo "Copy subject data to temporary folder"
    echo "----------------------------------------------------------"
    LOCAL=/tmp
    # Node directory that where computation will take place
    NODEDIR=$LOCAL/${SLURM_ARRAY_JOB_ID}_${SUBJID}
    log_Msg "mkdir -p $NODEDIR"
    mkdir -p $NODEDIR
    cd $NODEDIR

    echo "----------------------------------------------------------"
    echo "Transfer files from server '$SERVER' to node '$NODE'"
    echo "----------------------------------------------------------"
    # Copy FPP scripts from server to node, creating whatever directories required
    log_Msg "Copy app-freesurfer"
    rsync_local $SERVER_APPDIR $NODEDIR
    NODE_APPDIR=$NODEDIR/app-freesurfer

    # Copy subject data from server to node, creating whatever directories required
    log_Msg "Copy subject data"
    SERVER_STUDYDIR=${studydir}
    SERVER_DATASETDIR=$subjectsdir
    SERVER_SUBJECTDIR="${SERVER_DATASETDIR}/${SUBJID}"

    # if input is not empty, then it's the first time freesurfer is run, copy
    # subjid folder contents
    NODE_SUBJECTDIR=$NODEDIR/subject && mkdir -p $NODE_SUBJECTDIR
    if [ ! -z $input ] ; then
        rsync_local $SERVER_SUBJECTDIR/ $NODE_SUBJECTDIR
    # else input is empty, then it's a re-run, copy subjid folder
    else
        rsync_local $SERVER_SUBJECTDIR $NODE_SUBJECTDIR
    fi

    # Log paths
    SERVER_LOGDIR="$SERVER_APPDIR/jobs/${job_name}/${timestamp}/log"
    NODE_LOGDIR=$NODE_APPDIR/log/${job_name}/${timestamp}

    log_Msg "SERVER_LOGDIR:\n$SERVER_LOGDIR"
    log_Msg "NODE_LOGDIR:\n$NODE_LOGDIR"

    mkdir -p $SERVER_LOGDIR
    mkdir -p $NODE_LOGDIR


    log_Msg "## END: setup_parallel"
}

setup_bridges2()
{
    log_Msg "## START: setup_bridges2"

    echo "----------------------------------------------------------"
    echo "Platform Information Follows: "
    echo "----------------------------------------------------------"
    uname -a

    module purge # Make sure the modules environment is sane

    echo "----------------------------------------------------------"
    echo "Set environment variables for required software:"
    echo "----------------------------------------------------------"
    FREESURFER=$SERVER_APPDIR/bin/gpntk

    if [[ ! -L $FREESURFER ]] || [[ ! -e $FREESURFER ]] ; then
        unset FREESURFER
    fi

    SSH=$(which ssh)
    RSYNC=$(which rsync)
    SINGULARITY=$(which singularity)

    log_Check_Env_Var SSH
    log_Check_Env_Var RSYNC
    log_Check_Env_Var SINGULARITY
    log_Check_Env_Var FREESURFER

    echo "----------------------------------------------------------"
    echo "Copy subject data to temporary folder"
    echo "----------------------------------------------------------"
    # Node directory that where computation will take place
    NODEDIR=$LOCAL/${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}
    log_Msg "mkdir -p $NODEDIR"
    mkdir -p $NODEDIR
    cd $NODEDIR

    echo "----------------------------------------------------------"
    echo "Transfer files from server '$SERVER' to node '$NODE'"
    echo "----------------------------------------------------------"
    # Copy FPP scripts from server to node, creating whatever directories required
    log_Msg "Copy app-freesurfer"
    #rsync_to_bridges2 $SERVER_APPDIR $NODEDIR
    rsync_local $SERVER_APPDIR $NODEDIR
    NODE_APPDIR=$NODEDIR/app-freesurfer

    # Copy subject data from server to node, creating whatever directories required
    log_Msg "Copy subject data"
    SERVER_STUDYDIR=${studydir}
    SERVER_DATASETDIR=$subjectsdir
    SERVER_SUBJECTDIR="${SERVER_DATASETDIR}/${SUBJID}"

    # if input is not empty, then it's the first time freesurfer is run, copy
    # subjid folder contents
    NODE_SUBJECTDIR=$NODEDIR/subject && mkdir -p $NODE_SUBJECTDIR
    if [ ! -z $input ] ; then
        #rsync_to_bridges2 $SERVER_SUBJECTDIR/ $NODE_SUBJECTDIR
        rsync_local $SERVER_SUBJECTDIR/ $NODE_SUBJECTDIR
    # else input is empty, then it's a re-run, copy subjid folder
    else
        #rsync_to_bridges2 $SERVER_SUBJECTDIR $NODE_SUBJECTDIR
        rsync_local $SERVER_SUBJECTDIR $NODE_SUBJECTDIR
    fi

    # Log paths
    SERVER_LOGDIR="$SERVER_APPDIR/jobs/${job_name}/${timestamp}/log"
    NODE_LOGDIR=$NODE_APPDIR/log/${job_name}/${timestamp}

    log_Msg "SERVER_LOGDIR:\n$SERVER_LOGDIR"
    log_Msg "NODE_LOGDIR:\n$NODE_LOGDIR"

    mkdir -p $SERVER_LOGDIR
    mkdir -p $NODE_LOGDIR

    log_Msg "## END: setup_bridges2"
}

rsync_local()
{
    log_Msg "### START: rsync_local"

    source_directory=$1
    target_directory=$2

    # Create necessary directories on the remote host
    log_Msg "mkdir -p '${target_directory}'"
    mkdir -p "${target_directory}"

    # Transfer files
    _rsync "$source_directory" $target_directory

    log_Msg "### END: rsync_local"
}

rsync_to_bridges2()
{
    log_Msg "### START: rsync_to_bridges2"

    source_directory=$1
    target_directory=$2

    remote_name="${USER}@data.bridges2.psc.edu"

    # Create, if necessary, directories on the remote host
    log_Msg "ssh $USER@bridges2.psc.edu 'mkdir -p '${target_directory}''"
    ssh -o BatchMode=yes "$USER@bridges2.psc.edu" "mkdir -p "${target_directory}""

    # Transfer files
    _rsync $source_directory "$remote_name:$target_directory"

    log_Msg "### END: rsync_to_bridges2"
}

rsync_from_bridges2()
{
    log_Msg "### START: rsync_from_bridges2"

    source_directory=$1
    target_directory=$2
    remote_name="${USER}@data.bridges2.psc.edu"

    # Create necessary directories on the remote host
    log_Msg "mkdir -p ${target_directory}"
    mkdir -p "${target_directory}"

    # Transfer files
    _rsync "${remote_name}:${source_directory}" $target_directory

    log_Msg "### END: rsync_from_bridges2"
}

rsync_to_rflab()
{
    log_Msg "### START: rsync_to_rflab"

    source_directory=$1
    target_directory=$2 # e.g., node07:target_directory

    remote_name=$NODE

    # Create necessary directories on the node
    log_Msg "ssh $remote_name "mkdir -p "${target_directory}"""
    ssh $remote_name "mkdir -p "${target_directory}""

    # Transfer files
    _rsync $source_directory "${remote_name}:${target_directory}"

    log_Msg "### END: rsync_to_rflab"
}

rsync_from_rflab()
{
    log_Msg "### START: rsync_from_rflab"

    source_directory=$1 # e.g., node07:source_directory
    target_directory=$2
    remote_name=$NODE

    # Create necessary directories on the server
    log_Msg "mkdir -p "${target_directory}""
    mkdir -p "${target_directory}"

    # Transfer files
    _rsync "$remote_name:$source_directory" $target_directory

    log_Msg "### END: rsync_from_rflab"
}

# --------------------------------------------------------------
# rsync command
# --------------------------------------------------------------
_rsync()
{
    source_directory=$1
    target_directory=$2 # e.g., data.bridges2.psc.edu:target_directory

    local RC=1
    local n=0
    local nattempts=20

    # --------------------------------------------------------------
    # Log rsync
    # --------------------------------------------------------------
    log_Msg "rsync command:
    $RSYNC -rlpDPq
     --exclude '*.sif'
     --exclude '*.git/'
     -e 'ssh -q -o BatchMode=yes'
     $source_directory $target_directory"

    # Put rsync command in a loop to insure that it completes; try 20 times
    while [ $RC -ne 0 ] && [ $n -lt $nattempts ] ; do
        # --exclude '*.sif' prevents freesurfer image from being transfered
        # -oMACS=umac-65@openssh.com will use a faster data validation algorithm
        $RSYNC -rlpDPq \
            --exclude '*.sif' \
            --exclude '*.git/' \
            -e 'ssh -q -o BatchMode=yes' $source_directory $target_directory

        RC=$?
        let n=n+1
        echo $n
        sleep 10

    done

    unset RC
    unset n
    unset nattempts
}

main()
{
    log_Msg "# START: main"

    echo "----------------------------------------------------------"
    echo "Creating app-freesurfer command"
    echo "----------------------------------------------------------"
    CONTAINER_APPDIR="/app-freesurfer"
    CONTAINER_SUBJECTDIR="/subject"
    CONTAINER_LOGDIR="/log"
    CONTAINER_SUBJID="${SUBJID}"
    if [ ! -z $expert_opts_file ] ; then
        CONTAINER_XOPTS_FILE="$CONTAINER_APPDIR/jobs/${job_name}/${timestamp}/etc/expert_-_${job_name}_-_${timestamp}.opts"
    else
        CONTAINER_XOPTS_FILE=""
    fi

    if [ ! -z $input ] ; then
        CONTAINER_INPUT=$CONTAINER_SUBJECTDIR/$input
    else
        CONTAINER_INPUT=""
        if [ ! -z $expert_opts_file ] ; then
            PRE_XOPTS_FILE="$NODE_SUBJECTDIR/${SUBJID}/scripts/expert-options"
            NEW_XOPTS_FILE="$NODE_APPDIR/jobs/${job_name}/${timestamp}/etc/expert_-_${job_name}_-_${timestamp}.opts"
            # if there is a pre-existing expert options file and an expert options
            # file was specified on the command-line, append the contents of the
            # pre-existing file with the newly specified one and set -xopts-overwrite
            if [ -f $PRE_XOPTS_FILE ] ; then
                cat $PRE_XOPTS_FILE $NEW_XOPTS_FILE > tmp
                # Remove repeated lines from expert options file
                sort -u tmp -o $NEW_XOPTS_FILE
                rm -f tmp
                directives+=" -xopts-overwrite"
            fi
        else
            CONTAINER_XOPTS_FILE=""
        fi
    fi

    if [ ! -z $T2 ] ; then
        CONTAINER_T2=$CONTAINER_SUBJECTDIR/$T2
    else
        CONTAINER_T2=""
    fi

    if [ ! -z $FLAIR ] ; then
        CONTAINER_FLAIR=$CONTAINER_SUBJECTDIR/$FLAIR
    else
        CONTAINER_FLAIR=""
    fi

    APP_LICENSE="$NODE_APPDIR/etc/license.txt"
    # We do not copy singularity image over to nodes
    # Technically, we don't need to setup SIF_PATH, it's already done
    # at app.conf, but this allow to set a image that is not
    # located at the expected path.
    SIF_PATH="$SERVER_APPDIR/libexec/gpntk.sif"

    singularity_cmd="$FREESURFER"
    singularity_cmd+=" -L $APP_LICENSE"
    singularity_cmd+=" -B $NODE_APPDIR:$CONTAINER_APPDIR"
    singularity_cmd+=" -B $NODE_SUBJECTDIR:$CONTAINER_SUBJECTDIR"
    singularity_cmd+=" -S $SIF_PATH"
    singularity_cmd+=" bash"
    echo "----------------------------------------------------------"
    echo "Singularity command"
    echo "----------------------------------------------------------"
    echo "${singularity_cmd}"

    echo "----------------------------------------------------------"
    echo "APP_fs.sh script call, Runing inside container"
    echo "----------------------------------------------------------"
    echo "$CONTAINER_APPDIR/src/APP_fs.sh
  --subjid=$CONTAINER_SUBJID
  --sd=$CONTAINER_SUBJECTDIR
  --i=$CONTAINER_INPUT
  --T2=$CONTAINER_T2
  --FLAIR=$CONTAINER_FLAIR
  --directives=$directives
  --expert_opts=$expert_opts
  --expert_opts_file=$CONTAINER_XOPTS_FILE
  --print=${print}
  1> $NODE_LOGDIR/APP_-_$SUBJID.out
  2> $NODE_LOGDIR/APP_-_$SUBJID.err"

    #replace spaces with commas in space separated options
    #this is replaced back to spaces in APP_fs.sh
    ${singularity_cmd} \
    $CONTAINER_APPDIR/src/APP_fs.sh \
    --subjid="${CONTAINER_SUBJID}" \
    --sd="${CONTAINER_SUBJECTDIR}" \
    --i="$CONTAINER_INPUT" \
    --T2="${CONTAINER_T2}" \
    --FLAIR="${CONTAINER_FLAIR}" \
    --directives="${directives// /,}" \
    --expert_opts="${expert_opts// /,}" \
    --expert_opts_file="${CONTAINER_XOPTS_FILE}" \
    --print="${print// /,}" \
    1> "${NODE_LOGDIR}/APP_-_${SUBJID}.out" \
    2> "${NODE_LOGDIR}/APP_-_${SUBJID}.err"

    log_Msg "# END: main"
}

clean()
{
    log_Msg "# START: clean"

    echo "----------------------------------------------------------"
    echo "Transfer files from node '$NODE' to server '$SERVER':"
    echo "----------------------------------------------------------"

    log_Msg "Copy freesurfer data from node"
    case "$location" in
        #psc_bridges2 ) rsync_cmd=rsync_from_bridges2 ;;
        psc_bridges2 ) rsync_cmd=rsync_local ;;
        pitt_crc ) rsync_cmd=rsync_from_crc ;;
        rflab_cluster_old ) rsync_cmd=rsync_from_cluster ;;
        rflab_cluster_new ) rsync_cmd=rsync_from_cluster ;;
        rflab_cluster ) rsync_cmd=rsync_from_cluster ;;
        rflab_workstation ) rsync_cmd=rsync_from_workstation ;;
        gpn_paradox ) rsync_cmd=rsync_local ;;
        no_slurm_parallel ) rsync_cmd=rsync_local ;;
        no_slurm_serial ) rsync_cmd=rsync_local ;;
    esac

    SERVER_STUDY_LOGDIR="${SERVER_STUDYDIR}/metadata/app-freesurfer/jobs/${job_name}/${timestamp}/log"
    SERVER_SUBJID_JOBDIR="$SERVER_STUDYDIR/processed/app-freesurfer/jobs/${job_name}/${timestamp}/${SUBJID}"
    log_Msg "Move subject data to permanent processed data directory:\n$SERVER_SUBJID_JOBDIR"
    log_Msg "mkdir -p $SERVER_SUBJID_JOBDIR"
    mkdir -p $SERVER_SUBJID_JOBDIR

    log_Msg "Copy subject processed data from node"
    ${rsync_cmd} "${NODE_SUBJECTDIR}/${SUBJID}/" "$SERVER_SUBJID_JOBDIR/"

    # APP_fs.sh log files
    log_Msg "Move APP_fs.sh logs: SERVER_DATASET_LOGDIR/APP_-_<subjid>.*"
    ${rsync_cmd} ${NODE_LOGDIR}/ $SERVER_STUDY_LOGDIR

    # BATCH_fs.sh log files
    log_Msg "Move BATCH_fs.sh logs: STUDY_LOGDIR/BATCH_-_<subjid>.*"
    if [[ -f $output ]] ; then
        mv $output "$SERVER_STUDY_LOGDIR/BATCH_-_${SUBJID}.out"
    fi
    if [[ -f $error ]] ; then
        mv $error "$SERVER_STUDY_LOGDIR/BATCH_-_${SUBJID}.err"
    fi

    echo "-------------------------------------------------------------------"
    echo "Files transfered to server, clean temporary directory and log files"
    echo "-------------------------------------------------------------------"
    #rm -rf ${NODEDIR}

    log_Msg "# END: clean"

    #echo "----------------------------------------------------------"
    #echo "Job Statistics"
    #echo "----------------------------------------------------------"
    #crc-job-stats.py # gives stats of job, wall time, etc.
}

halt()
{
   exit_code=$?
   if [ $exit_code -ne 0 ]; then
       echo "###################################################"
       echo "################ HALT: APP_fs.sh ##################"
       echo "###################################################"

       clean
   fi
}

run_main()
{
    echo "#####################################################"
    echo "################ START: BATCH_fs.sh #################"
    echo "#####################################################"

    case "$location" in
        psc_bridges2 ) setup ; main ; clean ;;
        pitt_crc ) setup ; main ; clean ;;
        rflab_cluster_old ) setup ; main ; clean ;;
        rflab_cluster_new ) setup ; main ; clean ;;
        rflab_cluster ) setup ; main ; clean ;;
        rflab_workstation ) setup ; main ; clean ;;
        gpn_paradox ) setup $@ ; main ; clean;;
        no_slurm_parallel ) setup $@ ; main ; clean ;;
        no_slurm_serial ) setup $@ ; main ; clean ;;
    esac

    echo "###################################################"
    echo "################ END: BATCH_fs.sh #################"
    echo "###################################################"
}

run_main_with_parallel()
{
    PARALLEL=$(which parallel)

    input_array=()

    # Create log files
    for SUBJID in ${subjects[@]} ; do
        stdout_file=$(echo "${output/subjid/$SUBJID}")
        stderr_file=$(echo "${error/subjid/$SUBJID}")
        input_array+=("$SUBJID")
        input_array+=("$stdout_file")
        input_array+=("$stderr_file")
    done

    # -k keeps output in order
    # -N3 reads three stdin arguments at a time
    # -j$job_slots will run $job_slots jobs in parallel at once
    printf '%s\n' "${input_array[@]}" \
        | $PARALLEL -k -N3 -j$((job_slots+0)) \
        'run_main {1} {2} {3} 1> {2} 2> {3}'
}

run_main_serial()
{
    # Need temporary variables since $output and $error change dynamically
    local output_tmp=$output
    local error_tmp=$error

    for SUBJID in ${subjects[@]} ; do
        stdout_file=$(echo "${output_tmp/subjid/$SUBJID}")
        stderr_file=$(echo "${error_tmp/subjid/$SUBJID}")
        run_main $SUBJID $stdout_file $stderr_file 1> $stdout_file 2> $stderr_file
    done

    unset output_tmp
    unset error_tmp
}

# ##############################################################################
#                               EXECUTION START
# ##############################################################################
input_parser "$@"

if [ -z $output ] || [ -z $error ] ; then
    output="./log/app-freesurfer/${job_name}/${timestamp}/BATCH_-_subjid.out"
    error="./log/app-freesurfer/${job_name}/${timestamp}/BATCH_-_subjid.err"
fi

case "$location" in
    psc_bridges2 ) run_main ;;
    pitt_crc ) run_main ;;
    rflab_cluster_old ) run_main ;;
    rflab_cluster_new ) run_main ;;
    rflab_cluster ) run_main ;;
    rflab_workstation ) run_main ;;
    gpn_paradox ) run_main_with_parallel ;;
    no_slurm_parallel ) run_main_with_parallel ;;
    no_slurm_serial ) run_main_serial ;;
esac

# happy end
exit 0

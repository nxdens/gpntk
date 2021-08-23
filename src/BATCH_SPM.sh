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
$log_ToolName: API script for running SPM on Slurm managed computing clusters

Usage: $log_ToolName

                SPM Options
                    --subjects=<path or list>
                    --studydir=<study directory>                   Default: None
                    --subjectsdir=<subjects directory>             Default: None
                    [--batchdir=<batch directory>]                 Default: None
                    [--batchfile=<path to batch file>]             Default: None
                    [--pipeline_steps=<list of pipeline steps>]    Default: None

                Miscellaneous Options
                    [--job_name=<name for job allocation>]         Default: GPN
                    [--location=<name of the HCP>]                 Default: psc_bridges2
                    [--job_slots=<max number of active jobs>]      Default: Unlimited
                    [--output=<name of output file>]               Default: <APP_LOGDIR>/*.out
                    [--error=<name of error file>]                 Default: <APP_LOGDIR>/*.err
                    [--timestamp=<job execution timestamp>]        Default: current date time
                    [--print=<print command>]                      Default: None

        PARAMETERs are [ ] = optional; < > = user supplied value

        Slurm values default to running SPM at PSC Bridges-2.
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

    # SPM Options
    opts_AddMandatory '--subjects' 'subjects' 'path to file with subject IDs or space-delimited list of subject IDs (identification strings) upon which to operate' "a required argument; path to a file with the IDs (identification strings) of the subjects to be processed (e.g. /data/ADNI/subjid_list.txt) or a space-delimited list of subject IDs (e.g., 'bert berta') upon which to operate. If subject directory doesn't exist in SUBJECTDIR, creates analysis directory SUBJECTSDIR/<SUBJECT_ID> and converts one or more input volumes to MGZ format in SUBJECTDIR/<SUBJECT_ID>/mri/orig" "--s" "--sid" "--subjid"  "--subject" "--subjects_list" "--subjid_list"
    opts_AddMandatory '--studydir' 'studydir' 'specify study directory' "a required argument; is the path to the study directory (e.g. /data/ADNI)." "--ds"
    opts_AddMandatory '--subjectsdir' 'subjectsdir' 'specify subjects directory' "a required argument; is the path to the subjects directory (e.g. /data/ADNI)." "--sd"
    opts_AddOptional  '--batchdir' 'batchdir' 'set directory for matlab batches for SPM' "an optional argument: directory where the .mat matlab batches are stored or generated. If using script to generate them please pass the script to the --batchfile arguement. Default: None" "" "--bd"
    opts_AddOptional  '--step_names' 'step_names' 'Space seperated string with the names of all the folders that will be used for processing' "an optional arguement; Required for batch creation. Default: none" "" ""
    
    # Miscellaneous Options
    opts_AddOptional '--job_name' 'job_name' 'name for job allocation' "an optional argument; specify a name for the job allocation. Default: GPN (RFLab)" "GPN"
    opts_AddOptional  '--location' 'location' 'name of the HCP' "an optional argument; is the name of the High Performance Computing (HCP) cluster. Default: bridges2. Supported: psc_bridges2 | pitt_crc | rflab_workstation | rflab_cluster | gpn_paradox" "psc_bridges2"
    opts_AddOptional  '--job_slots' 'job_slots' 'max number of active jobs' "an optional argument; The maximum number of jobs active at once  Default: unlimited" ""
    opts_AddOptional  '--output' 'output' 'Name of output file' "an optional argument; the name of the output file. Default: ./log/gpntk/<timestamp>_<job_name>_-_<SUBJID>.out" ""
    opts_AddOptional  '--error' 'error' 'Name of error file' "an optional argument; the name of the error file. Default: ./log/gpntk/<timestamp>_<job_name>_-_<SUBJID>.err" ""
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
    # (e.g. /ocean/projects/med200002p/shared/gpntk/src)
    # (e.g. /bgfs/tibrahim/edd32/proj/gpntk/src)
    # SERVER_APPDIR is the parent directory from which the script was invoked
    # (e.g. /ocean/projects/med200002p/shared/gpntk)
    # (e.g. /bgfs/tibrahim/edd32/proj/gpntk)
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
	log_Msg "environment Script: $NODE_APPDIR/src/SETUP_SPM.sh"
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
    # (e.g. /home/dinize@acct.upmchs.net/proj/gpntk/src)
    # SERVER_APPDIR is the parent directory from which the script was invoked
    # (e.g. /home/dinize@acct.upmchs.net/proj/gpntk)
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
    log_Msg "Copy gpntk"
    rsync_local $SERVER_APPDIR $NODEDIR
    NODE_APPDIR=$NODEDIR/gpntk

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
    SPM=$SERVER_APPDIR/bin/singularity-gpntk

    if [[ ! -L $SPM ]] || [[ ! -e $SPM ]] ; then
        unset SPM
    fi

    SSH=$(which ssh)
    RSYNC=$(which rsync)
    SINGULARITY=$(which singularity)

    log_Check_Env_Var SSH
    log_Check_Env_Var RSYNC
    log_Check_Env_Var SINGULARITY
    log_Check_Env_Var SPM

    #need to get rid of all the transfers since the batches aren't setup for that and also the gpn scripts aren't either
    #unfortunately gpn scripts do all subject batches at once for now 
    #not a huge deal since this is pretty fast

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
    log_Msg "Copy gpntk"
    #rsync_to_bridges2 $SERVER_APPDIR $NODEDIR
    rsync_local $SERVER_APPDIR $NODEDIR
    NODE_APPDIR=$NODEDIR/gpntk

    # Copy subject data from server to node, creating whatever directories required
    log_Msg "Copy subject data"
    SERVER_STUDYDIR=${studydir}
    SERVER_DATASETDIR=$subjectsdir
    SERVER_SUBJECTDIR="${SERVER_DATASETDIR}/${SUBJID}"

    # if input is not empty, then it's the first time spm is run, copy
    # subjid folder contents
    NODE_SUBJECTDIR=$NODEDIR/subject && mkdir -p $NODE_SUBJECTDIR
    rsync_local $SERVER_SUBJECTDIR/ $NODE_SUBJECTDIR

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
        # --exclude '*.sif' prevents spm image from being transfered
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
    echo "Creating gpntk command"
    echo "----------------------------------------------------------"
    CONTAINER_APPDIR="/gpntk"
    CONTAINER_SUBJECTDIR="/subject"
    CONTAINER_LOGDIR="/log"
    CONTAINER_SUBJID="${SUBJID}"

    APP_LICENSE="$NODE_APPDIR/etc/license.txt"
    # We do not copy singularity image over to nodes
    # Technically, we don't need to setup SIF_PATH, it's already done
    # at app.conf, but this allow to set a image that is not
    # located at the expected path.
    SIF_PATH="$SERVER_APPDIR/libexec/gpntk.sif"

    singularity_cmd="$SPM"
    #singularity_cmd+=" -L $APP_LICENSE"
    singularity_cmd+=" -B /ocean/projects/med200002p/liw82/"
    singularity_cmd+=" -B $NODE_APPDIR:$CONTAINER_APPDIR"
    singularity_cmd+=" -B $NODE_SUBJECTDIR:$CONTAINER_SUBJECTDIR"
    singularity_cmd+=" -S $SIF_PATH"
    singularity_cmd+=" bash"
    echo "----------------------------------------------------------"
    echo "Singularity command"
    echo "----------------------------------------------------------"
    echo "${singularity_cmd}"

    echo "----------------------------------------------------------"
    echo "APP_SPM.sh script call, Runing inside container"
    echo "----------------------------------------------------------"
    echo "$CONTAINER_APPDIR/src/APP_SPM.sh
  --subjid=$CONTAINER_SUBJID
  --sd=$CONTAINER_SUBJECTDIR
  --batchdir=${batchdir}
  --step_names="${step_names}" 
  --print=${print}"
  #1> $NODE_LOGDIR/APP_-_$SUBJID.out
  #2> $NODE_LOGDIR/APP_-_$SUBJID.err"

    #replace spaces with commas in space separated options
    #this is replaced back to spaces in APP_SPM.sh
    ${singularity_cmd} \
    $CONTAINER_APPDIR/src/APP_SPM.sh \
    --subjid="${CONTAINER_SUBJID}" \
    --sd="${CONTAINER_SUBJECTDIR}" \
    --batchdir="${batchdir}" \
    --step_names="${step_names}" \
    --print="${print// /,}" 
    #1> "${NODE_LOGDIR}/APP_-_${SUBJID}.out" \
    #2> "${NODE_LOGDIR}/APP_-_${SUBJID}.err"

    log_Msg "# END: main"
}

clean()
{
    log_Msg "# START: clean"

    echo "----------------------------------------------------------"
    echo "Transfer files from node '$NODE' to server '$SERVER':"
    echo "----------------------------------------------------------"

    log_Msg "Copy SPM data from node"
    case "$location" in
        psc_bridges2 ) rsync_cmd=rsync_from_bridges2 ;;
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

    SERVER_STUDY_LOGDIR="${SERVER_STUDYDIR}/metadata/gpntk/jobs/${job_name}/${timestamp}/log"
    SERVER_SUBJID_JOBDIR="$SERVER_STUDYDIR/processed/gpntk/jobs/${job_name}/${timestamp}/${SUBJID}"
    log_Msg "Move subject data to permanent processed data directory:\n$SERVER_SUBJID_JOBDIR"
    log_Msg "mkdir -p $SERVER_SUBJID_JOBDIR"
    mkdir -p $SERVER_SUBJID_JOBDIR

    log_Msg "Copy subject processed data from node"
    ${rsync_cmd} "${NODE_SUBJECTDIR}/${SUBJID}/" "$SERVER_SUBJID_JOBDIR/"

    # APP_SPM.sh log files
    log_Msg "Move APP_SPM.sh logs: SERVER_DATASET_LOGDIR/APP_-_<subjid>.*"
    ${rsync_cmd} ${NODE_LOGDIR}/ $SERVER_STUDY_LOGDIR

    # BATCH_SPM.sh log files
    log_Msg "Move BATCH_SPM.sh logs: STUDY_LOGDIR/BATCH_-_<subjid>.*"
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
       echo "################ HALT: APP_SPM.sh ##################"
       echo "###################################################"

       clean
   fi
}

run_main()
{
    echo "#####################################################"
    echo "################ START: BATCH_SPM.sh #################"
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
    echo "################ END: BATCH_SPM.sh #################"
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
    output="./log/gpntk/${job_name}/${timestamp}/BATCH_-_subjid.out"
    error="./log/gpntk/${job_name}/${timestamp}/BATCH_-_subjid.err"
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

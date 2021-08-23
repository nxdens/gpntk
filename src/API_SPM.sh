#!/bin/bash

trap 'halt' SIGINT SIGKILL SIGTERM SIGSEGV EXIT

# Setup this script such that if any command exits with a
# non-zero value, the script itself exits and does not
# attempt any further processing. Also, treat unset
# variables as an error when substituting.
set -eu
# Copy of API_GPNTK script specifically for spm on bridges 2
### v1
#TODO change to use SPM
#TODO Remove all cpus_per_task instances 
#TODO line 536 queuing command for batch
# ##############################################################################
#                                   CODE START
# ##############################################################################
# This function gets called by opts_ParseArguments when --help is specified
usage()
{
    echo "
$log_ToolName: API script for running SPM on Slurm managed computing clusters (use run_spm command)

Usage: $log_ToolName
                SLURM queuing options
                    --job_name=<name for job allocation>
                    [--location=<name of the HCP>]                       Default: psc_bridges2
                    [--partition=<request a specific partition>]         Default: RM
                    [--exclude=<node(s) to be excluded>]                 Default: None
                    [--mem_per_cpu=<real memory per CPU>]                Default: 1G
                    [--time=<limit on the total runtime]                 Default: 10 hours
                    [--export=<export environment variables>]            Default: ALL
                    [--mail_type=<type of mail>]                         Default: FAIL,END
                    [--mail_user=<user email>]                           Default: None
                    [--job_slots=<max number of active jobs>]            Default: Unlimited

                SPM Options
                    --subjects=<path or list>
                    --studydir=<study directory>                         Default: None
                    [--subjectsdir=<subjects directory>]                 Default: None
                    [--input_dirname=<path to append to subject dir]     Default: None
                    [--input_filename=<name of DICOM or NIFTI file>]     Default: None
                    [--input=<path to DICOM or NIFTI>]                   Default: None
                    [--batchdir=<batch directory>]                       Default: None
                    [--batchscript=<path to batch file>]                 Default: None
                    [--step_names=<list of steps>]                       Default: None
                    [--debug=<true or false>]                            Default: false

                Miscellaneous Options
                    [--print=<print command>]                            Default: None
                    [--clean_job=<clean all previous run of this job>]   Default: false
                    [--clean_instance=<clean specific run of this job>]  Default: None

        PARAMETERs are [ ] = optional; < > = user supplied value

        Slurm values default to running SPM at PSC Bridges-2.
    "
    # automatic argument descriptions
    opts_ShowArguments
}

input_parser()
{
    log_Msg "## START: input_parser"

    # SLURM Queuing Options
    opts_AddMandatory '--job_name' 'job_name' 'name for job allocation' "a required argument; specify a name for the job allocation."
    opts_AddOptional  '--location' 'location' 'name of the HCP' "an optional argument; is the name of the High Performance Computing (HCP) cluster. Default: bridges2. Supported: psc_bridges2 | pitt_crc | rflab_workstation | rflab_cluster | gpn_paradox" "psc_bridges2"
    opts_AddOptional  '--partition' 'partition' 'request a specific partition' "an optional argument; request a specific partition (node) for the resource allocation in the HCP cluster specified in 'location'; At PSC Bridges-2 we have the RM and em clusters. At Pitt CRC we have smp and high-mem. Default: RM (psc_bridges2), smp (pitt_crc), standard (rflab_cluster), workstation (rflab_workstation)" "RM-shared"
    opts_AddOptional  '--exclude' 'exclude' 'list of nodes to be excluded' "an optional argument; Explicitly exclude certain nodes from the resources granted to the job. Default: Depends on the partition. Usually None, but rflab_cluster_old exclude the new nodes and rflab_cluster_new exclude the old nodes." ""
    opts_AddOptional  '--mem_per_cpu' 'mem_per_cpu' 'specify the real memory requried per CPU' "an optional argument; specify the real memory required per CPU. Default: 2 GB RAM (we have 8 CPUs per subject and require a minimum of 8 GB RAM per subject, however -parallel triggers 16 CPUs per subject for some processing steps, hence allocate 2 GB of RAM)" "4G"
    opts_AddOptional  '--time' 'time' 'limit on the total run time of the job allocation' "an optional argument; When the time limit is reached, each task in each job step is sent SIGTERM followed by SIGKILL. Format: days-hours:minutes:seconds. Default: 6 hours" "0-6:00:00"
    opts_AddOptional  '--export' 'export' 'export environment variables' "an optional argument; Identify which environment variables from the submission environment are propagated to the launched application. Note that SLURM_* variables are always propagated. Default: all of the users environment will be loaded (either from callers environment or clean environment)" ""
    opts_AddOptional  '--mail_type' 'mail_type' 'type of mail' "an optional argument; notify user by email when certain event types occur. Default: FAIL,END" "FAIL,END"
    opts_AddOptional  '--mail_user' 'mail_user' 'user email' "an optional argument; User to receive email notification of state changes as defined by --mail_type. Default: None" ""
    opts_AddOptional  '--job_slots' 'job_slots' 'max number of active jobs' "an optional argument; The maximum number of jobs active at once  Default: unlimited" "0"
    
    # SPM Options
    opts_AddMandatory '--subjects' 'subjects' 'path to file with subject IDs or space-delimited list of subject IDs (identification strings) upon which to operate' "a required argument; path to a file with the IDs (identification strings) of the subjects to be processed (e.g. /data/ADNI/subjid_list.txt) or a space-delimited list of subject IDs (e.g., 'bert berta') upon which to operate. If subject directory doesn't exist in <DATASETDIR>, creates analysis directory <DATASETDIR>/<SUBJECT_ID> and converts one or more input volumes to MGZ format in SUBJECTDIR/<SUBJECT_ID>/mri/orig" "--s" "--sid" "--subjid"  "--subject" "--subjects_list" "--subjid_list"
    opts_AddMandatory '--studydir' 'studydir' 'specify study directory' "a required argument; is the path to the study directory (e.g. /data/ADNI)." "--ds"
    opts_AddOptional  '--subjectsdir' 'subjectsdir' "an optional argument; is the path to the subjects directory within <studydir> (e.g. /data/ADNI/raw). Default: none" "--subd"
    opts_AddOptional  '--batchdir' 'batchdir' 'set directory for matlab batches for SPM' "an optional argument: directory where the .mat matlab batches are stored or generated. Default: None" ""
    opts_AddOptional  '--batch_script' 'batch_script' 'set file used for generating batches. If not set then script will look for .mat batches in the batch directory' "an optional arguement; matlab file used to create batches if not already put in the batch directory toDefault:None" ""
    opts_AddOptional  '--step_names' 'step_names' 'Space seperated string with the names of all the folders that will be used for processing' "an optional arguement; Required for batch creation. Default: none" "" ""
    opts_AddOptional  '--debug' 'debug' 'print out lots of info' "an optional argument; if true, print out lots of information to error log file. Default: false" "false" "--v"

    # Miscellaneous Options
    opts_AddOptional  '--print' 'print' 'Perform a dry run' "an optional argument; If print is not a null or empty string variable, then this script and other scripts that it calls will simply print out the commands and with options it otherwise would run. This printing will be done using the command specified in the print variable, e.g., echo" " "
    opts_AddOptional  '--clean_job' 'clean_job' 'Caution! clean all previous runs of this job' "an optional argument; If clean_job is true, <studydir>/metadata/app-freesufer/jobs/<job_name> (except config.json the file) and <DATASETDIR>/<SUBJID>/processed/app-freesufer/jobs/<job_name> are removed. Default: false." "false"
    opts_AddOptional  '--clean_instance' 'clean_instance' 'Caution! Clean an specific run of this job' "an optional argument; If a timestamp is provided (accepted format: YYYYmmddHHMMSSUTC, where YYYY is the year, mm the month, dd the day, HH the hour, MM the minute, SS the second at the universal coordinate time (UTC)), then <studydir>/metadata/gpntk/jobs/<job_name>/<timestamp> and <DATASETDIR>/<SUBJID>/processed/gpntk/jobs/<job_name>/<timestamp> are removed. Default: None." ""
    
    opts_ParseArguments "$@"

    echo "----------------------------------------------------------"
    echo "Parsed/default options:"
    echo "----------------------------------------------------------"
    opts_ShowValues

    log_Msg "## END: input_parser"
}

parse_json()
{
    params=("job_name" "location" "partition" "exclude"
       "mem_per_cpu" "time" "export"
       "mail_type" "mail_user" "job_slots"
       "subjects" "s" "sid" "subjid"  "subject" "subjects_list" "subjid_list"
       "studydir" "ds" "subjectsdir" "subd"
       "input_dirname" "i_dirname" "input_filename" "i_filename"  "input" "i"
       "batchdir" "bd" "batch_script" "step_names"
       "debug" "v"  "print" "clean_job" "clean_instance")

    API_ARGS=()

    for param in ${params[@]} ; do
        param_value=`jq -r '.'"$param"' | select(.!=null)' $jsonfile`
        #log_Msg $param": "$param_value
        if [ ! -z $param_value ] ; then
            API_ARGS+=("--$param=$param_value")
        fi
    done
}

get_default_dataset_dir()
{
    log_Msg "## START: get_default_dataset_dir"

    # Check if subjectsdir and studydir are absolute or relative paths
    case $studydir in
        (/*) pathchk -- "$studydir" ;;
        (*) log_Msg "studydir must be an absolute path" ; exit 1 ;;
    esac

    case $subjectsdir in
        (/*) pathchk -- "$subjectsdir" ;
            log_Msg "studydir must be a relative path" ; exit 1 ;;
        (*) subjectsdir_relative="true" ;;
    esac

    if [ $subjectsdir_relative == "true" ] ; then
        if [ ! -z "${subjectsdir}" ] ; then
            if ! grep -q $subjectsdir $studydir ; then
                DATASETDIR=${studydir}/${subjectsdir}
            else
                log_Msg "subjectsdir must be a subdir of studydir"
                exit 1
            fi
        else
            DATASETDIR="${studydir}"
        fi
        # if subjectsdir is located in the studydir path, ok
    fi

    log_Msg "DATASETDIR:\n$DATASETDIR"

    log_Msg "## END: get_default_dataset_dir"
}

# --------------------------------------------------------------
# Setup Function
# --------------------------------------------------------------
setup()
{
    # e.g., timestamp=20210325132704UTC
    timestamp=$(date -u +%Y%m%d%H%M%S%Z)

    # ----------------------------------------------------------
    #  Load Function Libraries
    # ----------------------------------------------------------
    SRC="$(dirname $(readlink -f ${BASH_SOURCE[0]:-$0}))"
    cd $SRC
    APPDIR="$(dirname ${SRC})"
    UTILS=$APPDIR/lib
    echo $UTILS
    . ${UTILS}/log.shlib       # Logging related functions
    . ${UTILS}/opts.shlib "$@" # Command line option functions

    # if --help, show usage and exit
    if [[ "$1" == "--help" ]] ; then
        usage
        exit 0
    fi

    jsonfile=$1
    parse_json
    echo "###"
    log_Msg "${API_ARGS[@]}"
    input_parser "${API_ARGS[@]}"

    log_Msg "# START: setup"

    echo "----------------------------------------------------------"
    echo "Platform Information Follows: "
    echo "----------------------------------------------------------"
    uname -a

    echo "----------------------------------------------------------"
    echo "Verify required environment variables are set:"
    echo "----------------------------------------------------------"
    log_Check_Env_Var APPDIR
    log_Check_Env_Var UTILS

    log_Msg "config.json file location:\n$jsonfile"

    APP_JOBDIR="${APPDIR}/jobs/${job_name}"
    log_Msg "APP_JOBDIR:\n$APP_JOBDIR"

    get_default_dataset_dir

    STUDY_JOBDIR="${studydir}/metadata/gpntk/jobs/${job_name}"
    log_Msg "STUDY_JOBDIR:\n$STUDY_JOBDIR"

    # If clean_job=true, clean job metadata stored at the app
    # since we are using rm -rf, this first if is just an extra layer of security
    if [ -d $APP_JOBDIR ] ; then
        if [ $clean_job == "true" ] ; then
            log_Msg "Cleaning all app metadata for the job: $job_name"
            # remove all directories
            find $APP_JOBDIR/* -type d -exec rm -rf {} +
            # remove all files except config.json
            find $APP_JOBDIR/* -type f ! -name "config.json" -exec rm -f {} +

        # If clean_instance is set, clean job instance metadata stored at app
        elif [ ! -z ${clean_instance} ] && [[ -d $APP_JOBDIR/${clean_instance} ]]; then
            log_Msg "Cleaning all app metadata for the job instance: $job_name/$clean_instance"
            rm -rf $APP_JOBDIR/${clean_instance}
        fi
    fi

    # If clean_job=true, clean data produced by the job from individual subjects
    if [ $clean_job == "true" ] ; then
        if [ -d ${studydir}/processed/gpntk/jobs/${job_name} ] ; then
            log_Msg "Cleaning all data produced by the job: $job_name"
            rm -rf "${studydir}/processed/gpntk/jobs/${job_name}"
        fi
    # If clean_instance is set, clean data produced by the job instance from individual subjects
    elif [ ! -z ${clean_instance} ] ; then
        if [ -d $studydir/processed/gpntk/jobs/${job_name}/$clean_instance ] ; then
            log_Msg "Cleaning all data produced by the $job_name/${clean_instance}"
            rm -rf "${studydir}/processed/gpntk/jobs/${job_name}/${clean_instance}"
        fi
    fi

    # If clean_job=true, clean job metadata stored at dataset
    # since we are using rm -rf, this first if is just an extra layer of security
    if [ -d $STUDY_JOBDIR ] ; then
        if [ $clean_job == "true" ] ; then
            log_Msg "Cleaning all dataset metadata for the job: $job_name"
            rm -rf $STUDY_JOBDIR
        # If clean_instance is set, clean job instance metadata stored at dataset
        elif [ ! -z ${clean_instance} ] && [[ -d $STUDY_JOBDIR/${clean_instance} ]]; then
            log_Msg "Cleaning all dataset metadata for the job instance: $job_name/$clean_instance"
            rm -rf $STUDY_JOBDIR/${clean_instance}
        fi
    fi
    #make_batches
    JOB_LOGDIR="${APPDIR}/jobs/${job_name}/${timestamp}/log"
    mkdir -p $JOB_LOGDIR
    log_Msg "JOB_LOGDIR:\n$JOB_LOGDIR"

    log_Msg "# END: setup"
}

# --------------------------------------------------------------
# Get Subject IDs from file or list
# --------------------------------------------------------------
get_subjid_list()
{
    log_Msg "## START: get_subjid_list"

    local file_or_list=$1
    local delim=""
    local i=1
    local nsubjects

    subjid_list=()
    # If a file with the subject IDs was passed
    #if [ -f "$file_or_list" ] ; then
    #    while IFS= read -r line || [[ -n "$line" ]] ; do
    #        subjid_list+=($line)
    #    done < "$file_or_list"
    # Instead a space separated list was passed
    #else
    #    subjid_list=($file_or_list)
    #fi

    if [ -f "$file_or_list" ] ; then
        for line in `sed '/^$/d' $file_or_list` ; do
            subjid_list+=($line)
        done
    # Instead a space separated list was passed
    else
        subjid_list=($file_or_list)
    fi

    array=""
    # Create the array 1,2,3,...,nsubjects
    for id in ${subjid_list[@]} ; do
        array="$array$delim$i"
        delim=","
        i=$(($i+1))
    done

    # Append array task throttle
    array="$array%$job_slots"

    # Number of subjects
    nsubjects=$(($i-1))
    subjid_list_string="${subjid_list[@]}"
    subjid_list_string="${subjid_list_string// /,}"

    log_Msg "subjid_list: ${subjid_list[@]}"
    log_Msg "nsubjects: $nsubjects"

    unset file_or_list
    unset delim
    unset i

    log_Msg "## END: get_subjid_list"
}

get_default_queuing_options()
{
    log_Msg "### START: get_default_queuing_options"

    local  usage="Usage:
                --location={psc_bridges2|pitt_crc|rflab_cluster|
                            rflab_cluster_old|rflab_cluster_new|
                            rflab_workstation|gpn_paradox|
                            no_slurm_parallel|no_slurm_serial}"

    if [ -z "$partition" ]; then
        case "$location" in
            psc_bridges2 ) partition="RM-shared" ;;
            pitt_crc ) partition="smp" ;;
            rflab_cluster_old )
                partition="standard"
                exclude="nodes09-13" ;;
            rflab_cluster_new )
                partition="standard"
                exclude="nodes01-08" ;;
            rflab_cluster ) partition="standard" ;;
            rflab_workstation ) partition="workstation" ;;
            gpn_paradox ) partition="";;
            no_slurm_parallel ) partition="";;
            no_slurm_serial ) partition="";;
            * ) echo $usage ; exit 1 ;;
        esac
    fi

    log_Msg "partition: $partition"

    # %A is replaced with the value of $SLURM_ARRAY_JOB_ID (job ID)
    # %a is replaced with the value of $SLURM_ARRAY_TASK_ID (Array index value)
    case "$location" in
        psc_bridges2 )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        pitt_crc )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        rflab_cluster_old )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        rflab_cluster_new )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        rflab_cluster )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        rflab_workstation )
            output="$JOB_LOGDIR/slurm_-_%a.out"
            error="$JOB_LOGDIR/slurm_-_%a.err" ;;
        # The string 'subjid' will be replaced by the ID of the subject being processed
        gpn_paradox )
            output="$JOB_LOGDIR/parallel_-_subjid.out"
            error="$JOB_LOGDIR/parallel_-_subjid.err" ;;
        no_slurm_parallel )
            output="$JOB_LOGDIR/parallel_-_subjid.out"
            error="$JOB_LOGDIR/parallel_-_subjid.err" ;;
        no_slurm_serial )
            output="$JOB_LOGDIR/serial_-_subjid.out"
            error="$JOB_LOGDIR/serial_-_subjid.err" ;;
        * ) echo $usage ; exit 1 ;;
    esac

    log_Msg "output: $output"
    log_Msg "error: $error"

    unset usage

    log_Msg "### END: get_default_queuing_options"
}
#liang mentioned not to use arrays since that makes it take longer to queue apperently but im not sure about that 
array_contains()
{
    local array="$1[@]"
    local seeking=$2
    is_slurm_managed=0
    for element in "${!array}"; do
        if [[ "$element" == "$seeking" ]]; then
            is_slurm_managed=1
            break
        fi
    done
}
make_batches()
{
    GPNTK=/ocean/projects/med200002p/liw82/gpntk/bin/singularity-gpntk
    singularity_cmd=$GPNTK  
    #bind path to allocation storage
    singularity_cmd+=" -B $studydir"
    singularity_cmd+=" -B /ocean/projects/med200002p/liw82/gpntk/"
    singularity_cmd+=" -S /ocean/projects/med200002p/shared/gpntk/libexec/gpntk.sif "
    singularity_cmd+=" bash"
    log_Msg "$singularity_cmd 
        $APPDIR/src/SPM_Make_Batches.sh 
        --subjects=$subjects 
        --studydir=$studydir 
        --batchdir=$batchdir 
        --batchscript=$batch_script 
        --step_names=$step_names"
    #somehow need to get module to work
    $singularity_cmd \
    $APPDIR/src/SPM_Make_Batches.sh \
        --subjects="${subjects}" \
        --studydir="${studydir}" \
        --batchdir="${batchdir}" \
        --batchscript="${batch_script}" \
        --step_names="${step_names}"
    log_Msg "Finished making batches"

}
get_queuing_command()
{
    log_Msg "## START: get_queuing_command"

    # Get default slurm options for partition
    get_default_queuing_options

    # the --wait flag signals sbatch to not exit until the submitted job
    # terminates. The exit code of the sbatch command will be the same as the
    # exit code of the submitted job. If the job terminated due to a signal
    # rather than a normal exit, the exit code will be set to 1. In the case of
    # a job array, the exit code recorded will be the highest value for any
    # task in the job array.
    # --chdir=$APPDIR set $SLURM_SUBMIT_DIR set the working directory of the batch script to the root of the App before it is executed. The path can be specified as full path or relative path to the directory where the command is executed.
    # --ntasks-per-node=1 necessary for the job array to allocate resources correctly
    # --ntasks=1 necessary to signal that each job is an independent task
    batch="sbatch
        --job-name=${job_name} \
        --partition=$partition \
        --exclude=$exclude \
        --exclusive=user \
        --nodes=1 \
        --cpus-per-task=1\
        --mem-per-cpu=$mem_per_cpu \
        --time=$time \
        --export=$export \
        --mail-type=$mail_type \
        --mail-user=$mail_user \
        --output=$output \
        --error=$error \
        --array=$array \
        --wait"

    local slurm_managed_machine=("psc_bridges2"
                                 "pitt_crc"
                                 "rflab_cluster_old"
                                 "rflab_cluster_new"
                                 "rflab_cluster"
                                 "rflab_workstation")

    array_contains slurm_managed_machine "$location"
    if [ $is_slurm_managed -eq 1 ] ; then
        queuing_command=$batch
        log_Msg "queuing_command:
            --job-name=${job_name}
            --partition=$partition
            --exclude=$exclude
            --exclusive=user
            --nodes=1
            --cpus-per-task=1
            --mem-per-cpu=$mem_per_cpu
            --time=$time
            --export=$export
            --mail-type=$mail_type
            --mail-user=$mail_user
            --output=$output
            --error=$error
            --array=$array
            --wait"
    else
        queuing_command=""
        log_Msg "queuing_command: None"
    fi


    log_Msg "## END: get_queuing_command"
}

main()
{
    log_Msg "# START: main"

    # Get an index for each subject ID; It will be used to
    # submit an array job
    get_subjid_list $subjects

    JOB_ETCDIR="${APP_JOBDIR}/${timestamp}/etc"
    mkdir -p $JOB_ETCDIR
    cp -n $APP_JOBDIR/config.json "$JOB_ETCDIR/config_-_${job_name}_-_${timestamp}.json"
    config_file="$JOB_ETCDIR/config_-_${job_name}_-_${timestamp}.json"

    # If debug true, be verbose; outputs to error log file
    if [ "$debug" == "true" ] ; then
        directives+=" -debug"
    fi

    # Get queuing command
    get_queuing_command

    echo "----------------------------------------------------------"
    echo "BATCH_SPM.sh script call"
    echo "----------------------------------------------------------"

    echo "/BATCH_SPM.sh
  --subjects=${subjid_list[@]}
  --subjectsdir=$DATASETDIR
  --batchdir=$batchdir
  --step_names="${step_names}" 
  --job_name=$job_name
  --location=$location
  --job_slots=$job_slots
  --output=$output
  --error=$error
  --timestamp=$timestamp
  --print=$print"
    
    $queuing_command $APPDIR/src/BATCH_SPM.sh \
        --subjects="${subjid_list_string}" \
        --studydir="${studydir}" \
        --subjectsdir="${DATASETDIR}" \
        --batchdir="${batchdir}" \
        --step_names="${step_names}" \
        --job_name="${job_name}" \
        --location="${location}" \
        --job_slots="${job_slots}" \
        --output="${output}" \
        --error="${error}" \
        --timestamp="${timestamp}" \
        --print="${print}"

    wait

    log_Msg "# END: main"

}

clean()
{
    log_Msg "# START: clean"

    echo "---------------------------------------------------------------------"
    echo "Saving gpntk run log files:"
    echo "---------------------------------------------------------------------"
    STUDY_JOBDIR="${studydir}/metadata/gpntk/jobs/${job_name}/${timestamp}"
    log_Msg "Metadata for the current job instance location:\n$STUDY_JOBDIR"
    STUDY_LOGDIR="$STUDY_JOBDIR/log"
    mkdir -p $STUDY_LOGDIR
    log_Msg "Log folder for the current job instance location:\n$STUDY_LOGDIR"

    # Copy config.json into dataset dir
    STUDY_ETCDIR="$STUDY_JOBDIR/etc"
    mkdir -p $STUDY_ETCDIR
    log_Msg "etc folder for the current job instance:\n$STUDY_ETCDIR"
    cp -n $config_file $STUDY_ETCDIR

    for SUBJID in "${subjid_list[@]}"; do
        SUBJID_JOBDIR="${studydir}/processed/gpntk/jobs/${job_name}/${timestamp}/${SUBJID}"
        mkdir -p $SUBJID_JOBDIR
        stdout_filename="${SUBJID}_-_gpntk_-_${job_name}_-_${timestamp}.out"
        stderr_filename="${SUBJID}_-_gpntk_-_${job_name}_-_${timestamp}.err"

        # Append API_GPNTK.sh log files to gpntk log files
        if [ -f $JOB_LOGDIR/API.out ]; then
            cp "$JOB_LOGDIR/API.out" $STUDY_LOGDIR/${stdout_filename}
        fi
        if [ -f $JOB_LOGDIR/API.err ]; then
            cp "$JOB_LOGDIR/API.err" $STUDY_LOGDIR/${stderr_filename}
        fi

        # Append BATCH_GPNTK.sh log files to gpntk log files
        if [ -f $STUDY_LOGDIR/BATCH_-_${SUBJID}.out ]; then
            cat $STUDY_LOGDIR/BATCH_-_${SUBJID}.out >> $STUDY_LOGDIR/${stdout_filename}
            rm -f $STUDY_LOGDIR/BATCH_-_${SUBJID}.out
        fi
        if [ -f $STUDY_LOGDIR/BATCH_-_${SUBJID}.err ]; then
            cat $STUDY_LOGDIR/BATCH_-_${SUBJID}.err  >> $STUDY_LOGDIR/${stderr_filename}
            rm -f $STUDY_LOGDIR/BATCH_-_${SUBJID}.err
        fi

        # Append APP_GPNTK.sh log files to gpntk log files
        if [ -f $STUDY_LOGDIR/APP_-_${SUBJID}.out ]; then
            cat $STUDY_LOGDIR/APP_-_${SUBJID}.out >> $STUDY_LOGDIR/${stdout_filename}
            rm -f $STUDY_LOGDIR/APP_-_${SUBJID}.out
        fi
        if [ -f $STUDY_LOGDIR/APP_-_${SUBJID}.err ]; then
            cat $STUDY_LOGDIR/APP_-_${SUBJID}.err  >> $STUDY_LOGDIR/${stderr_filename}
            rm -f $STUDY_LOGDIR/APP_-_${SUBJID}.err
        fi

        if [ -f $STUDY_LOGDIR/${stdout_filename} ]; then
            cat >> $STUDY_LOGDIR/${stdout_filename} <<-EOF
$(date):$(basename "$0"): # START: clean"
--------------------------------------------------------------------------------
Creating gpntk log files
--------------------------------------------------------------------------------
$(date):$(basename "$0"): subjects permanent log dir:
$STUDY_LOGDIR"

--------------------------------------------------------------------------------
Final log file created, clean partial log files
--------------------------------------------------------------------------------
$(date):$(basename "$0"): # END: clean"
################################################################################
################################## END: API_GPNTK.sh ##############################
################################################################################
EOF
        fi

        SUBJID_LOGDIR=$SUBJID_JOBDIR/log
        mkdir -p $SUBJID_LOGDIR
        # Copy log file inside subject dir
        if [ -f $STUDY_LOGDIR/${stdout_filename} ]; then
            cp $STUDY_LOGDIR/${stdout_filename} $SUBJID_LOGDIR/${stdout_filename}
        fi
        if [ -f $STUDY_LOGDIR/${stderr_filename} ]; then
            cp $STUDY_LOGDIR/${stderr_filename} $SUBJID_LOGDIR/${stderr_filename}
        fi

        SUBJID_ETCDIR=$SUBJID_JOBDIR/etc
        mkdir -p $SUBJID_ETCDIR

        # Copy config.json into subject dir
        cp -n "$config_file" \
            "$SUBJID_ETCDIR/${SUBJID}_-_config_-_${job_name}_-_${timestamp}.json"

        # Append SUBJID to subjects.txt file
        printf "%s\n" "${SUBJID}" >> $STUDY_JOBDIR/subjects.txt

    done

    # Copy metadata from study directory to the corresponding folder in processed
    mkdir -p "${studydir}/processed/gpntk/jobs/${job_name}/${timestamp}/metadata"
    cp -r $STUDY_JOBDIR/* \
        "${studydir}/processed/gpntk/jobs/${job_name}/${timestamp}/metadata/"

    # Rename API_GPNTK.sh log files to gpntk_-_${job_name}_-_${timestamp}.*
    if [ -f $JOB_LOGDIR/API.out ]; then
        mv $JOB_LOGDIR/API.out "$JOB_LOGDIR/gpntk_-_${job_name}_-_${timestamp}.out"
    fi
    if [ -f $JOB_LOGDIR/API.err ]; then
        mv $JOB_LOGDIR/API.err "$JOB_LOGDIR/gpntk_-_${job_name}_-_${timestamp}.err"
    fi

    echo "-------------------------------------------------------------------"
    echo "Final log files created"
    echo "-------------------------------------------------------------------"

    log_Msg "# END: clean"
}

halt()
{
   exit_code=$?
   if [ $exit_code -ne 0 ]; then
       echo "###################################################"
       echo "################ HALT: APP_GPNTK.sh ##################"
       echo "###################################################"

       clean
   fi
}

run_main()
{
    echo "###################################################"
    echo "################ START: API_GPNTK.sh #################"
    echo "###################################################"

    main
    clean

    echo "#################################################"
    echo "################ END: API_GPNTK.sh #################"
    echo "#################################################"
}

# ##############################################################################
#                               EXECUTION START
# ##############################################################################
echo "####### start run_spm"

setup "$@"

run_main \
    1> "$JOB_LOGDIR/API.out" \
    2> "$JOB_LOGDIR/API.err"

# happy end
exit 0

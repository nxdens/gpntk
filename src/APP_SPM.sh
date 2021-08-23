#!/bin/bash
# source before everything else

source /etc/profile

trap 'halt' SIGINT SIGKILL SIGTERM SIGSEGV EXIT

# Setup this script such that if any command exits with a non-zero value, the
# script itself exits and does not attempt any further processing. Also, treat
# unset variables as an error when substituting.
set -eu

#
# ------------------------------------------------------------------------------
#  Usage Description Function
# ------------------------------------------------------------------------------
usage()
{
    echo "
    $log_ToolName: app-gpntk

Usage: $log_ToolName
    --subjid=<string>                            The subject name
    [--subjectdir=<dir path>]                    Default: None
    [--batchdir=<batch directory>]               Default: None


    PARAMETERs are [ ] = optional; < > = user supplied value
"
    # automatic argument descriptions
    opts_ShowArguments
}

# ##############################################################################
# CODE START
# ##############################################################################

# ------------------------------------------------------------------------------
#  Input Parser Function
# ------------------------------------------------------------------------------
input_parser()
{
    log_Msg "# START: input_parser"

    opts_AddMandatory '--subjid' 'subjid' 'Subject ID' "a required value; the subject name" "--s" "--sid" "--subject"
    opts_AddOptional '--subjectdir' 'subjectdir' 'Directory with data' "an optional value; the path to the directory holding subject data. Default: None" "" "--sd"
    opts_AddOptional '--batchdir' 'batchdir' 'set directory for matlab batches for SPM' "an optional argument: directory where the .mat matlab batches are stored or generated. If using script to generate them please pass the script to the --batchfile arguement. Default: None" "" "--bd"
    opts_AddOptional '--step_names' 'step_names' 'Space seperated string with the names of all the folders that will be used for processing' "an optional arguement; Required for batch creation. Default: none" "" ""
    opts_AddOptional '--print' 'print' 'Perform a dry run' "an optional argument; If PRINT is not a null or empty string variable, then this script and other scripts that it calls will simply print out the commands and with options it otherwise would run. This printing will be done using the command specified in the PRINT variable, e.g., echo" ""

    opts_ParseArguments "$@"

    print="${print//,/ }"

    echo "----------------------------------------------------------"
    echo "Input Arguments:"
    echo "----------------------------------------------------------"
    # Display the parsed/default values
    opts_ShowValues

    log_Msg "# END: input_parser"
}

# ------------------------------------------------------------------------------
# Setup Function
# ------------------------------------------------------------------------------
setup()
{
    # ------------------------------------------------------------------------------
    #  Load Function Libraries
    # ------------------------------------------------------------------------------
    
    UTILS="/ocean/projects/med200002p/liw82/gpntk/lib"
    set -a
    . ${UTILS}/log.shlib       # Logging related functions
    . ${UTILS}/opts.shlib "$@" # Command line option functions
    set +a

    log_Msg "# START: setup"
    
    
    log_Msg "Platform Information Follows: "
    # ------------------------------------------------------------------------------
    uname -a

    # ------------------------------------------------------------------------------
    log_Msg "Show and Verify required environment variables are set:"
    # ------------------------------------------------------------------------------
    
    log_Check_Env_Var UTILS

    log_Msg "# END: setup"
}
# ------------------------------------------------------------------------------
# Main Function
# ------------------------------------------------------------------------------
main()
{
    log_Msg "# START: main"

    # --------------------------------------------------------------------------
    log_Msg "Build Paths"
    # --------------------------------------------------------------------------
    log_Msg "Get batch path"
    #need to check for non file paths
    
    #for folder in ($step_names)
    #do
    BATCH_PATH=$batchdir"/step03_motion_correction/"${subjid//\//_}".mat"
    log_Msg $BATCH_PATH
    
    
    module load spm12

    spm_command="spm batch "${BATCH_PATH}
    #spm_command="spm --help"
    
    # -dontrun just prints the commands that will run, without execute them
    if [ ! -z $print ] ; then
        spm_command+=" -dontrun"
    fi

    log_Msg "spm_command:\n${spm_command}"


    echo "----------------------------------------------------------"
    echo "run spm batch command"
    echo "----------------------------------------------------------"
    ${spm_command}

    return_code=$?
    if [ "${return_code}" != "0" ]; then
        log_Err_Abort "recon-all command failed with return_code: ${return_code}"
    fi
    #done



    echo "----------------------------------------------------------"
    echo "spm steps completed!"
    echo "----------------------------------------------------------"
    log_Msg "# END: main"
}

clean()
{
    log_Msg "# START: clean"

    #remove stuff

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


echo "####################################################"
echo "################ START: APP_GPNTK.sh ##################"
echo "####################################################"

setup
input_parser "$@"
main
clean

echo "##################################################"
echo "################ END: APP_GPNTK.sh ##################"
echo "##################################################"
echo ""

# happy end
exit 0

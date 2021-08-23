#!/bin/bash
# This script should be called within singularity image (not yet working)
input_parser()
{
    log_Msg "# START: input_parser"

    opts_AddMandatory '--subjects' 'subjects' 'Subject ID' "a required value; the subject name" "--s" "--subjects"
    opts_AddOptional '--studydir' 'studydir' 'Directory with data' "an optional value; the path to the directory holding subject data. Default: None" "" "--sd"
    opts_AddOptional '--batchdir' 'batchdir' 'set directory for matlab batches for SPM' "an optional argument: directory where the .mat matlab batches are stored or generated. If using script to generate them please pass the script to the --batchfile arguement. Default: None" "" "--bd"
    opts_AddOptional  '--batchscript' 'batchscript' 'set file used for generating batches. If not set then script will look for .mat batches in the batch directory' "an optional arguement; matlab file used to create batches if not already put in the batch directory toDefault:None" "" "--bs"
    opts_AddOptional  '--step_names' 'step_names' 'Space seperated string with the names of all the folders that will be used for processing' "an optional arguement; Required for batch creation. Default: none" "" ""
    opts_ParseArguments "$@"

    print="${print//,/ }"

    echo "----------------------------------------------------------"
    echo "Input Arguments:"
    echo "----------------------------------------------------------"
    # Display the parsed/default values
    opts_ShowValues

    log_Msg "# END: input_parser"
}
setup()
{
    source /etc/profile
    SRC="$(dirname $(readlink -f ${BASH_SOURCE[0]:-$0}))"
    cd $SRC
    APPDIR="$(dirname ${SRC})"
    UTILS=$APPDIR/lib
    echo $SRC
    . ${UTILS}/log.shlib       # Logging related functions
    . ${UTILS}/opts.shlib "$@" # Command line option functions
    
}
main()
{
    #do this here since it needs to be after input parser
    BATHCLOC=$(dirname ${batchscript})
    BATCHNAME=$(basename ${batchscript})
    
    # want this to eventually be spm12
    module load spm12 
    cd $BATHCLOC
    spm eval "$BATCHNAME(\"$subjects\", \"$studydir\",\"$batchdir\", \"$step_names\");"
}

setup
input_parser "$@"
main
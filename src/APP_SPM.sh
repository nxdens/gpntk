#!/bin/bash

trap 'halt' SIGINT SIGKILL SIGTERM SIGSEGV EXIT

# Setup this script such that if any command exits with a non-zero value, the
# script itself exits and does not attempt any further processing. Also, treat
# unset variables as an error when substituting.
set -eu

#
# ------------------------------------------------------------------------------
#  Usage Description Function
# ------------------------------------------------------------------------------
function usage()
{
    echo "
    $log_ToolName: app-freesurfer

Usage: $log_ToolName
    --subjid=<string>                            The subject name
    [--subjectdir=<dir path>]                    Default: None
    [--input=<file path>]                        Single NIFTi/DICOM file from series
                                                 Default: <subjectdir>/<subjid>/mri/orig/XXX.mgz
                                                 (XXX is a 3-digit, zero-padded number)
    [--T2=<path to DICOM or NIFTI>]              Default: None
    [--FLAIR=<path to DICOM or NIFTI>]           Default: None
    [--directives=<directives>]                  Default: -autorecon-all
    [--expert_opts=<expert options>]             Default: None
    [--expert_opts_file=<expert options file>]   Default: None


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
    opts_AddOptional '--input' 'input' 'Path to input file' "an optional value; the path to the subject data (NIFTI/DICOM file). Default: <subjectdir>/<subjid>/mri/orig/xxx.mgz" "" "--i"
    opts_AddOptional  '--T2' 'T2' 'path relative to <subjectsdir>/<subjid> to single DICOM file from a T2 MRI series or a single NIFTI file from a T2 series' "an optional argument; path relative to <subjectsdir>/<subjid> to single DICOM file from a T2 MRI series or a single NIFTI file from a T2 series. Default: None." "" "--t2"
    opts_AddOptional  '--FLAIR' 'FLAIR' 'path relative to <subjectsdir>/<subjid> to single DICOM file from a FLAIR MRI series or a single NIFTI file from a FLAIR series' "an optional argument; path relative to <subjectsdir>/<subjid> to single DICOM file from a FLAIR MRI series or a single NIFTI file from a FLAIR series. Default: None." "" "--flair"
    opts_AddOptional '--directives' 'directives' 'space-delimited list of freesurfer directives' 'an optional argument; space-delimited list of freesurfer directives to instruct recon-all which part(s) of the reconstruction stream to run (e.g., "-autorecon-all -notalairach"). Default: -autorecon-all.' "-autorecon-all"
    opts_AddOptional '--expert_opts' 'expert_opts' 'space-delimited list of freesurfer expert options' 'an optional argument; space-delimited list of freesurfer expert options (e.g., "-normmaxgrad maxgrad"; passes "-g maxgrad to mri_normalize"). The expert preferences flags supported by recon-all to be passed to a freesurfer binary. Default: None.' ""
    opts_AddOptional '--expert_opts_file' 'expert_opts_file' 'path to file containing special options to include in the command string' 'an optional argument; path to file containing special options to include in the command string (in addition to, not in place of the expert options flags already set). The file should contain as the first item the name of the command, and the items following it on rest of the line will be passed as the extra options (e.g., "mri_em_register -p .5"). Default: None.' "" "--expert"
    opts_AddOptional '--print' 'print' 'Perform a dry run' "an optional argument; If PRINT is not a null or empty string variable, then this script and other scripts that it calls will simply print out the commands and with options it otherwise would run. This printing will be done using the command specified in the PRINT variable, e.g., echo" ""

    opts_ParseArguments "$@"

    #replace commas with spaces in comma separated options
    directives="${directives//,/ }"
    expert_opts="${expert_opts//,/ }"
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
    UTILS="/app-freesurfer/lib"
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
    log_Check_Env_Var FREESURFER_HOME
    log_Check_Env_Var SUBJECTS_DIR
    log_Check_Env_Var UTILS

    log_Msg "# END: setup"
}

# ------------------------------------------------------------------------------
# Generate volumes in NIFTI format and in rawavg space
# that has been aligned by BBR but not undergone
# FreeSurfer intensity normalization
# ------------------------------------------------------------------------------
make_t1w_hires_nifti_file()
{
    log_Msg "## START: make_t1w_hires_nifti_file"

	local working_dir
	local t1w_input_file
	local t1w_brain_input_file
	local t1w_output_file
	local t1w_brain_output_file
	local mri_convert_cmd
	local return_code

	working_dir="${1}"

	pushd "${working_dir}"

	# We should already have the necessary T1w volume.
	# It's the rawavg.mgz file. We just need to convert
	# it to NIFTI format.

	t1w_input_file="rawavg.mgz"
	t1w_brain_input_file="brain-in-rawavg.mgz"
	t1w_output_file="t1w_hires.nii.gz"
	t1w_brain_output_file="t1w_brain_hires.nii.gz"

	if [ ! -e "${t1w_input_file}" ]; then
		log_Err_Abort "Expected t1w_input_file: ${t1w_input_file} DOES NOT EXIST"
	fi

	if [ ! -e "${t1w_brain_input_file}" ]; then
		log_Err_Abort "Expected t1w_input_file: ${t1w_brain_input_file} DOES NOT EXIST"
	fi

	mri_convert_cmd="mri_convert ${t1w_input_file} ${t1w_output_file}"
	mri_convert_cmd_brain="mri_convert ${t1w_brain_input_file} ${t1w_brain_output_file}"

	log_Msg "Creating ${t1w_output_file} with ${mri_convert_cmd}"
	${mri_convert_cmd}
	return_code=$?
	if [ "${return_code}" != "0" ]; then
		log_Err_Abort "${mri_convert_cmdn} command failed with return code: ${return_code}"
	fi

	log_Msg "Creating ${t1w_brain_output_file} with ${mri_convert_cmd_brain}"
	${mri_convert_cmd_brain}
	return_code=$?
	if [ "${return_code}" != "0" ]; then
		log_Err_Abort "${mri_convert_cmd_brain} command failed with return code: ${return_code}"
	fi

	popd

    log_Msg "## END: make_t1w_hires_nifti_file"
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
    mridir="${subjectdir}/${subjid}/mri"
    surfdir="${subjectdir}/${subjid}/surf"
    log_Msg "mridir: $mridir"
    log_Msg "surfdir: $surfdir"

    if [ ! -z $input ] ; then
        # -----------------------------------------------------------------------
        log_Msg "Thresholding T1w input to eliminate negative voxel values"
        # -----------------------------------------------------------------------
        zero_thresh_input=$(remove_ext ${input})_zero_threshold.nii.gz
        log_Msg "zero_thresh_input: ${zero_thresh_input}"

        fslmaths ${input} -thr 0 ${zero_thresh_input}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "${zero_thresh_input} fslmaths command failed with return_code: ${return_code}"
        fi
    fi

    if [ ! -z $T2 ] ; then
        # -----------------------------------------------------------------------
        log_Msg "Thresholding T2w input to eliminate negative voxel values"
        # -----------------------------------------------------------------------
        zero_thresh_t2=$(remove_ext ${T2})_zero_threshold.nii.gz
        log_Msg "zero_thresh_t2: ${zero_thresh_t2}"

        fslmaths ${T2} -thr 0 ${zero_thresh_t2}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "${zero_thresh_t2} fslmaths command failed with return_code: ${return_code}"
        fi
    fi

    if [ ! -z $FLAIR ] ; then
        # -----------------------------------------------------------------------
        log_Msg "Thresholding FLAIR input to eliminate negative voxel values"
        # -----------------------------------------------------------------------
        zero_thresh_flair=$(remove_ext ${FLAIR})_zero_threshold.nii.gz
        log_Msg "zero_thresh_flair: ${zero_thresh_flair}"

        fslmaths ${FLAIR} -thr 0 ${zero_thresh_flair}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "${zero_thresh_flair} fslmaths command failed with return_code: ${return_code}"
        fi
    fi

    echo "----------------------------------------------------------"
    echo "Build recon-all command"
    echo "----------------------------------------------------------"
    # -time reports the time each step takes
    # -clean-xopts cleans pre-existing expert options file
    recon_all_cmd="recon-all -time -clean-xopts"
    recon_all_cmd+=" $directives"
    recon_all_cmd+=" -subject ${subjid}"
    recon_all_cmd+=" -sd $subjectdir"
    if [ ! -z $input ] ; then
        recon_all_cmd+=" -i ${zero_thresh_input}"
    fi

    # Remove -FLAIRpial and -T2pial from directives; if needed they will be
    # automatically set below
    directives="${directives//-FLAIRpial/}"
    directives="${directives//-T2pial/}"
    # Preference for FLAIR
    if [ ! -z $FLAIR ] ; then
        recon_all_cmd+=" -FLAIR ${zero_thresh_flair} -FLAIRpial"
    # If no FLAIR available, check if T2 available
    elif [ ! -z $T2 ] ; then
        recon_all_cmd+=" -T2 ${zero_thresh_t2} -T2pial"
    fi

    # Check if an expert options was provided
    if [ ! -z $expert_opts ] ; then
        recon_all_cmd+=" $expert_opts"
    fi
    # Check if an expert options file was provided
    if [ ! -z $expert_opts_file ] ; then
        recon_all_cmd+=" -expert $expert_opts_file"
    fi
    # -dontrun just prints the commands that will run, without execute them
    if [ ! -z $print ] ; then
        recon_all_cmd+=" -dontrun"
    fi

    log_Msg "recon_all_cmd:\n${recon_all_cmd}"

    # Check if multistrip
    if [[ "${directives}" == *"-multistrip"* ]]; then
        log_Msg "multistrip -> setenv WATERSHED_PREFLOOD_HEIGHTS '10 15 20 25 30 35 40 45 50'"
        export WATERSHED_PREFLOOD_HEIGHTS='10 15 20 25 30 35 40 45 50'
    fi

    echo "----------------------------------------------------------"
    echo "Call recon-all command"
    echo "----------------------------------------------------------"
    ${recon_all_cmd}

    return_code=$?
    if [ "${return_code}" != "0" ]; then
        log_Err_Abort "recon-all command failed with return_code: ${return_code}"
    fi

    # If high resolution, run mris_inflate -n 15 ?h.smoothwm ?h.inflated after
    # recon-all is finished to deflate the surface
    if [[ "${directives}" == *"-hires"* ]] ; then
        if [ -f "${surfdir}/rh.smoothwm" ] && [ -f "${surfdir}/lh.smoothwm" ]; then
            # -------------------------------------------------------------------------
            log_Msg "If High Resolution, run mris_inflate with n=15"
            # --------------------------------------------------------------------------
            log_Msg "mris_inflate -n 15 ${surfdir}/rh.smoothwm ${surfdir}/rh.inflated"
            $print mris_inflate -n 15 ${surfdir}/rh.smoothwm ${surfdir}/rh.inflated
            log_Msg "mris_inflate -n 15 ${surfdir}/lh.smoothwm ${surfdir}/lh.inflated"
            $print mris_inflate -n 15 ${surfdir}/lh.smoothwm ${surfdir}/lh.inflated
        fi
    fi


    echo "----------------------------------------------------------"
    echo "Convert from FreeSurfer space back to native space"
    echo "----------------------------------------------------------"
    echo "mri_vol2vol
  --mov ${mridir}/brainmask.mgz
  --targ ${mridir}/rawavg.mgz
  --regheader --o ${mridir}/brain-in-rawavg.mgz
  --no-save-reg"
    $print mri_vol2vol --mov ${mridir}/brainmask.mgz \
                       --targ ${mridir}/rawavg.mgz \
                       --regheader --o ${mridir}/brain-in-rawavg.mgz \
                       --no-save-reg

    echo "----------------------------------------------------------"
    echo "Generate NIFTI files"
    echo "----------------------------------------------------------"
    $print make_t1w_hires_nifti_file ${mridir}

    echo "----------------------------------------------------------"
    echo "freesurfer recon-all completed!"
    echo "----------------------------------------------------------"
    log_Msg "# END: main"
}

clean()
{
    log_Msg "# START: clean"

    if [ ! -z ${zero_thresh_input:-} ] ; then
        # ----------------------------------------------------------------------
        log_Msg "Clean up file: ${zero_thresh_input}"
        # ----------------------------------------------------------------------
        rm -f ${zero_thresh_input}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "rm ${zero_thresh_input} failed with return_code: ${return_code}"
        fi
    fi

    if [ ! -z ${zero_thresh_t2:-} ] ; then
        # ----------------------------------------------------------------------
        log_Msg "Clean up file: ${zero_thresh_t2}"
        # ----------------------------------------------------------------------
        rm -f ${zero_thresh_t2}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "rm ${zero_thresh_t2} failed with return_code: ${return_code}"
        fi
    fi

    if [ ! -z ${zero_thresh_flair:-} ] ; then
        # ----------------------------------------------------------------------
        log_Msg "Clean up file: ${zero_thresh_flair}"
        # ----------------------------------------------------------------------
        rm -f ${zero_thresh_flair}
        return_code=$?
        if [ "${return_code}" != "0" ]; then
            log_Err_Abort "rm ${zero_thresh_flair} failed with return_code: ${return_code}"
        fi
    fi

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

echo ""
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

# Organization

in libexec or bin call app-gpntk which parses find the command called and finds the right json file

​	we will just add a command "run_spm" 

​	or maybe just make it a json file config thing? probably not

app-spm calls API_GPNTK which sets up slurm command and parameters for BATCH_GPNTK

​	this calls matlab to generate batches 

​	then runs batch?

BATCH_GPNTK actually calls the slurm command for every subject in teh batch

Batch calls the app_gpntk

app_gpntk sets up singularity

where is setup_gpntk/fs used????

## Functions to work on

- [ ] ### API_GPNTK

  - [x] setup

  ​	program flow

  1. make timestamp
  2. loads libraries
  3. check if help is used
  4. read json and parse it 
     1. json filename from the input args 
     2. parse json stores all parameters to API_ARGS
     3. input_parser is passed API_ARGS 
  5. find study and app directory folders for job
  6. check for clean parameter
     1. removes all metadata for previous previous instances of the job
     2. and a bunch of other stuff that i don't think needs to be changed 

  - [x] usage - check file structure section - kinda done for now

  - [x] input_parser - check file structure section - kinda done for now

    - [ ] test

  - [x] parse_json - check file structure section - kinda done for now; check to make sure array for the pipeline_steps works

    - [ ] Test

  - [x] get_default_dataset_dir

    - [ ] test

    shouldn't need any changes but need to test

  - [x] get_subjid_list

    should be fine

  - [x] get_default_queuing_options

    should be fine 

  - [x] array_contains - maybe not needed

  - [x] get_queuing_command

  - [x] get_default_freesurfer_input_option - remove all calls of this

  - [x] get_default_freesurfer_T2_options - remove all calls of this

  - [x] get_default_freesurfer_FLAIR_option - remove all calls of this

  - [x] set_hires - remove all calls of this

  - [ ] main

    need to fix the batch script call after fixing the batch script :|

  - [x] clean

    should be fine

  - [x] Check for compatibility with batch/setup/app scripts

    only calls the batch script here 

- [ ] ### BATCH_GPNTK

  - [ ] APP_fs call
  - [ ] usage
  - [ ] input_parser
  - [ ] setup
  - [ ] setup_slurm
  - [ ] setup_parallel - remove all calls
  - [ ] setup_bridges2 - should be fine
  - [ ] rsync_local 
  - [ ] rsync_to_bridges2
  - [ ] rsync _from_bridges2
  - [ ] rsync_to_rflab - remove all calls
  - [ ] rsync_from rflab - remove all calls
  - [ ] _rsync
  - [ ] main
  - [ ] clean
  - [ ] halt
  - [ ] run_main
  - [ ] run_main_with_parallel -remove all calls
  - [ ] run_main_serial - remove all calls
  - [ ] exit stuff

- [ ] ### APP_SPM 

  - [ ] input_parser
  - [ ] setup
  - [ ] main 
  - [ ] make_t1w_hires_nifti_file - remove
  - [ ] clean
  - [ ] halt - should be fine

- [ ] ### Check argument compatibility and system compatibility

## Json file structure

```json
{
    "job_name": "example",
    "location": "gpn_paradox",
    "subjects": "/example/metadata/subjects.txt",
    "studydir": "/example",
    "GPN_toolbox": "/ocean/projects/med200002p/shared/PipelineScripts/GPN_Toolbox",
    "input_dirname": "MNI",
    "input_filename": "7T11.nii.gz",
	"batch_directory": "example_batches",
    "batch_script":"/example/step05_encoding_preprocessing.m",
    "pipeline_steps": [
    	"realign",
    	"coreg"
    ]
}
```

subjects need to be formatted as subjectID/scanID within the subjects file

lets only worry about realign for now before adding compatibility for other steps

​	will want to make this more dynamic to allow for different ordering of different stages in the preprocessing

​	do we want automate the batch generation?

​	do we want to automate the pipeline steps? Almost certainly

eventually we want to add FSL and CONN options to this as well since they are used together
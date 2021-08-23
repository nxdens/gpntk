# app-freesurfer

This is a wrapper for [Freesurfer](https://surfer.nmr.mgh.harvard.edu/); a popular brain segmentation tool developed by Athinoula A. Martinos Center for Biomedical Imaging at Massachusetts General Hospital.

# SPM-fork
This fork adds compatibility for spm within the app-freesurfer api as a temporary measure until we decide whether to spin it off into it's own thing (app-spm or something) or just keep it as is. 

### Authors
- [Eduardo Diniz](https://github.com/eduardojdiniz)
- [Linghai Wang](http://github.com/nxdens)
## Installing the App
1. git clone this repo.

For the purpose of this document, it is assumed that the repository is cloned at `$HOME` under the name `app-freesurfer`.
```bash
$ cd $HOME
$ git clone git@github.com:gpnlab/app-freesurfer.git
````

2. source the App configuration file
```bash
$ source $HOME/app-freesurfer/etc/app.conf
```

```bash
bash /iw82/gpntk/libexec/app-gpntk.sh run_spm test_spm
```
## Dependencies

This App only requires [jq](https://stedolan.github.io/jq/) and [singularity](https://www.sylabs.io/singularity/) to run. Also, for batch jobs, [SLURM](https://www.schedmd.com/) or [parallel](https://www.gnu.org/software/parallel/) if SLURM is not available.

## Running the App

1. Inside the folder jobs in the root of the cloned directory, create a folder with your job name (`job_name`) and a `config.json` inside it
```bash
app-freesurfer
├── jobs
    └── example
        └── config.json
```

The configuration file `config.json` must be populated with something like
```json
{
    "job_name": "test_spm",
    "location": "psc_bridges2",
    "subjects": "/ocean/projects/med200002p/liw82/metadata/subjects.txt",
    "studydir": "/ocean/projects/med200002p/liw82/fMRI",
    "batchdir": "/ocean/projects/med200002p/liw82/fMRI/batches",
    "batchscript": "/ocean/projects/med200002p/liw82/fMRI/batches/make_batches",
    "clean_job": false,
    "mail_user": "liw82@pitt.edu",
    "time": "01:00:00",
    "step_names": "step03_motion_correction/ step04_mean_skullstrip_BET.txt"
}
```

The arguments allowed in the `config.json` are the ones processed by the `$HOME/app-freesurfer/src/API_fs.sh script`. A list of the supported arguments can be accessed by executing

```bash
$ app-freesurfer --help
```

Below is a short summary of the supported arguments

```
"job_name": <name for job allocation>
["location": <name of the HCP>]                       Default: psc_bridges2
["partition": <request a specific partition>]         Default: RM
["exclude": <node(s) to be excluded>]                 Default: None
["cpus_per_task": <number of CPUs per task>]          Default: 8
["mem_per_cpu": <real memory per CPU>]                Default: 1G
["time": <limit on the total runtime]                 Default: 10 hours
["export": <export environment variables>]            Default: ALL
["mail_type": <type of mail>]                         Default: FAIL,END
["mail_user": <user email>]                           Default: None

Freesurfer Options
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
["print": <print command>]                            Default: None
[--clean_job=<clean all previous run of this job>]    Default: false
[--clean_instance=<clean specific run of this job>]   Default: None

PARAMETERs are [ ] = optional; < > = user supplied value
```

2. Launch the App by executing `$ app-freesurfer run 'job_name'`, where `job_name` is the name of the folder inside the directory jobs with a `json.conf` with the job specifications inside. For example

```bash
$ app-freesurfer run example
```

## Output

The main output of this App are directories named `studydir/processed/app-freesurfer/jobs/job_name/subjid/timestamp`, where `studydir` is the root directory where the data is located, `job_name` refers to the job name, `subjid` refers to the name of the folder where the subjects' input volume data are located, and `timestamp` is a unique identifier for the job instance. A example of output (e.g., `/data/processed/app-freesurfer/jobs/example/bert/20210407095730UTC`, where `/data` is the data root directory, `example` is the job name, `bert` the subject id, and `20210407095730UTC` is the timestamp). This folder contains various freesurfer sub directories

```bash
/data
  └──processed
      └── app-gpntk
          └── jobs
              └── example
                   └─ 20210407095730UTC
                        ├─── metadata
                        └─── bert
                              ├── etc
                              ├── label
                              ├── log
                              ├── mri
                              ├── scripts
                              ├── stats
                              ├── surf
                              ├── tmp
                              ├── touch
                              └── trash
```
The folders `etc` and `log` are not generated by FreeSurfer; `etc` has a copy of the `config.json` file and a copy of the `expert.opts` file if one was provided. The `log` folder has a copy of the standard out and standard error produced by app-freesurfer. The name convention for these log files are `subjid_-_app-freesurfer_-_jobname_-_timestamp.out` and `subjid_-_app-freesurfer_-_jobname_-_timestamp.err`, for the App's standard output and standard error, and `subjid_-_config_-_jobname_-_timestamp.json` and  `subjid_-_expert_-_jobname_-_timestamp.opts` for the `config.json` and `expert.opts` files, respectively. For example, `bert_-_app-freesurfer_-_example_-_20210407095730UTC.out`, `bert_-_app-freesurfer_-_example_-_20210407095730UTC.err`, `bert_-_config_-_example_-_20210407095730UTC.json`, and `bert_-_expert_-_example_-_20210407095730UTC.opts`. The `metadata` folder has all configuration, expert options, and log files produced by the given job instance. This metadata folder is also conveniently saved at the data root directory:

```bash
/data
  └── metadata
       └── app-freesurfer
             └── jobs
                  └── example
                      └─ 20210407095730UTC
                              ├── subjects.txt
                              ├── etc
                              └── log
```
The file `subjects.txt` has the list of the subject id's processed in that particular job instance.

## Troubleshoot

If `$ app-freesurfer --help` doesn't work out of the box, please source `app.conf` again by executing:
```bash
$ source $HOME/app-freesurfer/etc/app.conf
```

And/or add the following line to your `$HOME/.profile`:
```bash
export PATH=$HOME/app-freesurfer/bin:$PATH
```

## Recommendations

Place your expert options file, if any, in the same path as `json.conf` for the sake of organization. A backup copy with the name `expert.opts` is saved inside the log folders.

For the time being, if sharing an installation of app-freesurfer with other users, add your name to the job folder if possible as a preventive measure from others (re-)running your job by mistake. You can also change your job folders permission. Security measures are planned to be implemented in a future release.

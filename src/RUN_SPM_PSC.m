function [] = Run_SPM_PSC(batch_path)
    %everything has to be SINGLE QUOTES
    %make sure images have the structure 
    %make sure to change this directory 
    addpath /ocean/projects/med200002p/shared/spm12/
    disp(batch_path)
    spm_jobman('initcfg')
    spm_jobman('run',batch_path)
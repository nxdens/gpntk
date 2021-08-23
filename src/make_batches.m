function x = make_batches(subjects,studydir,batchdir,step_names)
    study_dir = studydir;
    subject_list = subjects; 
    save_dir = batchdir;
    disp(study_dir)
    disp(subject_list)
    disp(save_dir)
    % set gpntoolkit path
    gpn_toolkit_path = '/ocean/projects/med200002p/shared/GPN_Toolbox/'
    addpath(gpn_toolkit_path)

    proc_dir = '/step05_Encoding/';
    numVol = 270;
    fname = 'Encoding';
    steps = split(step_name)

    % Motion correction
    clearvars -except study_dir subject_list proc_dir save_dir numVol fname;
    image = [proc_dir '*' fname '.nii'];
    type_flag = 0;
    save_path = [save_dir steps(1)]; mkdir(save_path);
    GPN_realign(study_dir,subject_list,image,numVol,type_flag,save_path);
end
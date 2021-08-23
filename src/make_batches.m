function x = make_batches(subjects,studydir,batchdir,step_names)
    study_dir = char(studydir);
    subject_list = char(subjects); 
    save_dir = char(batchdir);
    % paths must end in /
    disp(study_dir)
    disp(subject_list)
    disp(save_dir)
    % set gpntoolkit path
    gpn_toolkit_path = '/ocean/projects/med200002p/shared/GPN_Toolbox/';
    addpath(gpn_toolkit_path)

    proc_dir = '/step05_Encoding/';
    numVol = 270;
    fname = 'Encoding';
    steps = split(step_names);

    % Motion correction
    image = [proc_dir '*' fname '.nii'];
    type_flag = 0;
    save_path = [save_dir char(steps(1))]; mkdir(save_path);
    GPN_realign(study_dir,subject_list,image,numVol,type_flag,save_path);
end
function wids_submission_atomic_save(path,payload)
%WIDS_SUBMISSION_ATOMIC_SAVE Replace a checkpoint only after saving succeeds.
folder=fileparts(path);
if ~isfolder(folder),mkdir(folder);end
temporary=[tempname(char(folder)),'.mat'];
save(temporary,'-struct','payload','-v7.3');
movefile(temporary,path,'f');
end

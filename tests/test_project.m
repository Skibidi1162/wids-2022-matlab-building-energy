function test_project()
%TEST_PROJECT Check checksum bytes, shared resolution, and history leakage.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);setup_wids_project;
originalMode=getenv('WIDS_CHECKSUM_MODE');
restoreMode=onCleanup(@()setenv('WIDS_CHECKSUM_MODE',originalMode));
originalData=getenv('WIDS_DATA_DIR');
restoreData=onCleanup(@()setenv('WIDS_DATA_DIR',originalData));
setenv('WIDS_DATA_DIR','');assert(wids_data_dir()==string(fullfile(root,'data')));
setenv('WIDS_DATA_DIR',originalData);
setenv('WIDS_CHECKSUM_MODE','strict');
path=[tempname,'.bin'];removeFile=onCleanup(@()delete(path));
fid=fopen(path,'wb');assert(fid>=0);fwrite(fid,uint8('abc'),'uint8');fclose(fid);
if usejava('jvm')
assert(strcmp(wids_sha256(path), ...
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));
fid=fopen(path,'wb');fwrite(fid,uint8(0:255),'uint8');fclose(fid);
assert(strcmp(wids_sha256(path), ...
    '40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880'));
fid=fopen(path,'wb');fclose(fid);
assert(strcmp(wids_sha256(path), ...
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
else
    refused=false;
    try,wids_sha256(path);catch problem,refused=strcmp(problem.identifier,'WiDS:ChecksumJVM');end
    assert(refused,'Strict mode must refuse execution without Java.');
    fprintf('No configured JVM: SHA256 vectors skipped; testing metadata fallback and strict refusal.\n');
end
setenv('WIDS_CHECKSUM_MODE','off');assert(startsWith(wids_sha256(path),'METADATA_ONLY:'));
setenv('WIDS_CHECKSUM_MODE','optional');assert(~isempty(wids_sha256(path)));
for name=["wids_clean_split","wids_past_building_features","wids_encode","wids_sha256"]
    assert(strcmp(which(name),wids_shared_file(name+".m")));
end
check_building_history_logic;
fprintf('Project tests passed: available checksum modes, shared paths, history leakage.\n');
end

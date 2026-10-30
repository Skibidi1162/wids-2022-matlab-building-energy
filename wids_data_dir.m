function folder = wids_data_dir()
%WIDS_DATA_DIR Data location from WIDS_DATA_DIR or this repository's data folder.
folder = string(getenv('WIDS_DATA_DIR'));
if strlength(folder)==0
    folder = string(fullfile(fileparts(mfilename('fullpath')),'data'));
end
assert(isfolder(folder),'WiDS:DataFolder','Create the data folder or set WIDS_DATA_DIR.');
end

function path = wids_shared_file(name)
%WIDS_SHARED_FILE Resolve the single canonical copy of a shared helper.
path=fullfile(fileparts(mfilename('fullpath')),char(name));
assert(isfile(path),'WiDS:SharedFile','Shared file not found: %s',path);
end

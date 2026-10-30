function file = wids_data_file(name)
%WIDS_DATA_FILE Resolve a user-supplied competition input without modifying it.
file = fullfile(wids_data_dir(),string(name));
assert(isfile(file),'WiDS:DataFile','Download the competition input first: %s',file);
end

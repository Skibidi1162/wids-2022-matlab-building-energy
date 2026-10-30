function path = wids_source_file(workflowFolder,name)
%WIDS_SOURCE_FILE Resolve fingerprint sources without duplicate helper copies.
shared=fullfile(fileparts(mfilename('fullpath')),char(name));
if isfile(shared),path=shared;else,path=fullfile(workflowFolder,char(name));end
assert(isfile(path),'WiDS:SourceFile','Source file not found: %s',path);
end

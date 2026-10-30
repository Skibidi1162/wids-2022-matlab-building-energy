function digest = wids_sha256(path)
%WIDS_SHA256 Stream a file through Java SHA256 on any MATLAB platform.
% WIDS_CHECKSUM_MODE: optional (default), strict (requires JVM), or off.
persistent warned
assert(isfile(path),'WiDS:ChecksumFile','File not found: %s',path);
mode=lower(string(getenv('WIDS_CHECKSUM_MODE')));
if strlength(mode)==0,mode="optional";end
assert(ismember(mode,["strict","optional","off"]),'WiDS:ChecksumMode', ...
    'WIDS_CHECKSUM_MODE must be strict, optional, or off.');
if mode=="off" || (~usejava('jvm') && mode=="optional")
    info=dir(path);
    digest=sprintf('METADATA_ONLY:%.0f:%.15g',info.bytes,info.datenum);
    if isempty(warned)
        warning('WiDS:ChecksumDisabled', ...
            'SHA256 unavailable or off. Using file size/time; same-size/time edits cannot be detected.');
        warned=true;
    end
    return
end
assert(usejava('jvm'),'WiDS:ChecksumJVM', ...
    'SHA256 requires a JVM. Set WIDS_CHECKSUM_MODE=optional to run without checksums.');
engine=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
fid=fopen(path,'rb');assert(fid>=0,'WiDS:ChecksumRead','Cannot read %s',path);
closeFile=onCleanup(@()fclose(fid));
while true
    block=fread(fid,1048576,'*uint8');
    if isempty(block),break,end
    engine.update(typecast(block(:),'int8'));
end
bytes=typecast(engine.digest(),'uint8');
digest=lower(reshape(dec2hex(bytes,2).',1,[]));
end

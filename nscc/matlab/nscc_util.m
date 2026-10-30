function out = nscc_util(action, varargin)
%NSCC_UTIL Small portable helpers. No parallel pool or GPU initialization.
switch action
    case 'root'
        out = fileparts(fileparts(mfilename('fullpath')));
    case 'readjson'
        out = jsondecode(fileread(varargin{1}));
    case 'writejson'
        path = char(varargin{1});
        tmp = [path '.tmp'];
        fid = fopen(tmp, 'w');
        assert(fid >= 0, 'WiDS:IO', 'Cannot write %s', tmp);
        closer = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', jsonencode(varargin{2}, 'PrettyPrint', true));
        clear closer
        [ok,msg] = movefile(tmp,path,'f');
        assert(ok, 'WiDS:IO', '%s', msg);
        out = path;
    case 'savemat'
        path = char(varargin{1});
        payload = varargin{2}; %#ok<NASGU>
        tmp = [path '.tmp.mat'];
        save(tmp, 'payload', '-v7.3');
        [ok,msg] = movefile(tmp,path,'f');
        assert(ok, 'WiDS:IO', '%s', msg);
        out = path;
    case 'loadmat'
        s = load(varargin{1}, 'payload');
        out = s.payload;
    case 'sha256'
        fid = fopen(varargin{1}, 'rb');
        assert(fid >= 0, 'WiDS:IO', 'Cannot read %s', varargin{1});
        closer = onCleanup(@() fclose(fid));
        md = java.security.MessageDigest.getInstance('SHA-256');
        while ~feof(fid)
            bytes = fread(fid, 1048576, '*uint8');
            md.update(typecast(bytes, 'int8'));
        end
        out = lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
    case 'verify'
        root = nscc_util('root');
        lines = splitlines(string(fileread(fullfile(root,'SHA256SUMS'))));
        for k = 1:numel(lines)
            line = char(lines(k));
            if isempty(line), continue; end
            assert(numel(line)>66 && strcmp(line(65:66),'  '), ...
                'WiDS:Integrity','Invalid checksum record.');
            path = fullfile(root,strrep(line(67:end),'/',filesep));
            assert(strcmp(nscc_util('sha256',path),line(1:64)), ...
                'WiDS:Integrity','Checksum mismatch: %s',path);
        end
        out = nscc_util('sha256',fullfile(root,'SHA256SUMS'));
    case 'runroot'
        tag = getenv('WIDS_RUN_TAG');
        assert(~isempty(regexp(tag,'^[A-Za-z0-9_-]+$','once')), ...
            'WiDS:RunTag','Set WIDS_RUN_TAG to a simple, unique run name.');
        out = fullfile(nscc_util('root'),'results',tag);
        if ~isfolder(out), mkdir(out); end
    case 'context'
        out = struct;
        out.PackageSHA256 = nscc_util('verify');
        expected = getenv('WIDS_EXPECTED_PACKAGE');
        assert(strcmp(expected,out.PackageSHA256),'WiDS:Integrity', ...
            'Package differs from rendered PBS job; verify and render again.');
        out.MATLABVersion = version;
        out.MATLABRelease = version('-release');
        out.Architecture = computer('arch');
        v = ver('stats');
        if isempty(v), out.StatsVersion = ''; else, out.StatsVersion = v.Version; end
        out.RunTag = getenv('WIDS_RUN_TAG');
        out.Threads = str2double(getenv('WIDS_MAX_THREADS'));
        assert(isfinite(out.Threads) && out.Threads>=1 && ...
            out.Threads==fix(out.Threads),'WiDS:Threads','Invalid thread limit.');
    case 'timestamp'
        out = char(datetime('now','TimeZone','UTC', ...
            'Format',"yyyy-MM-dd'T'HH:mm:ss'Z'"));
    otherwise
        error('WiDS:Action','Unknown helper action %s.',action);
end
end

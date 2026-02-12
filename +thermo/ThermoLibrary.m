classdef ThermoLibrary < handle
    properties
        speciesMap containers.Map
        dataPath string
    end

    methods
        function obj = ThermoLibrary(dataPath)
            if nargin < 1 || strlength(string(dataPath)) == 0
                dataPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'library', 'thermo', 'species_shomate.json');
            end
            obj.dataPath = string(dataPath);
            obj.speciesMap = containers.Map('KeyType','char','ValueType','any');
            obj.loadFromFile(obj.dataPath);
        end

        function loadFromFile(obj, dataPath)
            if ~isfile(dataPath)
                error('Thermo library not found: %s', dataPath);
            end
            txt = fileread(dataPath);
            payload = jsondecode(txt);
            if isfield(payload, 'species')
                sp = payload.species;
            else
                sp = payload;
            end
            if ~isstruct(sp)
                error('Invalid thermo library schema in %s.', dataPath);
            end
            for i = 1:numel(sp)
                s = sp(i);
                key = lower(strtrim(s.name));
                obj.speciesMap(key) = s;
            end
        end

        function sp = getSpecies(obj, name)
            key = lower(strtrim(string(name)));
            if ~isKey(obj.speciesMap, char(key))
                error('Missing thermo for species "%s".', string(name));
            end
            sp = thermo.ShomateSpecies(obj.speciesMap(char(key)));
        end

        function mix = makeMixture(obj, speciesNames, z)
            mix = thermo.IdealGasMixture(obj, speciesNames, z);
        end

        function addSpeciesFromNISTShomateText(obj, txt)
            s = thermo.ThermoLibrary.parseNISTShomateText(txt);
            key = lower(strtrim(s.name));
            obj.speciesMap(char(key)) = s;
        end

        function save(obj, outPath)
            if nargin < 2 || strlength(string(outPath)) == 0
                outPath = obj.dataPath;
            end
            keys = obj.speciesMap.keys;
            species = repmat(struct(), 1, numel(keys));
            for i = 1:numel(keys)
                species(i) = obj.speciesMap(keys{i});
            end
            payload = struct('species', species);
            txt = jsonencode(payload, 'PrettyPrint', true);
            fid = fopen(outPath, 'w');
            cleaner = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', txt);
        end
    end

    methods (Static)
        function s = parseNISTShomateText(txt)
            % Expected paste format:
            % Name: CH4
            % Formula: CH4
            % MW: 16.043
            % Range: 298 1300
            % Coeff: A B C D E F G H
            lines = splitlines(string(txt));
            s = struct('name','','formula','','MW',NaN, ...
                'shomate_ranges',struct([]), 'Hf298_kJkmol', NaN, ...
                'S298_kJkmolK', NaN, 'phase_change', struct(), ...
                'source','NIST Shomate', 'notes','');
            ranges = struct([]);
            for i = 1:numel(lines)
                ln = strtrim(lines(i));
                if strlength(ln) == 0, continue; end
                if startsWith(lower(ln), 'name:')
                    s.name = strtrim(extractAfter(ln, ':'));
                elseif startsWith(lower(ln), 'formula:')
                    s.formula = strtrim(extractAfter(ln, ':'));
                elseif startsWith(lower(ln), 'mw:')
                    s.MW = str2double(strtrim(extractAfter(ln, ':')));
                elseif startsWith(lower(ln), 'hf298')
                    s.Hf298_kJkmol = str2double(strtrim(extractAfter(ln, ':')));
                elseif startsWith(lower(ln), 'range:')
                    nums = sscanf(char(extractAfter(ln, ':')), '%f');
                    if numel(nums) ~= 2
                        error('Invalid Range line: %s', ln);
                    end
                    rr = struct('Tmin_K',nums(1),'Tmax_K',nums(2), ...
                        'A',NaN,'B',NaN,'C',NaN,'D',NaN,'E',NaN,'F',NaN,'G',NaN,'H',NaN);
                    ranges = [ranges rr]; %#ok<AGROW>
                elseif startsWith(lower(ln), 'coeff:')
                    nums = sscanf(char(extractAfter(ln, ':')), '%f');
                    if numel(nums) ~= 8
                        error('Coeff must have 8 numbers (A..H): %s', ln);
                    end
                    if isempty(ranges)
                        error('Add Range before Coeff in pasted text.');
                    end
                    ranges(end).A = nums(1); ranges(end).B = nums(2);
                    ranges(end).C = nums(3); ranges(end).D = nums(4);
                    ranges(end).E = nums(5); ranges(end).F = nums(6);
                    ranges(end).G = nums(7); ranges(end).H = nums(8);
                end
            end
            if strlength(s.name) == 0 || isempty(ranges)
                error('Failed to parse NIST text: missing Name or Range/Coeff data.');
            end
            s.shomate_ranges = ranges;
        end
    end
end

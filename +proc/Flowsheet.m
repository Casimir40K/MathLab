classdef Flowsheet < handle
    properties
        species   % cellstr species list (global order)
        streams   % cell array of Stream objects
        units     % cell array of unit objects
    end

    methods
        function obj = Flowsheet(species)
            obj.species = species;
            obj.streams = {};
            obj.units = {};
        end

        function addStream(obj, s)
            obj.streams{end+1} = s;
        end

        function addUnit(obj, u)
            obj.units{end+1} = u;
        end

        function [nUnknown, nEq] = checkDOF(obj)
            % Counts unknowns (based on Stream.known if present, else NaN)
            % and counts number of equations contributed by all units.
            nUnknown = obj.countUnknowns();
            nEq = obj.countEquations();

            fprintf('DOF check:\n');
            fprintf('  Unknowns:  %d\n', nUnknown);
            fprintf('  Equations: %d\n', nEq);

            if nEq < nUnknown
                fprintf('  Status: UNDER-CONSTRAINED (need %d more equations/specs)\n', nUnknown - nEq);
            elseif nEq > nUnknown
                fprintf('  Status: OVER-CONSTRAINED (have %d extra equations)\n', nEq - nUnknown);
            else
                fprintf('  Status: Square (unknowns == equations)\n');
            end
        end

        function solver = solve(obj, varargin)
            % Usage:
            %   solver = fs.solve();
            %   solver = fs.solve('maxIter',80,'tolAbs',1e-9,'verbose',true);
            
            obj.validate();
            solver = ProcessSolver(obj.streams, obj.units);

            % Optional overrides
            for k = 1:2:numel(varargin)
                name = varargin{k};
                val  = varargin{k+1};
                if isprop(solver, name)
                    solver.(name) = val;
                else
                    error('ProcessSolver has no property "%s"', name);
                end
            end

            obj.checkDOF();
            solver.solve();
        end

        function T = streamTable(obj)
            % Table including: name, n_dot, T, P, y_i, and species molar flows n_i = n_dot*y_i
            N = numel(obj.streams);
            ns = numel(obj.species);

            names = strings(N,1);
            n_dot = nan(N,1);
            TT    = nan(N,1);
            PP    = nan(N,1);
            Y     = nan(N,ns);
            Ni    = nan(N,ns);

            for i = 1:N
                s = obj.streams{i};
                names(i) = string(s.name);
                n_dot(i) = s.n_dot;
                TT(i)    = s.T;
                PP(i)    = s.P;
                Y(i,:)   = s.y(:).';
                Ni(i,:)  = s.n_dot .* s.y(:).';
            end

            T = table(names, n_dot, TT, PP);

            % y columns
            for j = 1:ns
                T.(sprintf('y_%s', obj.species{j})) = Y(:,j);
            end

            % species molar flow columns
            for j = 1:ns
                T.(sprintf('n_%s', obj.species{j})) = Ni(:,j);
            end
        end
    end

    methods (Access = private)
        function n = countUnknowns(obj)
            ns = numel(obj.species);
            n = 0;

            for si = 1:numel(obj.streams)
                s = obj.streams{si};

                % n_dot
                if isUnknownField(s, 'n_dot')
                    n = n + 1;
                end

                % T
                if isUnknownField(s, 'T')
                    n = n + 1;
                end

                % P
                if isUnknownField(s, 'P')
                    n = n + 1;
                end

                % y
                if hasKnownY(s)
                    % count unknown components
                    for j = 1:ns
                        if ~s.known.y(j)
                            n = n + 1;
                        end
                    end
                else
                    % no known flags: treat NaNs as unknown; if no NaNs, treat as guess (unknown)
                    if any(isnan(s.y))
                        n = n + sum(isnan(s.y));
                    else
                        % your physical solver treats any non-known y as unknown (uses softmax)
                        n = n + ns;
                    end
                end
            end

            function tf = isUnknownField(st, fieldName)
                if isprop(st,'known') && isfield(st.known, fieldName)
                    tf = ~st.known.(fieldName);
                else
                    tf = isnan(st.(fieldName));
                end
            end

            function tf = hasKnownY(st)
                tf = isprop(st,'known') && isfield(st.known,'y') && numel(st.known.y)==ns;
            end
        end

        function nEq = countEquations(obj)
            % Count total number of scalar equations returned by unit.equations()
            nEq = 0;
            for u = 1:numel(obj.units)
                ru = obj.units{u}.equations();
                nEq = nEq + numel(ru);
            end
        end

        function validate(obj)
            % Throws an error with a readable message if the model is not runnable.
        
            if isempty(obj.streams)
                error('Flowsheet has no streams.');
            end
            if isempty(obj.units)
                error('Flowsheet has no units.');
            end
        
            % species consistency
            ns = numel(obj.species);
        
            % Stream checks
            for i = 1:numel(obj.streams)
                s = obj.streams{i};
        
                if ~isprop(s,'name')
                    error('Stream #%d has no name property.', i);
                end
        
                % Check y vector
                if isempty(s.y) || numel(s.y) ~= ns
                    error('Stream "%s": y must be length %d.', string(s.name), ns);
                end
                if any(~isfinite(s.y))
                    error('Stream "%s": y contains NaN/Inf.', string(s.name));
                end
                if any(s.y < 0)
                    error('Stream "%s": y contains negative entries.', string(s.name));
                end
                sy = sum(s.y);
                if abs(sy - 1) > 1e-6
                    error('Stream "%s": y must sum to 1 (currently %.6g).', string(s.name), sy);
                end
        
                % Scalars
                if ~isfinite(s.n_dot) || s.n_dot <= 0
                    error('Stream "%s": n_dot must be finite and > 0 (currently %.6g).', string(s.name), s.n_dot);
                end
                if ~isfinite(s.T) || s.T <= 0
                    error('Stream "%s": T must be finite and > 0 (currently %.6g).', string(s.name), s.T);
                end
                if ~isfinite(s.P) || s.P <= 0
                    error('Stream "%s": P must be finite and > 0 (currently %.6g).', string(s.name), s.P);
                end
        
                % known flags sanity (optional but helpful)
                if ~isprop(s,'known') || ~isstruct(s.known)
                    error('Stream "%s": missing known struct. Ensure Stream constructor initializes known.*', string(s.name));
                end
                req = {'n_dot','T','P','y'};
                for f = req
                    if ~isfield(s.known, f{1})
                        error('Stream "%s": known.%s missing. Ensure Stream constructor initializes it.', string(s.name), f{1});
                    end
                end
                if ~islogical(s.known.n_dot) || ~isscalar(s.known.n_dot)
                    error('Stream "%s": known.n_dot must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.T) || ~isscalar(s.known.T)
                    error('Stream "%s": known.T must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.P) || ~isscalar(s.known.P)
                    error('Stream "%s": known.P must be logical scalar.', string(s.name));
                end
                if ~islogical(s.known.y) || numel(s.known.y) ~= ns
                    error('Stream "%s": known.y must be logical(1,%d).', string(s.name), ns);
                end
            end
        
            % Unit checks (lightweight)
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                if ~ismethod(unit, 'equations')
                    error('Unit #%d (%s) has no equations() method.', u, class(unit));
                end
                % Try calling equations once to ensure it returns finite numbers
                ru = unit.equations();
                if isempty(ru)
                    error('Unit #%d (%s): equations() returned empty.', u, class(unit));
                end
                if any(~isfinite(ru(:)))
                    error('Unit #%d (%s): equations() returned NaN/Inf. Check connectivity/initial guesses.', u, class(unit));
                end
            end
        
            % DOF check
            [nU, nE] = obj.checkDOF();
            if nU ~= nE
                warning('Flowsheet DOF not square: unknowns=%d, eqs=%d. Solver may still run (LM), but check specs.', nU, nE);
            end
        end
    end
end

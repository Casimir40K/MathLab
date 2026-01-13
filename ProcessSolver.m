classdef ProcessSolver < handle
    properties
        streams      % Cell array of Stream objects
        units        % Cell array of Unit objects (Link, Mixer, Reactor, etc.)
        nspecies     % Number of species in the system
        solver_opts  % Options for fsolve or custom solver
    end
    
    methods
        function obj = ProcessSolver(streams, units)
            obj.streams = streams;
            obj.units = units;
            obj.nspecies = length(streams{1}.y);  % assume all streams have same species
            %obj.solver_opts = optimoptions('fsolve', 'Display','iter','FunctionTolerance',1e-12);
        end
        
        function X0 = buildInitialGuess(obj)
            % Build initial guess vector from current streams
            % Order: [S1.n_dot, S1.y(1:nspecies), S1.T, S1.P, S2.n_dot, ...]
            X0 = [];
            for s = 1:length(obj.streams)
                stream = obj.streams{s};
                if isempty(stream.n_dot)
                    X0(end+1) = 1;  % default guess
                else
                    X0(end+1) = stream.n_dot;
                end
                for j = 1:obj.nspecies
                    if isempty(stream.y)
                        X0(end+1) = 1/obj.nspecies;
                    else
                        X0(end+1) = stream.y(j);
                    end
                end
                if isempty(stream.T)
                    X0(end+1) = 300;
                else
                    X0(end+1) = stream.T;
                end
                if isempty(stream.P)
                    X0(end+1) = 1e5;
                else
                    X0(end+1) = stream.P;
                end
            end
        end
        
        function updateStreamsFromX(obj, X)
            % Update all stream objects from unknown vector X
            idx = 1;
            for s = 1:length(obj.streams)
                stream = obj.streams{s};
                stream.n_dot = X(idx); idx = idx + 1;
                for j = 1:obj.nspecies
                    stream.y(j) = X(idx); idx = idx + 1;
                end
                stream.T = X(idx); idx = idx + 1;
                stream.P = X(idx); idx = idx + 1;
            end
        end
        
        function R = residuals(obj, X)
            % Update streams
            obj.updateStreamsFromX(X);
            
            % Stack residuals from all units
            R = [];
            for u = 1:length(obj.units)
                R = [R; obj.units{u}.equations()];
            end
        end
        
        function solve(obj)
            % Solve the full process
            X0 = obj.buildInitialGuess();
            % Use fsolve
            [Xsol, ~, exitflag] = fsolve(@(X)obj.residuals(X), X0);
            
            if exitflag <= 0
                warning('Solver did not converge');
            end
            
            % Update streams with solution
            obj.updateStreamsFromX(Xsol);
        end
        
        function T = generateStreamTable(obj)
            % Create a MATLAB table with all stream properties
            N = length(obj.streams);
            T = table();
            species_names = strcat('Species_', string(1:obj.nspecies));
            for s = 1:N
                st = obj.streams{s};
                T.Name{s}   = st.name;
                T.n_dot(s)  = st.n_dot;
                T.T(s)      = st.T;
                T.P(s)      = st.P;
                % Add species fractions as columns
                for j = 1:obj.nspecies
                    T.(species_names(j))(s) = st.y(j);
                end
            end
        end
    end
end

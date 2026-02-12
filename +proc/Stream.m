classdef Stream < handle
    properties
        name
        species
        n_dot
        T
        P
        y
        known
        thermoLib  % optional thermo.ThermoLibrary
    end

    methods
        function obj = Stream(name, species)
            obj.name = name;
            obj.species = species;

            ns = numel(species);

            % Default values (guesses can overwrite)
            obj.n_dot = 1;
            obj.T     = 300;
            obj.P     = 1e5;
            obj.y     = ones(1, ns) / ns;

            % Default "unknown" flags
            obj.known = struct();
            obj.known.n_dot = false;
            obj.known.T     = false;
            obj.known.P     = false;
            obj.known.y     = false(1, ns);

            obj.thermoLib = proc.Stream.defaultThermoLibrary();
        end

        function setKnown(obj, field, value)
            % Convenience: set a field value and mark it known
            if strcmp(field, 'y')
                obj.y = value;
                obj.known.y(:) = true;
            else
                obj.(field) = value;
                obj.known.(field) = true;
            end
        end

        function setGuess(obj, n_dot, y, T, P)
            % Set initial guesses without marking known
            if nargin >= 2 && ~isempty(n_dot), obj.n_dot = n_dot; end
            if nargin >= 3 && ~isempty(y),     obj.y = y;         end
            if nargin >= 4 && ~isempty(T),     obj.T = T;         end
            if nargin >= 5 && ~isempty(P),     obj.P = P;         end
        end

        function z = getZ(obj)
            z = obj.y(:);
            z = max(z, 0);
            s = sum(z);
            if ~isfinite(s) || s <= 0
                z = ones(size(z)) / numel(z);
            else
                z = z ./ s;
            end
        end

        function mix = getMixture(obj)
            if isempty(obj.thermoLib)
                obj.thermoLib = proc.Stream.defaultThermoLibrary();
            end
            mix = thermo.IdealGasMixture(obj.thermoLib, obj.species, obj.getZ());
        end

        function cp = cp(obj, T)
            if nargin < 2 || isempty(T), T = obj.T; end
            cp = obj.getMixture().cp_molar_kJkmolK(T);
        end

        function h = h(obj, T, varargin)
            if nargin < 2 || isempty(T), T = obj.T; end
            mode = 'sensible';
            if ~isempty(varargin), mode = varargin{1}; end
            h = obj.getMixture().h_molar_kJkmol(T, mode);
        end

        function s = s(obj, T, P)
            if nargin < 2 || isempty(T), T = obj.T; end
            if nargin < 3 || isempty(P), P = obj.P; end
            s = obj.getMixture().s_molar_kJkmolK(T, P/1000);
        end

        function g = gamma(obj, T)
            if nargin < 2 || isempty(T), T = obj.T; end
            g = obj.getMixture().gamma(T);
        end
    end

    methods (Static)
        function setDefaultThermoLibrary(lib)
            persistent defaultLib
            defaultLib = lib;
        end

        function lib = defaultThermoLibrary()
            persistent defaultLib
            if isempty(defaultLib)
                try
                    defaultLib = thermo.ThermoLibrary();
                catch
                    defaultLib = [];
                end
            end
            lib = defaultLib;
        end
    end
end

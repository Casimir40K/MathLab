classdef Stream < handle
    properties
        name
        species
        n_dot
        T
        P
        y
        known
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
        end

        function setKnown(obj, field, value)
            % Convenience: set a field value and mark it known
            %   s.setKnown('n_dot', 10)
            %   s.setKnown('T', 300)
            %   s.setKnown('y', [0.8 0.2 0])
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
            %   s.setGuess(10, [0.8 0.2 0])
            %   s.setGuess(10, [0.8 0.2 0], 400, 2e5)
            if nargin >= 2 && ~isempty(n_dot), obj.n_dot = n_dot; end
            if nargin >= 3 && ~isempty(y),     obj.y = y;         end
            if nargin >= 4 && ~isempty(T),     obj.T = T;         end
            if nargin >= 5 && ~isempty(P),     obj.P = P;         end
        end
    end
end

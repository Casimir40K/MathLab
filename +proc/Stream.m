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
            obj.n_dot = NaN;
            obj.T     = NaN;
            obj.P     = NaN;
            obj.y     = NaN(1, ns);

            % NEW: default "unknown" flags (this is the key)
            ns = numel(species);
            obj.known = struct();
            obj.known.n_dot = false;
            obj.known.T     = false;
            obj.known.P     = false;
            obj.known.y     = false(1, ns);
        end
    end
end

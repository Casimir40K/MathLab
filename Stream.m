classdef Stream < handle
    properties
        name                    % string identifier

        species                 % cell array of species names
        n_dot                   % total molar flow [mol/s]
        T                       % temperature [K]
        P                       % pressure [Pa]
        y                       % mole fractions

        known                   % struct of known/unknown flags
    end

    methods
        function obj = Stream(name, species)
            % Constructor (runs when you create a Stream)

            obj.name = name;
            obj.species = species;

            % Unknowns default to NaN
            obj.n_dot = NaN;
            obj.T = NaN;
            obj.P = NaN;
            obj.y = NaN(1, numel(species));

            % Track what is specified
            obj.known.n_dot = false;
            obj.known.T = false;
            obj.known.P = false;
            obj.known.y = false(1, numel(species));
        end
    end
end

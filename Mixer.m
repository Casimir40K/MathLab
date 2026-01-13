classdef Mixer < handle
    properties
        inlets  % cell array of inlet streams
        outlet  % single outlet stream
    end

    methods
        function obj = Mixer(inlets, outlet)
            % Constructor
            % inlets = cell array of Stream objects
            % outlet = Stream object
            obj.inlets = inlets;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            eqs = [];

            % Total molar flow
            total_n_in = 0;
            for i = 1:length(obj.inlets)
                total_n_in = total_n_in + obj.inlets{i}.n_dot;
            end
            eqs(end+1) = obj.outlet.n_dot - total_n_in;

            % Species balances
            nspecies = length(obj.outlet.y);
            for j = 1:nspecies
                total_species_in = 0;
                for i = 1:length(obj.inlets)
                    total_species_in = total_species_in + obj.inlets{i}.n_dot * obj.inlets{i}.y(j);
                end
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(j) - total_species_in;
            end
        end
    end
end

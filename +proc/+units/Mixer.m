classdef Mixer < handle
    properties
        inlets  % cell array of inlet streams
        outlet  % single outlet stream
    end

    methods
        function obj = Mixer(inlets, outlet)
            obj.inlets = inlets;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            eqs = [];
        
            nspecies = length(obj.outlet.y);
        
            % Total molar flow balance (independent closure)
            total_in = 0;
            for i = 1:length(obj.inlets)
                total_in = total_in + obj.inlets{i}.n_dot;
            end
            eqs(end+1) = obj.outlet.n_dot - total_in;
        
            % Independent component balances: only nspecies-1
            % The last component balance is implied by (total balance + normalization)
            for j = 1:(nspecies-1)
                total_species_in = 0;
                for i = 1:length(obj.inlets)
                    total_species_in = total_species_in + obj.inlets{i}.n_dot * obj.inlets{i}.y(j);
                end
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(j) - total_species_in;
            end
        
            % Mechanical/thermal closure: match first inlet (adiabatic/isobaric assumption)
            eqs(end+1) = obj.outlet.T - obj.inlets{1}.T;
            eqs(end+1) = obj.outlet.P - obj.inlets{1}.P;
        end

        function str = describe(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            str = sprintf('Mixer: {%s} -> %s', strjoin(inNames, ', '), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            inNames = cellfun(@(s) char(string(s.name)), obj.inlets, 'Uni', false);
            names = [inNames, {char(string(obj.outlet.name))}];
        end
    end
end

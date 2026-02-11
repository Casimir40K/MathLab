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

            % Independence rationale:
            % - Use component-flow balances (n_dot*y) as the primary conservation equations.
            % - Do NOT add a separate total-flow equation here because it is implied by
            %   summing the component balances when stream compositions are normalized.
            % - Keep only physically intended closure relations (T/P matching assumption).
            %
            % This keeps the mixer equation set free of avoidable dependent constraints.

            % Component molar balances as primary conserved equations
            nspecies = length(obj.outlet.y);
            for j = 1:nspecies
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

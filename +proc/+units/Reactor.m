classdef Reactor < handle
    properties
        inlet      % Stream object
        outlet     % Stream object
        reactions  % struct array with fields: reactants, products, stoich, name
        conversion % fraction of limiting reactant reacted (0-1)
    end

    methods
        function obj = Reactor(inlet, outlet, reactions, conversion)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.reactions = reactions;
            obj.conversion = conversion;
        end

        function eqs = equations(obj)
            eqs = [];
            nspecies = length(obj.outlet.y);

            % Step 1: Copy inlet moles
            n_species = obj.inlet.n_dot * obj.inlet.y;

            % Step 2: Apply reactions
            for r = 1:length(obj.reactions)
                rxn = obj.reactions(r);

                % Limiting reactant (stoich-adjusted)
                limiting_n = inf;
                for i = 1:length(rxn.reactants)
                    idx = rxn.reactants(i);
                    limiting_n = min(limiting_n, n_species(idx)/abs(rxn.stoich(idx)));
                end

                % Extent of reaction
                xi = obj.conversion * limiting_n;

                % Update species moles
                for i = 1:length(rxn.reactants)
                    idx = rxn.reactants(i);
                    n_species(idx) = n_species(idx) + rxn.stoich(idx) * xi;
                end
                for i = 1:length(rxn.products)
                    idx = rxn.products(i);
                    n_species(idx) = n_species(idx) + rxn.stoich(idx) * xi;
                end
            end

            % Step 3: Compute total moles and mole fractions
            n_out = sum(n_species);
            y_out = n_species / n_out;

            % Step 4: Build residuals
            eqs(end+1) = obj.outlet.n_dot - n_out;
            for j = 1:nspecies
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(j) - n_out * y_out(j);
            end
            eqs(end+1) = obj.outlet.T - obj.inlet.T;
            eqs(end+1) = obj.outlet.P - obj.inlet.P;
        end

        function str = describe(obj)
            if isfield(obj.reactions, 'name') && ~isempty(obj.reactions(1).name)
                rxnName = obj.reactions(1).name;
            else
                rxnName = "reaction";
            end
            str = sprintf('Reactor: %s -> %s (X=%.2f, %s)', ...
                string(obj.inlet.name), string(obj.outlet.name), ...
                obj.conversion, rxnName);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

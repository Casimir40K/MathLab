classdef Separator < handle
    properties
        inlet      % Stream object
        outletA    % Stream object (e.g. gas / recycle)
        outletB    % Stream object (e.g. liquid / product)
        phi        % split fraction to outletA for each species (0..1), size = nspecies
        includeNormalizationConstraints logical = true
    end

    methods
        function obj = Separator(inlet, outletA, outletB, phi)
            obj.inlet   = inlet;
            obj.outletA = outletA;
            obj.outletB = outletB;
            obj.phi     = phi(:).';
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);

            % Component split equations
            for i = 1:ns
                eqs(end+1) = obj.outletA.n_dot * obj.outletA.y(i) ...
                          - obj.phi(i) * obj.inlet.n_dot * obj.inlet.y(i);
                eqs(end+1) = obj.outletB.n_dot * obj.outletB.y(i) ...
                          - (1 - obj.phi(i)) * obj.inlet.n_dot * obj.inlet.y(i);
            end

            % Mole fraction sum constraints (optional; can be redundant if y is parameterized)
            if obj.includeNormalizationConstraints
                eqs(end+1) = sum(obj.outletA.y) - 1;
                eqs(end+1) = sum(obj.outletB.y) - 1;
            end


            % T/P pass-through
            eqs(end+1) = obj.outletA.T - obj.inlet.T;
            eqs(end+1) = obj.outletB.T - obj.inlet.T;
            eqs(end+1) = obj.outletA.P - obj.inlet.P;
            eqs(end+1) = obj.outletB.P - obj.inlet.P;
        end

        function str = describe(obj)
            str = sprintf('Separator: %s -> %s, %s (phi=%s)', ...
                string(obj.inlet.name), string(obj.outletA.name), ...
                string(obj.outletB.name), mat2str(obj.phi, 3));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.outletA.name)), ...
                     char(string(obj.outletB.name))};
        end
    end
end

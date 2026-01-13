classdef Link < handle
    properties
        inlet
        outlet
    end

    methods
        function obj = Link(inlet, outlet)
            % Constructor
            obj.inlet = inlet;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            eqs = [];

            % Total molar flow
            eqs(end+1) = obj.outlet.n_dot - obj.inlet.n_dot;

            % Temperature
            eqs(end+1) = obj.outlet.T - obj.inlet.T;

            % Pressure
            eqs(end+1) = obj.outlet.P - obj.inlet.P;

            % Species mole fractions
            for i = 1:numel(obj.inlet.y)
                eqs(end+1) = obj.outlet.y(i) - obj.inlet.y(i);
            end
        end
    end
end

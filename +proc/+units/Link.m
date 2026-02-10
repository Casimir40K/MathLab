classdef Link < handle
    properties
        inlet
        outlet
    end

    methods
        function obj = Link(inlet, outlet)
            obj.inlet = inlet;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            eqs = [];
            eqs(end+1) = obj.outlet.n_dot - obj.inlet.n_dot;
            eqs(end+1) = obj.outlet.T - obj.inlet.T;
            eqs(end+1) = obj.outlet.P - obj.inlet.P;
            for i = 1:numel(obj.inlet.y)
                eqs(end+1) = obj.outlet.y(i) - obj.inlet.y(i);
            end
        end

        function str = describe(obj)
            str = sprintf('Link: %s -> %s', string(obj.inlet.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

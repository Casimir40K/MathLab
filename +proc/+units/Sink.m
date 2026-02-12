classdef Sink < handle
    %SINK Terminal sink block (1 inlet, 0 outlets). Adds no residuals.
    properties
        inlet
    end

    methods
        function obj = Sink(inlet)
            obj.inlet = inlet;
        end

        function eqs = equations(~)
            eqs = [];
        end

        function str = describe(obj)
            str = sprintf('Sink: %s ->', string(obj.inlet.name));
        end
    end
end

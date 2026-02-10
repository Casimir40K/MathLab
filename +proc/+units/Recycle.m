classdef Recycle < handle
    properties
        source   % Stream object (calculated stream in loop)
        tear     % Stream object (explicit tear stream guess)
    end

    methods
        function obj = Recycle(source, tear)
            obj.source = source;
            obj.tear = tear;
        end

        function eqs = equations(obj)
            eqs = [];
            eqs(end+1) = obj.tear.n_dot - obj.source.n_dot;
            for i = 1:numel(obj.source.y)
                eqs(end+1) = obj.tear.y(i) - obj.source.y(i);
            end
        end

        function str = describe(obj)
            str = sprintf('Recycle: %s -> tear %s', string(obj.source.name), string(obj.tear.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.source.name)), char(string(obj.tear.name))};
        end
    end
end

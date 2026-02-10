classdef Constraint < handle
    %CONSTRAINT Equality-only constraint: selected variable - value = 0.
    properties
        owner
        field char = ''
        index double = NaN
        value double = 0
    end

    methods
        function obj = Constraint(owner, field, value, index)
            if nargin >= 1, obj.owner = owner; end
            if nargin >= 2, obj.field = char(field); end
            if nargin >= 3, obj.value = value; end
            if nargin >= 4, obj.index = index; end
        end

        function eqs = equations(obj)
            v = obj.owner.(obj.field);
            if ~isnan(obj.index)
                v = v(obj.index);
            end
            eqs = v - obj.value;
        end

        function str = describe(obj)
            str = sprintf('Constraint: %s = %.6g', obj.field, obj.value);
        end
    end
end

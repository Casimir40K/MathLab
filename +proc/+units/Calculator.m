classdef Calculator < handle
    %CALCULATOR One algebraic equation using two values and an operator.
    properties
        lhsOwner
        lhsField char = ''
        lhsIndex double = NaN

        aOwner
        aField char = ''
        aIndex double = NaN

        bOwner
        bField char = ''
        bIndex double = NaN

        operator char = '+'   % + - * /
    end

    methods
        function obj = Calculator(lhsOwner, lhsField, aOwner, aField, operator, bOwner, bField)
            if nargin >= 1, obj.lhsOwner = lhsOwner; end
            if nargin >= 2, obj.lhsField = char(lhsField); end
            if nargin >= 3, obj.aOwner = aOwner; end
            if nargin >= 4, obj.aField = char(aField); end
            if nargin >= 5, obj.operator = char(operator); end
            if nargin >= 6, obj.bOwner = bOwner; end
            if nargin >= 7, obj.bField = char(bField); end
        end

        function eqs = equations(obj)
            lhs = obj.getValue(obj.lhsOwner, obj.lhsField, obj.lhsIndex);
            a = obj.getValue(obj.aOwner, obj.aField, obj.aIndex);
            b = obj.getValue(obj.bOwner, obj.bField, obj.bIndex);
            switch obj.operator
                case '+'
                    rhs = a + b;
                case '-'
                    rhs = a - b;
                case '*'
                    rhs = a * b;
                case '/'
                    rhs = a / b;
                otherwise
                    error('Calculator operator must be one of + - * /.');
            end
            eqs = lhs - rhs;
        end

        function str = describe(obj)
            str = sprintf('Calculator: %s = a %s b', obj.lhsField, obj.operator);
        end
    end

    methods (Access = private)
        function v = getValue(~, owner, field, idx)
            if ~isprop(owner, field)
                error('Calculator field "%s" not available on %s.', field, class(owner));
            end
            raw = owner.(field);
            if isnan(idx)
                v = raw;
            else
                v = raw(idx);
            end
        end
    end
end

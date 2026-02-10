classdef Adjust < handle
    %ADJUST Manipulate one variable to satisfy one DesignSpec residual.
    % The manipulated variable is packed into solver unknowns via unknownSpecs().
    properties
        targetSpec proc.units.DesignSpec
        variableOwner
        variableField char = ''
        variableIndex double = NaN
        minValue double = -Inf
        maxValue double = Inf
        initialValue double = NaN
    end

    methods
        function obj = Adjust(designSpec, owner, field, index, minValue, maxValue)
            if nargin >= 1, obj.targetSpec = designSpec; end
            if nargin >= 2, obj.variableOwner = owner; end
            if nargin >= 3, obj.variableField = char(field); end
            if nargin >= 4 && ~isempty(index), obj.variableIndex = index; end
            if nargin >= 5, obj.minValue = minValue; end
            if nargin >= 6, obj.maxValue = maxValue; end
            if ~isempty(obj.targetSpec)
                obj.targetSpec.enabled = false;
            end
        end

        function eqs = equations(obj)
            if isempty(obj.targetSpec)
                error('Adjust block is missing DesignSpec targetSpec.');
            end
            eqs = obj.targetSpec.residual();
        end

        function specs = unknownSpecs(obj)
            specs = struct('owner', obj.variableOwner, ...
                           'field', obj.variableField, ...
                           'index', obj.variableIndex, ...
                           'lower', obj.minValue, ...
                           'upper', obj.maxValue, ...
                           'initial', obj.getVariableValue());
            if isfinite(obj.initialValue)
                specs.initial = obj.initialValue;
            end
        end

        function str = describe(obj)
            str = sprintf('Adjust: %s.%s -> %s', class(obj.variableOwner), obj.variableField, obj.targetSpec.metric);
        end

        function v = getVariableValue(obj)
            if ~isprop(obj.variableOwner, obj.variableField)
                error('Adjust variable field "%s" not found on %s.', obj.variableField, class(obj.variableOwner));
            end
            base = obj.variableOwner.(obj.variableField);
            if isnan(obj.variableIndex)
                v = base;
            else
                v = base(obj.variableIndex);
            end
        end

        function setVariableValue(obj, v)
            v = min(max(v, obj.minValue), obj.maxValue);
            if isnan(obj.variableIndex)
                obj.variableOwner.(obj.variableField) = v;
            else
                arr = obj.variableOwner.(obj.variableField);
                arr(obj.variableIndex) = v;
                obj.variableOwner.(obj.variableField) = arr;
            end
        end
    end
end

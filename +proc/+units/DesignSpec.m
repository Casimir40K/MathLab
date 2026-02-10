classdef DesignSpec < handle
    %DESIGNSPEC One target equation: metric(stream) - target = 0.
    properties
        stream
        metric char = 'total_flow'    % total_flow | comp_flow | mole_fraction
        componentIndex double = 1
        target double = 0
        enabled logical = true
    end

    methods
        function obj = DesignSpec(stream, metric, target, componentIndex)
            if nargin >= 1, obj.stream = stream; end
            if nargin >= 2, obj.metric = char(metric); end
            if nargin >= 3, obj.target = target; end
            if nargin >= 4, obj.componentIndex = componentIndex; end
        end

        function eqs = equations(obj)
            if ~obj.enabled
                eqs = [];
                return;
            end
            eqs = obj.residual();
        end

        function r = residual(obj)
            r = obj.metricValue() - obj.target;
        end

        function v = metricValue(obj)
            if isempty(obj.stream)
                error('DesignSpec has no stream configured.');
            end
            switch lower(strtrim(obj.metric))
                case {'total_flow','n_dot','totalflow'}
                    v = obj.stream.n_dot;
                case {'comp_flow','component_flow','n_i'}
                    i = obj.componentIndex;
                    obj.validateComponentIndex(i);
                    v = obj.stream.n_dot * obj.stream.y(i);
                case {'mole_fraction','y','x_i'}
                    i = obj.componentIndex;
                    obj.validateComponentIndex(i);
                    v = obj.stream.y(i);
                otherwise
                    error('DesignSpec metric "%s" not available.', obj.metric);
            end
        end

        function str = describe(obj)
            str = sprintf('DesignSpec: %s on %s = %.6g', obj.metric, string(obj.stream.name), obj.target);
        end
    end

    methods (Access = private)
        function validateComponentIndex(obj, i)
            if ~(isscalar(i) && i >= 1 && i <= numel(obj.stream.y) && floor(i) == i)
                error('DesignSpec componentIndex must be integer in [1,%d].', numel(obj.stream.y));
            end
        end
    end
end

classdef Source < handle
    %SOURCE Fixed-spec stream source block (0 inlets, 1 outlet).
    % Adds equations only for user-selected outlet specifications.
    properties
        outlet
        totalFlow double = NaN            % optional scalar n_dot spec
        componentFlows double = []        % optional vector n_i specs (NaN = unspecified)
        composition double = []           % optional y_i specs (NaN = unspecified)
        specifyT logical = false
        specifyP logical = false
        T double = NaN
        P double = NaN
    end

    methods
        function obj = Source(outlet, varargin)
            obj.outlet = outlet;
            if nargin >= 2 && isstruct(varargin{1})
                s = varargin{1};
                f = fieldnames(s);
                for i = 1:numel(f)
                    if isprop(obj, f{i})
                        obj.(f{i}) = s.(f{i});
                    end
                end
            end
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.outlet.y);

            if ~isempty(obj.componentFlows)
                if numel(obj.componentFlows) ~= ns
                    error('Source %s: componentFlows must match species count.', string(obj.outlet.name));
                end
                for i = 1:ns
                    if ~isnan(obj.componentFlows(i))
                        eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(i) - obj.componentFlows(i); %#ok<AGROW>
                    end
                end
            end

            if ~isnan(obj.totalFlow)
                eqs(end+1) = obj.outlet.n_dot - obj.totalFlow; %#ok<AGROW>
            end

            if ~isempty(obj.composition)
                if numel(obj.composition) ~= ns
                    error('Source %s: composition must match species count.', string(obj.outlet.name));
                end
                for i = 1:ns
                    if ~isnan(obj.composition(i))
                        eqs(end+1) = obj.outlet.y(i) - obj.composition(i); %#ok<AGROW>
                    end
                end
            end

            if obj.specifyT && isfinite(obj.T)
                eqs(end+1) = obj.outlet.T - obj.T; %#ok<AGROW>
            end
            if obj.specifyP && isfinite(obj.P)
                eqs(end+1) = obj.outlet.P - obj.P; %#ok<AGROW>
            end
        end

        function str = describe(obj)
            str = sprintf('Source: -> %s', string(obj.outlet.name));
        end
    end
end

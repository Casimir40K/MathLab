classdef Splitter < handle
    properties
        inlet                 % Stream object
        outlets               % cell array of outlet Stream objects
        splitFractions        % optional row vector (1 x nOut), sums to 1
        specifiedOutletFlows  % optional row vector (1 x nOut), NaN means unspecified
    end

    methods
        function obj = Splitter(inlet, outlets, varargin)
            obj.inlet = inlet;
            obj.outlets = outlets;
            obj.splitFractions = [];
            obj.specifiedOutletFlows = [];

            if nargin < 3 || isempty(varargin)
                nOut = numel(outlets);
                obj.splitFractions = ones(1, nOut) / nOut;
                return;
            end

            mode = lower(string(varargin{1}));
            vals = varargin{2};
            switch mode
                case "fractions"
                    obj.splitFractions = vals(:).';
                case "flows"
                    obj.specifiedOutletFlows = vals(:).';
                otherwise
                    error('Splitter mode must be "fractions" or "flows".');
            end
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);
            nOut = numel(obj.outlets);

            if ~isempty(obj.splitFractions)
                f = obj.splitFractions;
                for k = 1:nOut
                    out = obj.outlets{k};
                    eqs(end+1) = out.n_dot - f(k) * obj.inlet.n_dot;
                    for i = 1:ns
                        eqs(end+1) = out.y(i) - obj.inlet.y(i);
                    end
                end
            else
                q = obj.specifiedOutletFlows;
                knownMask = ~isnan(q);
                for k = 1:nOut
                    out = obj.outlets{k};
                    if knownMask(k)
                        eqs(end+1) = out.n_dot - q(k);
                    end
                    for i = 1:ns
                        eqs(end+1) = out.y(i) - obj.inlet.y(i);
                    end
                end
                eqs(end+1) = sum(cellfun(@(s) s.n_dot, obj.outlets)) - obj.inlet.n_dot;
            end
        end

        function str = describe(obj)
            outNames = cellfun(@(s) char(string(s.name)), obj.outlets, 'Uni', false);
            str = sprintf('Splitter: %s -> {%s}', string(obj.inlet.name), strjoin(outNames, ', '));
        end

        function names = streamNames(obj)
            outNames = cellfun(@(s) char(string(s.name)), obj.outlets, 'Uni', false);
            names = [{char(string(obj.inlet.name))}, outNames];
        end
    end
end

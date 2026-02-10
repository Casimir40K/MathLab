classdef YieldReactor < handle
    %YIELDREACTOR Mass-only deterministic yield/selectivity reactor.
    % Basis reactant A is consumed by conversion X. Products are formed via
    % user-defined yields: n_P,out = n_P,in + Y_P * (n_A,in - n_A,out)
    properties
        inlet
        outlet
        basisSpecies (1,1) double = 1
        conversion double = 0.5
        conversionMode char = 'fixed'     % 'fixed' or 'solve'
        productSpecies double = []
        productYields double = []
        negativeTol double = 1e-10
        warnOnNegative logical = true
    end

    properties (Access = private)
        didWarnNegative logical = false
    end

    methods
        function obj = YieldReactor(inlet, outlet, basisSpecies, conversion, productSpecies, productYields, varargin)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.basisSpecies = basisSpecies;
            if nargin >= 4
                obj.conversion = conversion;
            end
            if nargin >= 6
                obj.productSpecies = productSpecies(:);
                obj.productYields = productYields(:);
            end

            p = inputParser;
            p.addParameter('conversionMode', 'fixed', @ischar);
            p.parse(varargin{:});
            obj.conversionMode = lower(strtrim(p.Results.conversionMode));
        end

        function eqs = equations(obj)
            if numel(obj.productSpecies) ~= numel(obj.productYields)
                error('YieldReactor: productSpecies and productYields must have the same length.');
            end

            nIn = obj.inlet.n_dot * obj.inlet.y(:);
            nOutVar = obj.outlet.n_dot * obj.outlet.y(:);
            a = obj.basisSpecies;

            if strcmp(obj.conversionMode, 'solve')
                X = 1 - nOutVar(a) / max(nIn(a), eps);
            else
                X = obj.conversion;
            end

            nAOut = nIn(a) * (1 - X);
            consumedA = nIn(a) - nAOut;

            nTarget = nIn;
            nTarget(a) = nAOut;
            for k = 1:numel(obj.productSpecies)
                pIdx = obj.productSpecies(k);
                nTarget(pIdx) = nTarget(pIdx) + obj.productYields(k) * consumedA;
            end

            if obj.warnOnNegative && any(nTarget < -obj.negativeTol) && ~obj.didWarnNegative
                warning('YieldReactor:NegativeComponentFlow', ...
                    'Predicted outlet component flow is negative for stream "%s".', string(obj.outlet.name));
                obj.didWarnNegative = true;
            end

            eqs = [nOutVar - nTarget; obj.outlet.n_dot - sum(nTarget); ...
                obj.outlet.T - obj.inlet.T; obj.outlet.P - obj.inlet.P];
        end

        function str = describe(obj)
            str = sprintf('YieldReactor: %s -> %s (%s X)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.conversionMode);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

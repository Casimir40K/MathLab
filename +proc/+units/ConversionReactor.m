classdef ConversionReactor < handle
    %CONVERSIONREACTOR Mass-only reactor with limiting-reactant conversion.
    %   xi = X * n_in(key) / (-nu_key), n_out = n_in + nu*xi
    properties
        inlet
        outlet
        nu double
        keySpecies (1,1) double = 1
        conversion double = 0.5
        conversionMode char = 'fixed'      % 'fixed' or 'solve'
        negativeTol double = 1e-10
        warnOnNegative logical = true
    end

    properties (Access = private)
        didWarnNegative logical = false
    end

    methods
        function obj = ConversionReactor(inlet, outlet, nu, keySpecies, conversion, varargin)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.nu = nu(:);
            obj.keySpecies = keySpecies;
            if nargin >= 5
                obj.conversion = conversion;
            end

            p = inputParser;
            p.addParameter('conversionMode', 'fixed', @ischar);
            p.parse(varargin{:});
            obj.conversionMode = lower(strtrim(p.Results.conversionMode));
        end

        function eqs = equations(obj)
            nIn = obj.inlet.n_dot * obj.inlet.y(:);
            nOutVar = obj.outlet.n_dot * obj.outlet.y(:);

            j = obj.keySpecies;
            nuKey = obj.nu(j);
            if nuKey >= 0
                error('ConversionReactor: keySpecies must be a reactant with negative nu.');
            end

            if strcmp(obj.conversionMode, 'solve')
                denom = max(nIn(j), eps);
                X = (nIn(j) - nOutVar(j)) / denom;
            else
                X = obj.conversion;
            end
            xi = X * nIn(j) / (-nuKey);
            nTarget = nIn + obj.nu * xi;

            if obj.warnOnNegative && any(nTarget < -obj.negativeTol) && ~obj.didWarnNegative
                warning('ConversionReactor:NegativeComponentFlow', ...
                    'Predicted outlet component flow is negative for stream "%s".', string(obj.outlet.name));
                obj.didWarnNegative = true;
            end

            eqs = [nOutVar - nTarget; obj.outlet.n_dot - sum(nTarget); ...
                obj.outlet.T - obj.inlet.T; obj.outlet.P - obj.inlet.P];
        end

        function str = describe(obj)
            str = sprintf('ConversionReactor: %s -> %s (%s X)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.conversionMode);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

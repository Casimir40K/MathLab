classdef StoichiometricReactor < handle
    %STOICHIOMETRICREACTOR Mass-only reactor with stoichiometric extent model.
    %   n_out = n_in + nu * xi
    properties
        inlet
        outlet
        nu double
        extent double = 0
        extentMode char = 'fixed'          % 'fixed' or 'solve'
        referenceSpecies (1,1) double = 1  % used when extentMode='solve'
        negativeTol double = 1e-10
        warnOnNegative logical = true
    end

    properties (Access = private)
        didWarnNegative logical = false
    end

    methods
        function obj = StoichiometricReactor(inlet, outlet, nu, varargin)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.nu = nu(:);

            p = inputParser;
            p.addParameter('extent', 0, @isnumeric);
            p.addParameter('extentMode', 'fixed', @ischar);
            p.addParameter('referenceSpecies', 1, @isnumeric);
            p.parse(varargin{:});

            obj.extent = p.Results.extent;
            obj.extentMode = lower(strtrim(p.Results.extentMode));
            obj.referenceSpecies = p.Results.referenceSpecies;
        end

        function eqs = equations(obj)
            nIn = obj.inlet.n_dot * obj.inlet.y(:);
            nOutVar = obj.outlet.n_dot * obj.outlet.y(:);

            if strcmp(obj.extentMode, 'solve')
                j = obj.referenceSpecies;
                if abs(obj.nu(j)) < eps
                    error('StoichiometricReactor: referenceSpecies must have nonzero stoichiometric coefficient.');
                end
                xi = (nOutVar(j) - nIn(j)) / obj.nu(j);
            else
                xi = obj.extent;
            end

            nTarget = nIn + obj.nu * xi;

            if obj.warnOnNegative && any(nTarget < -obj.negativeTol) && ~obj.didWarnNegative
                warning('StoichiometricReactor:NegativeComponentFlow', ...
                    'Predicted outlet component flow is negative for stream "%s".', string(obj.outlet.name));
                obj.didWarnNegative = true;
            end

            eqs = [nOutVar - nTarget; obj.outlet.n_dot - sum(nTarget); ...
                obj.outlet.T - obj.inlet.T; obj.outlet.P - obj.inlet.P];
        end

        function str = describe(obj)
            str = sprintf('StoichiometricReactor: %s -> %s (%s extent)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.extentMode);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

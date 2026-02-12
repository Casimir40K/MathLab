classdef EquilibriumReactor < handle
    %EQUILIBRIUMREACTOR Mass-action-only equilibrium reactor (ideal activity).
    %   Single reaction with stoichiometry nu and equilibrium constant Keq.
    %   Activities are mole fractions with epsilon floor.
    properties
        inlet
        outlet
        nu double
        Keq double = 1
        referenceSpecies (1,1) double = 1
        epsilon double = 1e-12
    end

    methods
        function obj = EquilibriumReactor(inlet, outlet, nu, Keq, varargin)
            obj.inlet = inlet;
            obj.outlet = outlet;
            obj.nu = nu(:);
            if nargin >= 4
                obj.Keq = Keq;
            end

            p = inputParser;
            p.addParameter('referenceSpecies', 1, @isnumeric);
            p.addParameter('epsilon', 1e-12, @isnumeric);
            p.parse(varargin{:});
            obj.referenceSpecies = p.Results.referenceSpecies;
            obj.epsilon = p.Results.epsilon;
        end

        function eqs = equations(obj)
            if obj.Keq <= 0
                error('EquilibriumReactor: Keq must be positive.');
            end

            nIn = obj.inlet.n_dot * obj.inlet.y(:);
            nOutVar = obj.outlet.n_dot * obj.outlet.y(:);

            j = obj.referenceSpecies;
            if abs(obj.nu(j)) < eps
                error('EquilibriumReactor: referenceSpecies must have nonzero stoichiometric coefficient.');
            end
            xi = (nOutVar(j) - nIn(j)) / obj.nu(j);
            nTarget = nIn + obj.nu * xi;

            yAct = max(obj.outlet.y(:), obj.epsilon);
            lnQ = sum(obj.nu .* log(yAct));
            eqMassAction = lnQ - log(obj.Keq);

            eqs = [nOutVar - nTarget; eqMassAction; obj.outlet.T - obj.inlet.T; obj.outlet.P - obj.inlet.P];
        end

        function str = describe(obj)
            str = sprintf('EquilibriumReactor: %s -> %s (K=%.3g)', ...
                string(obj.inlet.name), string(obj.outlet.name), obj.Keq);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

classdef Heater < handle
    %HEATER Single-stream heater (increases temperature).
    %
    %   Specification modes (set exactly one):
    %     'Tout' — outlet temperature [K] specified
    %     'duty' — heat duty Q [kW] specified (Q > 0 = heat added)
    %
    %   Pressure modes (set at most one; default is pass-through):
    %     'dP'   — pressure change [Pa], Pout = Pin + dP
    %     'Pout' — outlet pressure [Pa]
    %     'PR'   — pressure ratio Pout/Pin
    %
    %   Equations (ns+2 total):
    %     - ns component balances (pass-through)
    %     - 1 pressure specification
    %     - 1 energy/temperature equation
    %
    %   Units: T [K], P [Pa], Q [kW], n_dot [kmol/s].

    properties
        inlet               % proc.Stream
        outlet              % proc.Stream
        thermoMix           % thermo.IdealGasMixture

        Tout        double = NaN    % outlet temperature [K]
        duty        double = NaN    % heat duty [kW] (Q > 0 = heating)

        dP          double = NaN    % pressure change [Pa]
        Pout        double = NaN    % outlet pressure [Pa]
        PR          double = NaN    % pressure ratio Pout/Pin
    end

    methods
        function obj = Heater(inlet, outlet, thermoMix, varargin)
            obj.inlet     = inlet;
            obj.outlet    = outlet;
            obj.thermoMix = thermoMix;
            for k = 1:2:numel(varargin)
                if isprop(obj, varargin{k})
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
            obj.validateSpecs();
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);
            y_in = obj.inlet.y(:);
            y_out = obj.outlet.y(:);

            % Residual indices:
            %   1:ns   -> component balances
            %   ns+1   -> pressure
            %   ns+2   -> energy/temperature specification
            %
            % Component balances (all species):
            %   n_out*y_out(i) - n_in*y_in(i) = 0
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot * y_out(i) ...
                           - obj.inlet.n_dot * y_in(i);
            end

            Pspec = obj.resolvedOutletPressure();
            eqs(end+1) = obj.outlet.P - Pspec;

            z_in = y_in.';

            if isfinite(obj.Tout)
                % Temperature spec: outlet T must equal Tout
                eqs(end+1) = obj.outlet.T - obj.Tout;
            elseif isfinite(obj.duty)
                % Duty spec: Q = n_dot * (h_out - h_in)
                h_in  = obj.thermoMix.h_mix_sensible(obj.inlet.T, z_in);
                h_out = obj.thermoMix.h_mix_sensible(obj.outlet.T, z_in);
                eqs(end+1) = obj.duty - obj.inlet.n_dot * (h_out - h_in);
            else
                error('Heater: must specify exactly one of Tout or duty.');
            end
        end

        function labels = equationLabels(obj)
            ns = numel(obj.inlet.y);
            labels = strings(ns + 2, 1);
            for i = 1:ns
                labels(i) = sprintf('Heater %s->%s residual(%d): n_out*y_out(%d) - n_in*y_in(%d)', ...
                    string(obj.inlet.name), string(obj.outlet.name), i, i, i);
            end
            if isfinite(obj.dP)
                pLabel = 'P_out - (P_in + dP)';
            elseif isfinite(obj.Pout)
                pLabel = 'P_out - P_spec';
            elseif isfinite(obj.PR)
                pLabel = 'P_out - PR*P_in';
            else
                pLabel = 'P_out - P_in';
            end
            labels(ns+1) = sprintf('Heater %s->%s residual(%d): %s', ...
                string(obj.inlet.name), string(obj.outlet.name), ns+1, pLabel);
            if isfinite(obj.Tout)
                labels(ns+2) = sprintf('Heater %s->%s residual(%d): T_out - T_spec', ...
                    string(obj.inlet.name), string(obj.outlet.name), ns+2);
            elseif isfinite(obj.duty)
                labels(ns+2) = sprintf('Heater %s->%s residual(%d): duty - n_in*(h_out-h_in)', ...
                    string(obj.inlet.name), string(obj.outlet.name), ns+2);
            else
                labels(ns+2) = sprintf('Heater %s->%s residual(%d): energy/temperature spec (unset)', ...
                    string(obj.inlet.name), string(obj.outlet.name), ns+2);
            end
        end

        function Q = getDuty(obj)
            %GETDUTY Compute duty [kW] from current stream states.
            z = obj.inlet.y(:)';
            h_in  = obj.thermoMix.h_mix_sensible(obj.inlet.T, z);
            h_out = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            Q = obj.inlet.n_dot * (h_out - h_in);
        end

        function str = describe(obj)
            str = sprintf('Heater: %s -> %s', ...
                string(obj.inlet.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end

        function validateSpecs(obj)
            tModes = [isfinite(obj.Tout), isfinite(obj.duty)];
            if nnz(tModes) ~= 1
                error('Heater: specify exactly one thermal mode (Tout or duty).');
            end

            pModes = [isfinite(obj.dP), isfinite(obj.Pout), isfinite(obj.PR)];
            if nnz(pModes) > 1
                error('Heater: specify at most one pressure mode (dP, Pout, or PR).');
            end
            if isfinite(obj.Pout) && obj.Pout <= 0
                error('Heater: Pout must be > 0 Pa.');
            end
            if isfinite(obj.PR) && obj.PR <= 0
                error('Heater: PR must be > 0.');
            end
        end

        function Pspec = resolvedOutletPressure(obj)
            obj.validateSpecs();
            if isfinite(obj.dP)
                Pspec = obj.inlet.P + obj.dP;
            elseif isfinite(obj.Pout)
                Pspec = obj.Pout;
            elseif isfinite(obj.PR)
                Pspec = obj.inlet.P * obj.PR;
            else
                Pspec = obj.inlet.P;
            end
            if Pspec <= 0
                error('Heater: resolved outlet pressure must be > 0 Pa.');
            end
        end
    end
end

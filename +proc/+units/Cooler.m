classdef Cooler < handle
    %COOLER Single-stream cooler (decreases temperature).
    %
    %   Specification modes (set exactly one):
    %     'Tout' — outlet temperature [K] specified
    %     'duty' — heat duty Q [kW] specified (Q < 0 = heat removed)
    %
    %   Equations (ns+2 total):
    %     - ns component balances (pass-through)
    %     - 1 pressure pass-through (ΔP = 0)
    %     - 1 energy/temperature equation
    %
    %   Units: T [K], P [Pa], Q [kW], n_dot [kmol/s].

    properties
        inlet               % proc.Stream
        outlet              % proc.Stream
        thermoMix           % proc.thermo.IdealGasMixture

        Tout        double = NaN    % outlet temperature [K]
        duty        double = NaN    % heat duty [kW] (Q < 0 = cooling)
    end

    methods
        function obj = Cooler(inlet, outlet, thermoMix, varargin)
            obj.inlet     = inlet;
            obj.outlet    = outlet;
            obj.thermoMix = thermoMix;
            for k = 1:2:numel(varargin)
                if isprop(obj, varargin{k})
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);

            % Component balances
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(i) ...
                           - obj.inlet.n_dot * obj.inlet.y(i);
            end

            % Pressure pass-through (ΔP = 0)
            eqs(end+1) = obj.outlet.P - obj.inlet.P;

            z = obj.inlet.y(:)';

            if isfinite(obj.Tout)
                % Temperature spec
                eqs(end+1) = obj.outlet.T - obj.Tout;
            elseif isfinite(obj.duty)
                % Duty spec: Q = n_dot * (h_out - h_in), Q < 0 for cooling
                h_in  = obj.thermoMix.h_mix_sensible(obj.inlet.T, z);
                h_out = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
                eqs(end+1) = obj.duty - obj.inlet.n_dot * (h_out - h_in);
            else
                error('Cooler: must specify Tout or duty.');
            end
        end

        function labels = equationLabels(obj)
            ns = numel(obj.inlet.y);
            labels = strings(ns + 2, 1);
            for i = 1:ns
                labels(i) = sprintf('Cooler %s->%s: component %d mole flow', ...
                    string(obj.inlet.name), string(obj.outlet.name), i);
            end
            labels(ns+1) = sprintf('Cooler %s->%s: pressure', ...
                string(obj.inlet.name), string(obj.outlet.name));
            labels(ns+2) = sprintf('Cooler %s->%s: energy', ...
                string(obj.inlet.name), string(obj.outlet.name));
        end

        function Q = getDuty(obj)
            z = obj.inlet.y(:)';
            h_in  = obj.thermoMix.h_mix_sensible(obj.inlet.T, z);
            h_out = obj.thermoMix.h_mix_sensible(obj.outlet.T, z);
            Q = obj.inlet.n_dot * (h_out - h_in);
        end

        function str = describe(obj)
            str = sprintf('Cooler: %s -> %s', ...
                string(obj.inlet.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end
    end
end

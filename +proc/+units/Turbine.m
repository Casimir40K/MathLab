classdef Turbine < handle
    properties
        inlet
        outlet
        mode string = "PoutEta"   % PoutEta | PREta | Power
        Pout = NaN
        PR = NaN
        eta_isentropic = 0.75
        power_kW = NaN              % positive = power produced
    end

    methods
        function obj = Turbine(inlet, outlet, varargin)
            obj.inlet = inlet; obj.outlet = outlet;
            if nargin >= 3
                opts = varargin{1};
                f = fieldnames(opts);
                for i = 1:numel(f), obj.(f{i}) = opts.(f{i}); end
            end
        end

        function eqs = equations(obj)
            eqs = obj.componentCarryOver();
            Pout = obj.resolvePout();
            eqs(end+1) = obj.outlet.P - Pout;

            h1 = obj.inlet.h(obj.inlet.T, 'sensible');
            s1 = obj.inlet.s(obj.inlet.T, obj.inlet.P);
            mix = obj.inlet.getMixture();
            T2s = mix.solveTFromS(s1, Pout/1000);
            h2s = obj.inlet.h(T2s, 'sensible');
            h2target = h1 - max(obj.eta_isentropic,1e-8)*(h1 - h2s);

            h2 = obj.outlet.h(obj.outlet.T, 'sensible');
            switch lower(char(obj.mode))
                case 'power'
                    eqs(end+1) = obj.power_kW - obj.outlet.n_dot*(h1 - h2)/3600;
                otherwise
                    eqs(end+1) = h2 - h2target;
            end
        end

        function str = describe(obj)
            str = sprintf('Turbine: %s -> %s (%s)', string(obj.inlet.name), string(obj.outlet.name), obj.mode);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end

        function Pout = resolvePout(obj)
            switch lower(char(obj.mode))
                case {'pouteta','power'}
                    if ~isfinite(obj.Pout), error('Turbine requires Pout in mode %s.', obj.mode); end
                    Pout = obj.Pout;
                case 'preta'
                    if ~isfinite(obj.PR), error('Turbine PREta mode requires PR.'); end
                    Pout = obj.inlet.P / obj.PR;
                otherwise
                    error('Unknown turbine mode %s', obj.mode);
            end
        end

        function eqs = componentCarryOver(obj)
            ns = numel(obj.inlet.y); eqs = [];
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot*obj.outlet.y(i) - obj.inlet.n_dot*obj.inlet.y(i);
            end
        end
    end
end

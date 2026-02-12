classdef Heater < handle
    properties
        inlet
        outlet
        specMode string = "Tout"   % Tout | Duty
        Tout = NaN
        duty_kW = NaN
    end

    methods
        function obj = Heater(inlet, outlet, varargin)
            obj.inlet = inlet; obj.outlet = outlet;
            if nargin >= 3
                opts = varargin{1};
                f = fieldnames(opts);
                for i = 1:numel(f), obj.(f{i}) = opts.(f{i}); end
            end
        end

        function eqs = equations(obj)
            eqs = obj.componentCarryOver();
            eqs(end+1) = obj.outlet.P - obj.inlet.P;
            hIn = obj.inlet.h(obj.inlet.T, 'sensible');
            hOut = obj.outlet.h(obj.outlet.T, 'sensible');
            switch lower(char(obj.specMode))
                case 'tout'
                    eqs(end+1) = obj.outlet.T - obj.Tout;
                case 'duty'
                    eqs(end+1) = obj.duty_kW - obj.outlet.n_dot*(hOut - hIn)/3600;
                otherwise
                    error('Unknown Heater specMode %s', obj.specMode);
            end
        end

        function str = describe(obj)
            str = sprintf('Heater: %s -> %s (%s)', string(obj.inlet.name), string(obj.outlet.name), obj.specMode);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), char(string(obj.outlet.name))};
        end

        function eqs = componentCarryOver(obj)
            ns = numel(obj.inlet.y); eqs = [];
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot*obj.outlet.y(i) - obj.inlet.n_dot*obj.inlet.y(i);
            end
        end
    end
end

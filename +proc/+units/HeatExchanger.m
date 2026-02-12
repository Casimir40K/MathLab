classdef HeatExchanger < handle
    properties
        hotIn
        hotOut
        coldIn
        coldOut
        Q_kW = 0
        hotOutT = NaN
        coldOutT = NaN
        dutySpecified logical = false
    end

    methods
        function obj = HeatExchanger(hotIn, hotOut, coldIn, coldOut, varargin)
            obj.hotIn = hotIn; obj.hotOut = hotOut;
            obj.coldIn = coldIn; obj.coldOut = coldOut;
            if nargin >= 5
                opts = varargin{1};
                f = fieldnames(opts);
                for i = 1:numel(f), obj.(f{i}) = opts.(f{i}); end
            end
        end

        function eqs = equations(obj)
            eqs = [];
            eqs = [eqs obj.sideCarryOver(obj.hotIn, obj.hotOut)]; %#ok<AGROW>
            eqs = [eqs obj.sideCarryOver(obj.coldIn, obj.coldOut)]; %#ok<AGROW>
            eqs(end+1) = obj.hotOut.P - obj.hotIn.P;
            eqs(end+1) = obj.coldOut.P - obj.coldIn.P;

            hHotIn = obj.hotIn.h(obj.hotIn.T, 'sensible');
            hHotOut = obj.hotOut.h(obj.hotOut.T, 'sensible');
            hColdIn = obj.coldIn.h(obj.coldIn.T, 'sensible');
            hColdOut = obj.coldOut.h(obj.coldOut.T, 'sensible');

            eqs(end+1) = obj.Q_kW + obj.hotOut.n_dot*(hHotOut - hHotIn)/3600;
            eqs(end+1) = -obj.Q_kW + obj.coldOut.n_dot*(hColdOut - hColdIn)/3600;

            if isfinite(obj.hotOutT)
                eqs(end+1) = obj.hotOut.T - obj.hotOutT;
            end
            if isfinite(obj.coldOutT)
                eqs(end+1) = obj.coldOut.T - obj.coldOutT;
            end
            if obj.dutySpecified
                % implicit via Q_kW constant in two energy equations
            end
        end

        function str = describe(obj)
            str = sprintf('HeatExchanger: hot %s->%s, cold %s->%s', ...
                string(obj.hotIn.name), string(obj.hotOut.name), string(obj.coldIn.name), string(obj.coldOut.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.hotIn.name)), char(string(obj.hotOut.name)), char(string(obj.coldIn.name)), char(string(obj.coldOut.name))};
        end

        function eqs = sideCarryOver(~, inS, outS)
            ns = numel(inS.y); eqs = [];
            for i = 1:ns
                eqs(end+1) = outS.n_dot*outS.y(i) - inS.n_dot*inS.y(i);
            end
        end
    end
end

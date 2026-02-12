classdef ShomateSpecies < handle
    %SHOMATESPECIES Species ideal-gas properties from NIST Shomate form.
    % Inputs/outputs:
    %   T [K]
    %   cp [kJ/kmol/K]
    %   h  [kJ/kmol] sensible relative to 298.15 K by default
    %   s  [kJ/kmol/K]

    properties
        data struct
    end

    methods
        function obj = ShomateSpecies(data)
            obj.data = data;
        end

        function cp = cp_molar_kJkmolK(obj, T)
            T = thermo.thermo_utils('validateTemperature', T);
            c = obj.selectRange(T);
            t = T / 1000;
            cp_JmolK = c.A + c.B*t + c.C*t.^2 + c.D*t.^3 + c.E./(t.^2);
            cp = cp_JmolK; % 1 J/mol/K == 1 kJ/kmol/K
        end

        function h = h_molar_kJkmol(obj, T, mode)
            if nargin < 3 || isempty(mode), mode = 'sensible'; end
            T = thermo.thermo_utils('validateTemperature', T);
            c = obj.selectRange(T);
            t = T / 1000;
            H_kJmol = c.A*t + c.B*(t.^2)/2 + c.C*(t.^3)/3 + c.D*(t.^4)/4 - c.E./t + c.F - c.H;
            H_kJkmol = H_kJmol * 1000;
            switch lower(string(mode))
                case "absolute"
                    h = H_kJkmol;
                otherwise
                    h_ref = obj.h_molar_kJkmol(thermo.thermo_utils('constants').Tref_K, 'absolute');
                    h = H_kJkmol - h_ref;
            end
        end

        function s = s_molar_kJkmolK(obj, T)
            T = thermo.thermo_utils('validateTemperature', T);
            c = obj.selectRange(T);
            t = T / 1000;
            S_JmolK = c.A*log(t) + c.B*t + c.C*(t.^2)/2 + c.D*(t.^3)/3 - c.E./(2*t.^2) + c.G;
            s = S_JmolK;
        end

        function c = selectRange(obj, T)
            ranges = obj.data.shomate_ranges;
            for i = 1:numel(ranges)
                if T >= ranges(i).Tmin_K && T <= ranges(i).Tmax_K
                    c = ranges(i);
                    return;
                end
            end
            lo = inf; hi = -inf;
            for i = 1:numel(ranges)
                lo = min(lo, ranges(i).Tmin_K);
                hi = max(hi, ranges(i).Tmax_K);
            end
            error('Species "%s": T=%.2f K outside Shomate ranges [%.2f, %.2f] K.', obj.data.name, T, lo, hi);
        end

        function hf = Hf298_kJkmol(obj)
            if isfield(obj.data, 'Hf298_kJkmol') && ~isempty(obj.data.Hf298_kJkmol)
                hf = obj.data.Hf298_kJkmol;
            else
                hf = NaN;
            end
        end
    end
end

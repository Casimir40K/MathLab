function out = thermo_utils(action, varargin)
%THERMO_UTILS Utility helpers/constants for ideal-gas Shomate thermo.
% Units: kJ/kmol, K, kPa.

switch lower(string(action))
    case "constants"
        out = struct();
        out.R_kJkmolK = 8.314462618;   % kJ/(kmol*K)
        out.P0_kPa = 100;              % 1 bar reference
        out.Tref_K = 298.15;
    case "normalizez"
        z = varargin{1}(:);
        z = max(z, 0);
        s = sum(z);
        if ~isfinite(s) || s <= 0
            out = ones(size(z)) / max(numel(z),1);
        else
            out = z / s;
        end
    case "validatetemperature"
        T = varargin{1};
        if ~isscalar(T) || ~isfinite(T) || T <= 0
            error('Invalid temperature %.6g K. Must be finite and > 0.', T);
        end
        out = T;
    otherwise
        error('Unknown thermo_utils action "%s".', action);
end
end

classdef IdealGasMixture < handle
    properties
        lib thermo.ThermoLibrary
        speciesNames
        z
    end

    methods
        function obj = IdealGasMixture(lib, speciesNames, z)
            obj.lib = lib;
            obj.speciesNames = speciesNames;
            obj.z = thermo.thermo_utils('normalizez', z);
        end

        function cp = cp_molar_kJkmolK(obj, T)
            cp = 0;
            for i = 1:numel(obj.speciesNames)
                cp = cp + obj.z(i) * obj.lib.getSpecies(obj.speciesNames{i}).cp_molar_kJkmolK(T);
            end
        end

        function h = h_molar_kJkmol(obj, T, mode)
            if nargin < 3 || isempty(mode), mode = 'sensible'; end
            h = 0;
            for i = 1:numel(obj.speciesNames)
                sp = obj.lib.getSpecies(obj.speciesNames{i});
                h = h + obj.z(i) * sp.h_molar_kJkmol(T, 'sensible');
                if strcmpi(mode, 'absolute')
                    hf = sp.Hf298_kJkmol();
                    if isfinite(hf)
                        h = h + obj.z(i) * hf;
                    end
                end
            end
        end

        function s = s_molar_kJkmolK(obj, T, P_kPa, includeMixingEntropy)
            if nargin < 4, includeMixingEntropy = false; end
            C = thermo.thermo_utils('constants');
            s = 0;
            for i = 1:numel(obj.speciesNames)
                s = s + obj.z(i) * obj.lib.getSpecies(obj.speciesNames{i}).s_molar_kJkmolK(T);
            end
            s = s - C.R_kJkmolK * log(P_kPa / C.P0_kPa);
            if includeMixingEntropy
                zpos = max(obj.z, eps);
                s = s - C.R_kJkmolK * sum(obj.z .* log(zpos));
            end
        end

        function cv = cv_molar_kJkmolK(obj, T)
            cv = obj.cp_molar_kJkmolK(T) - thermo.thermo_utils('constants').R_kJkmolK;
        end

        function g = gamma(obj, T)
            cp = obj.cp_molar_kJkmolK(T);
            cv = obj.cv_molar_kJkmolK(T);
            g = cp / max(cv, eps);
        end

        function T = solveTFromH(obj, h_target, mode)
            if nargin < 3 || isempty(mode), mode = 'sensible'; end
            f = @(T) obj.h_molar_kJkmol(T, mode) - h_target;
            T = obj.solveWithBracket(f, 150, 4000, 'enthalpy');
        end

        function T = solveTFromS(obj, s_target, P_kPa)
            f = @(T) obj.s_molar_kJkmolK(T, P_kPa) - s_target;
            T = obj.solveWithBracket(f, 150, 4000, 'entropy');
        end

        function T = solveWithBracket(~, f, Tmin, Tmax, label)
            grid = linspace(Tmin, Tmax, 50);
            vals = arrayfun(f, grid);
            if any(~isfinite(vals))
                error('Thermo solve (%s): non-finite function values.', label);
            end
            idx = find(vals(1:end-1).*vals(2:end) <= 0, 1, 'first');
            if isempty(idx)
                [~,k] = min(abs(vals));
                error('Thermo solve (%s): could not bracket root in [%.1f, %.1f] K. Closest residual %.3e at %.2f K.', ...
                    label, Tmin, Tmax, vals(k), grid(k));
            end
            T = fzero(f, [grid(idx), grid(idx+1)]);
        end
    end
end

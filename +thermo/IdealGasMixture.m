classdef IdealGasMixture < handle
    %IDEALGASMIXTURE Ideal-gas mixture thermodynamic property evaluator.
    %
    %   Units:
    %     T in K,  P in Pa,  enthalpy in kJ/kmol,  entropy in kJ/(kmol*K),
    %     cp in kJ/(kmol*K),  MW in kg/kmol.
    %
    %   Reference state: Tref = 298.15 K,  P0 = 1e5 Pa (1 bar).
    %   Ideal-gas mixture: properties are mole-fraction weighted sums.

    properties (Constant)
        Rbar = 8.314462618   % kJ/(kmol*K) — universal gas constant
        Tref = 298.15        % K — reference temperature
        P0   = 1e5           % Pa — standard pressure (1 bar)
    end

    properties
        speciesNames    cell   = {}         % cell of species name strings
        speciesObjects  cell   = {}         % cell of ShomateSpecies handles
        ns              double = 0          % number of species
    end

    methods
        function obj = IdealGasMixture(speciesNames, thermoLib)
            %IDEALGASMIXTURE Construct from species names + ThermoLibrary.
            %   mix = IdealGasMixture({'N2','O2','H2O'}, lib)
            if nargin == 0, return; end
            obj.speciesNames = speciesNames(:)';
            obj.ns = numel(speciesNames);
            obj.speciesObjects = cell(1, obj.ns);
            for i = 1:obj.ns
                obj.speciesObjects{i} = thermoLib.get(speciesNames{i});
            end
        end

        % --- Pure-component accessors (delegate to ShomateSpecies) ---

        function cp = cp_species(obj, idx, T)
            %CP_SPECIES cp [kJ/(kmol*K)] for species index idx at T [K].
            cp = obj.speciesObjects{idx}.cp_molar(T);
        end

        function h = h_species_sensible(obj, idx, T)
            h = obj.speciesObjects{idx}.h_sensible(T);
        end

        function h = h_species_absolute(obj, idx, T)
            h = obj.speciesObjects{idx}.h_absolute(T);
        end

        function s = s_species(obj, idx, T)
            s = obj.speciesObjects{idx}.s_molar(T);
        end

        function mw = MW_species(obj, idx)
            mw = obj.speciesObjects{idx}.MW;
        end

        % --- Mixture properties ---

        function mw = MW_mix(obj, z)
            %MW_MIX Mean molecular weight [kg/kmol].
            mw = 0;
            for i = 1:obj.ns
                mw = mw + z(i) * obj.speciesObjects{i}.MW;
            end
        end

        function cp = cp_mix(obj, T, z)
            %CP_MIX Mixture cp [kJ/(kmol*K)] at T, mole fractions z.
            cp = 0;
            for i = 1:obj.ns
                if z(i) > 0
                    cp = cp + z(i) * obj.speciesObjects{i}.cp_molar(T);
                end
            end
        end

        function h = h_mix_sensible(obj, T, z)
            %H_MIX_SENSIBLE Sensible enthalpy of mixture [kJ/kmol] relative to Tref.
            h = 0;
            for i = 1:obj.ns
                if z(i) > 0
                    h = h + z(i) * obj.speciesObjects{i}.h_sensible(T);
                end
            end
        end

        function h = h_mix_absolute(obj, T, z)
            %H_MIX_ABSOLUTE Absolute enthalpy = sensible + formation [kJ/kmol].
            %   Requires Hf298 for all species; NaN propagates if any missing.
            h = 0;
            for i = 1:obj.ns
                if z(i) > 0
                    h = h + z(i) * obj.speciesObjects{i}.h_absolute(T);
                end
            end
        end

        function s = s_mix(obj, T, P, z)
            %S_MIX Mixture entropy [kJ/(kmol*K)] at T, P, mole fractions z.
            %   s = sum(zi * s_i(T)) - R*ln(P/P0) - R*sum(zi*ln(zi))
            s = 0;
            for i = 1:obj.ns
                if z(i) > 0
                    s = s + z(i) * obj.speciesObjects{i}.s_molar(T);
                    s = s - obj.Rbar * z(i) * log(z(i));  % ideal mixing
                end
            end
            s = s - obj.Rbar * log(P / obj.P0);  % pressure correction
        end

        function cv = cv_mix(obj, T, z)
            %CV_MIX Mixture cv [kJ/(kmol*K)] = cp - R.
            cv = obj.cp_mix(T, z) - obj.Rbar;
        end

        function g = gamma_mix(obj, T, z)
            %GAMMA_MIX Heat capacity ratio cp/cv.
            cp = obj.cp_mix(T, z);
            cv = cp - obj.Rbar;
            g = cp / cv;
        end

        % --- Inverse solvers ---

        function T = solveT_from_h(obj, h_target, z, T_guess)
            %SOLVET_FROM_H Find T such that h_mix_sensible(T,z) = h_target.
            %   Uses fzero with bracketing.
            if nargin < 4, T_guess = 500; end
            f = @(T) obj.h_mix_sensible(T, z) - h_target;

            % Bracket search
            Tlo = 200; Thi = 4500;
            try
                T = fzero(f, [Tlo, Thi]);
            catch
                % Fallback: use guess as starting point
                T = fzero(f, T_guess);
            end
        end

        function T = solveT_isentropic(obj, s_target, P2, z, T_guess)
            %SOLVET_ISENTROPIC Find T2 such that s_mix(T2,P2,z) = s_target.
            if nargin < 5, T_guess = 500; end
            f = @(T) obj.s_mix(T, P2, z) - s_target;

            Tlo = 200; Thi = 4500;
            try
                T = fzero(f, [Tlo, Thi]);
            catch
                T = fzero(f, T_guess);
            end
        end
    end
end

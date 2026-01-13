classdef Mixer < handle
    properties
        inlets  % cell array of inlet streams
        outlet  % single outlet stream
    end

    methods
        function obj = Mixer(inlets, outlet)
            % Constructor
            % inlets = cell array of Stream objects
            % outlet = Stream object
            obj.inlets = inlets;
            obj.outlet = outlet;
        end

        function eqs = equations(obj)
            eqs = [];

            % DEBUG: check inlet/outlet for NaNs
            for ii = 1:numel(obj.inlets)
                st = obj.inlets{ii};
                if any(isnan([st.n_dot, st.T, st.P])) || any(isnan(st.y))
                    fprintf('Mixer inlet %d (%s): n_dot=%g, T=%g, P=%g, y=%s\n', ...
                        ii, string(st.name), st.n_dot, st.T, st.P, mat2str(st.y,5));
                end
            end
            st = obj.outlet;
            if any(isnan([st.n_dot, st.T, st.P])) || any(isnan(st.y))
                fprintf('Mixer outlet (%s): n_dot=%g, T=%g, P=%g, y=%s\n', ...
                    string(st.name), st.n_dot, st.T, st.P, mat2str(st.y,5));
            end


            % Total molar flow
            total_n_in = 0;
            for i = 1:length(obj.inlets)
                total_n_in = total_n_in + obj.inlets{i}.n_dot;
            end
            eqs(end+1) = obj.outlet.n_dot - total_n_in;

            % Species balances
            nspecies = length(obj.outlet.y);
            for j = 1:nspecies
                total_species_in = 0;
                for i = 1:length(obj.inlets)
                    total_species_in = total_species_in + obj.inlets{i}.n_dot * obj.inlets{i}.y(j);
                end
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(j) - total_species_in;
            end

            % --- Simple T/P behaviour (for now: same as first inlet) ---
            eqs(end+1) = obj.outlet.T - obj.inlets{1}.T;
            eqs(end+1) = obj.outlet.P - obj.inlets{1}.P;
        end
    end
end

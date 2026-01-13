classdef Purge < handle
    %PURGE Fixed-fraction purge splitter (Mode A), extendable to Design-Spec (Mode B)
    %
    % Mode A (implemented):
    %   - Split inlet into recycle and purge by a fixed recycle fraction beta (0..1)
    %
    % Future Mode B (planned):
    %   - Treat beta as an unknown (or add an "adjust" variable)
    %   - Add one additional specification equation (purity, recovery, purge flow, etc.)
    %
    % Notes:
    %   - This unit is a component-wise splitter. It does not assume equilibrium.
    %   - Outlet compositions follow inlet composition unless solver finds otherwise.
    %   - T and P are passed through (like Link/Separator do in your current framework).

    properties
        inlet       % Stream
        recycle     % Stream (goes back to process)
        purge       % Stream (leaves the process)

        beta        % recycle fraction (Mode A). 0..1. Fraction of each component to recycle.

        % --- Reserved for Mode B extension ---
        mode = "fixed"     % "fixed" (Mode A) or "spec" (Mode B later)
        % specFcn = []      % function handle or object defining design spec residual (Mode B)
        % betaKnown = true  % if false, beta becomes an unknown (Mode B)
    end

    methods
        function obj = Purge(inlet, recycle, purge, beta)
            obj.inlet = inlet;
            obj.recycle = recycle;
            obj.purge = purge;
            obj.beta = beta;
        end

        function eqs = equations(obj)
            eqs = [];

            ns = numel(obj.inlet.y);

            % --- Mode A: fixed split fraction ---
            % Component-wise split:
            % recycle.n_dot * recycle.y(i) = beta * inlet.n_dot * inlet.y(i)
            % purge.n_dot   * purge.y(i)   = (1-beta) * inlet.n_dot * inlet.y(i)
            b = obj.beta;

            for i = 1:ns
                eqs(end+1) = obj.recycle.n_dot * obj.recycle.y(i) ...
                          - b * obj.inlet.n_dot * obj.inlet.y(i);

                eqs(end+1) = obj.purge.n_dot * obj.purge.y(i) ...
                          - (1 - b) * obj.inlet.n_dot * obj.inlet.y(i);
            end

            % Mole fraction normalization constraints
            eqs(end+1) = sum(obj.recycle.y) - 1;
            eqs(end+1) = sum(obj.purge.y) - 1;

            % Simple T/P behaviour (pass-through)
            eqs(end+1) = obj.recycle.T - obj.inlet.T;
            eqs(end+1) = obj.purge.T   - obj.inlet.T;
            eqs(end+1) = obj.recycle.P - obj.inlet.P;
            eqs(end+1) = obj.purge.P   - obj.inlet.P;

            % --- Placeholder for Mode B (future) ---
            % if obj.mode == "spec"
            %    % 1) Add an equation to enforce a design spec (purity/recovery/purge flow)
            %    % 2) Make beta an unknown variable (handled by ProcessSolver packing)
            %    % eqs(end+1) = obj.specFcn(...);  % design spec residual
            % end
        end

        function setFixed(obj, beta)
            % Convenience: switch back to Mode A
            obj.mode = "fixed";
            obj.beta = beta;
        end

        % Future extension idea:
        % function setSpec(obj, specFcn)
        %     obj.mode = "spec";
        %     obj.specFcn = specFcn;
        % end
    end
end

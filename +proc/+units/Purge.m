classdef Purge < handle
    properties
        inlet       % Stream
        recycle     % Stream (goes back to process)
        purge       % Stream (leaves the process)
        beta        % recycle fraction (0..1)
        mode = "fixed"
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
            b = obj.beta;

            % Component-wise split
            for i = 1:ns
                eqs(end+1) = obj.recycle.n_dot * obj.recycle.y(i) ...
                          - b * obj.inlet.n_dot * obj.inlet.y(i);
                eqs(end+1) = obj.purge.n_dot * obj.purge.y(i) ...
                          - (1 - b) * obj.inlet.n_dot * obj.inlet.y(i);
            end

            % Mole fraction normalization
            eqs(end+1) = sum(obj.recycle.y) - 1;
            eqs(end+1) = sum(obj.purge.y) - 1;

            % T/P pass-through
            eqs(end+1) = obj.recycle.T - obj.inlet.T;
            eqs(end+1) = obj.purge.T   - obj.inlet.T;
            eqs(end+1) = obj.recycle.P - obj.inlet.P;
            eqs(end+1) = obj.purge.P   - obj.inlet.P;
        end

        function setFixed(obj, beta)
            obj.mode = "fixed";
            obj.beta = beta;
        end

        function str = describe(obj)
            str = sprintf('Purge: %s -> recycle=%s, purge=%s (beta=%.3f)', ...
                string(obj.inlet.name), string(obj.recycle.name), ...
                string(obj.purge.name), obj.beta);
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.recycle.name)), ...
                     char(string(obj.purge.name))};
        end
    end
end

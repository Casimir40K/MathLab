classdef Bypass < handle
    properties
        inlet          % Stream object (fresh feed)
        processInlet   % Stream object (feed sent to process branch)
        bypassStream   % Stream object (bypassed branch)
        processReturn  % Stream object (return from process branch)
        outlet         % Stream object (mixed outlet)
        bypassFraction % scalar (0..1)
    end

    methods
        function obj = Bypass(inlet, processInlet, bypassStream, processReturn, outlet, bypassFraction)
            obj.inlet = inlet;
            obj.processInlet = processInlet;
            obj.bypassStream = bypassStream;
            obj.processReturn = processReturn;
            obj.outlet = outlet;
            obj.bypassFraction = bypassFraction;
        end

        function eqs = equations(obj)
            eqs = [];
            ns = numel(obj.inlet.y);
            b = obj.bypassFraction;

            % Internal splitter section
            eqs(end+1) = obj.processInlet.n_dot - (1 - b) * obj.inlet.n_dot;
            eqs(end+1) = obj.bypassStream.n_dot - b * obj.inlet.n_dot;
            for i = 1:ns
                eqs(end+1) = obj.processInlet.y(i) - obj.inlet.y(i);
                eqs(end+1) = obj.bypassStream.y(i) - obj.inlet.y(i);
            end

            % Internal mixer section
            eqs(end+1) = obj.outlet.n_dot - (obj.bypassStream.n_dot + obj.processReturn.n_dot);
            for i = 1:ns
                eqs(end+1) = obj.outlet.n_dot * obj.outlet.y(i) ...
                          - (obj.bypassStream.n_dot * obj.bypassStream.y(i) ...
                           + obj.processReturn.n_dot * obj.processReturn.y(i));
            end
        end

        function str = describe(obj)
            str = sprintf('Bypass: %s -> (%s + %s) -> %s', ...
                string(obj.inlet.name), string(obj.bypassStream.name), ...
                string(obj.processReturn.name), string(obj.outlet.name));
        end

        function names = streamNames(obj)
            names = {char(string(obj.inlet.name)), ...
                     char(string(obj.processInlet.name)), ...
                     char(string(obj.bypassStream.name)), ...
                     char(string(obj.processReturn.name)), ...
                     char(string(obj.outlet.name))};
        end
    end
end

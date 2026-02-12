classdef Cooler < proc.units.Heater
    methods
        function obj = Cooler(inlet, outlet, varargin)
            obj@proc.units.Heater(inlet, outlet, varargin{:});
        end

        function str = describe(obj)
            str = sprintf('Cooler: %s -> %s (%s)', string(obj.inlet.name), string(obj.outlet.name), obj.specMode);
        end
    end
end

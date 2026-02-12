function test_energy_units()
species = {'N2','O2'};
s1 = proc.Stream('s1', species);
s2 = proc.Stream('s2', species);
s1.n_dot = 100; s1.T = 300; s1.P = 1e5; s1.y = [0.79 0.21];
s2.n_dot = 100; s2.T = 350; s2.P = 1e5; s2.y = [0.79 0.21];

h = proc.units.Heater(s1, s2, struct('specMode','Tout','Tout',350));
eqs = h.equations();
assert(numel(eqs) == numel(species)+2);
assert(abs(eqs(end)) < 1e-8);
end

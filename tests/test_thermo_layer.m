function test_thermo_layer()
lib = thermo.ThermoLibrary();
mix = lib.makeMixture({'N2','O2'}, [0.79 0.21]);
cp300 = mix.cp_molar_kJkmolK(300);
assert(cp300 > 28 && cp300 < 32);

h300 = mix.h_molar_kJkmol(300, 'sensible');
h500 = mix.h_molar_kJkmol(500, 'sensible');
assert(abs(h300) < 500);
assert(h500 > h300);
end

%% run_case_reactors_massonly.m
% Mass-only reactor variants demo (no thermo/energy equations).
% Exercises StoichiometricReactor and ConversionReactor on species {A,B,C}.

clear; clc;

species = {'A','B','C'};

%% --- Case 1: Stoichiometric reactor (A -> B), fixed extent ---
S1_in = proc.Stream('S1_in', species);
S1_in.n_dot = 10; S1_in.y = [0.8 0.2 0.0];
S1_out = proc.Stream('S1_out', species);
S1_out.n_dot = 10; S1_out.y = [0.6 0.4 0.0];

nu1 = [-1; 1; 0];
xi1 = 2.0;
uStoich = proc.units.StoichiometricReactor(S1_in, S1_out, nu1, ...
    'extent', xi1, 'extentMode', 'fixed', 'referenceSpecies', 1);

res1 = uStoich.equations();
assert(max(abs(res1)) < 1e-10, 'StoichiometricReactor residual check failed.');

n1in = S1_in.n_dot * S1_in.y(:);
n1out = S1_out.n_dot * S1_out.y(:);
fprintf('StoichiometricReactor\n');
fprintf('  n_in  = [%g %g %g]\n', n1in(1), n1in(2), n1in(3));
fprintf('  n_out = [%g %g %g] (xi=%.3f)\n\n', n1out(1), n1out(2), n1out(3), xi1);

%% --- Case 2: Conversion reactor (A -> C), fixed conversion ---
S2_in = proc.Stream('S2_in', species);
S2_in.n_dot = 12; S2_in.y = [0.5 0.5 0.0];
S2_out = proc.Stream('S2_out', species);
S2_out.n_dot = 12; S2_out.y = [0.35 0.5 0.15];

nu2 = [-1; 0; 1];
X2 = 0.30;
uConv = proc.units.ConversionReactor(S2_in, S2_out, nu2, 1, X2, ...
    'conversionMode', 'fixed');

res2 = uConv.equations();
assert(max(abs(res2)) < 1e-10, 'ConversionReactor residual check failed.');

n2in = S2_in.n_dot * S2_in.y(:);
n2out = S2_out.n_dot * S2_out.y(:);
xi2 = X2 * n2in(1) / (-nu2(1));
fprintf('ConversionReactor\n');
fprintf('  n_in  = [%g %g %g]\n', n2in(1), n2in(2), n2in(3));
fprintf('  n_out = [%g %g %g] (X=%.3f, xi=%.3f)\n', n2out(1), n2out(2), n2out(3), X2, xi2);

fprintf('\nMass-only reactor example passed.\n');

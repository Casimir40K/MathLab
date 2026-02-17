%% MathLab Config Script (square-DOF thermo recycle case)
% Recreates the user's thermo-enabled recycle flowsheet with a square DOF.
% Key fixes vs the original snippet:
%   1) Adds missing Link unit: S2 -> S3
%   2) Leaves Sh.T and Sc.T as unknowns (heater/cooler Tout equations determine them)
%   3) Fails fast if solver does NOT actually converge (square DOF alone is not sufficient)

clear; clc;

species = {'H2', 'O2', 'H2O'};
fs = proc.Flowsheet(species);

% --- Streams ---
S1 = proc.Stream("S1", species);
S1.n_dot = 10; S1.T = 300; S1.P = 100000;
S1.y = [0.8 0.2 0];
S1.known.n_dot = true;
S1.known.T = true;
S1.known.P = true;
S1.known.y(:) = true;
fs.addStream(S1);

S2 = proc.Stream("S2", species);
S2.n_dot = 7.00008; S2.T = 300; S2.P = 100000;
S2.y = [0.85713287;0.14285548;1.1650897e-05];
fs.addStream(S2);

S3 = proc.Stream("S3", species);
S3.n_dot = 12; S3.T = 300; S3.P = 100000;
S3.y = [0.75;0.2;0.05];
fs.addStream(S3);

S4 = proc.Stream("S4", species);
S4.n_dot = 2.00001; S4.T = 500; S4.P = 100000;
S4.y = [0.99999299;9.8057565e-13;7.0051635e-06];
fs.addStream(S4);

S5 = proc.Stream("S5", species);
S5.n_dot = 6.62051e-05; S5.T = 278.15; S5.P = 100000;
S5.y = [9.9947768e-07;9.9453556e-07;0.99999801];
fs.addStream(S5);

S6 = proc.Stream("S6", species);
S6.n_dot = 1.12798e-07; S6.T = 278.15; S6.P = 100000;
S6.y = [1;1e-12;1e-12];
fs.addStream(S6);

S7 = proc.Stream("S7", species);
S7.n_dot = 3.99959e-09; S7.T = 278.15; S7.P = 100000;
S7.y = [1;1e-12;1e-12];
fs.addStream(S7);

Sp = proc.Stream("Sp", species);
Sp.n_dot = 2.19131e-05; Sp.T = 278.15; Sp.P = 100000;
Sp.y = [1;1e-12;1e-12];
fs.addStream(Sp);

Sh = proc.Stream("Sh", species);
Sh.n_dot = 4; Sh.T = 500; Sh.P = 100000;
Sh.y = [1;1e-12;1e-12];
% NOTE: leave Sh.T unknown; Heater(Tout) provides this equation.
fs.addStream(Sh);

Sc = proc.Stream("Sc", species);
Sc.n_dot = 5.33275e-06; Sc.T = 278.15; Sc.P = 100000;
Sc.y = [1e-12;1e-12;1];
% NOTE: leave Sc.T unknown; Cooler(Tout) provides this equation.
fs.addStream(Sc);

% --- Units ---
fs.addUnit(proc.units.Mixer({S1, S7}, S2));
fs.addUnit(proc.units.Link(S2, S3));

rxn.reactants = [1 2];
rxn.products = 3;
rxn.stoich = [-2 -1 2];
rxn.name = "reaction";
fs.addUnit(proc.units.Reactor(Sh, S4, rxn, 0.7));

fs.addUnit(proc.units.Separator(Sc, S5, S6, [0.1 0.1 0.98]));
fs.addUnit(proc.units.Purge(S6, S7, Sp, 0.95));

thermoLib = thermo.ThermoLibrary();
mix = thermo.IdealGasMixture(species, thermoLib);
fs.addUnit(proc.units.Heater(S3, Sh, mix, 'Tout', 500));

thermoLib = thermo.ThermoLibrary();
mix = thermo.IdealGasMixture(species, thermoLib);
fs.addUnit(proc.units.Cooler(S4, Sc, mix, 'Tout', 278.15));

% --- DOF check (should be square) ---
[nUnknown, nEq] = fs.checkDOF();
fprintf('Expected square DOF for this config: unknowns=%d, equations=%d\n', nUnknown, nEq);

% --- Solve ---
solver = fs.solve('maxIter', 200, 'tolAbs', 1.00e-09, 'verbose', true);

% --- Convergence guard (important) ---
% The solver can return a stream table even when maxIter is reached.
% Reject non-converged results explicitly.
if solver.useWeightedNormForConvergence
    finalNorm = solver.weightedResidualHistory(end);
    normName = '||W*r||';
else
    finalNorm = solver.residualHistory(end);
    normName = '||r||';
end
if ~isfinite(finalNorm) || finalNorm > solver.tolAbs
    error('Config did not converge: final %s = %.3e > tolAbs = %.3e.\nDo not trust stream values.', ...
        normName, finalNorm, solver.tolAbs);
end

T = fs.streamTable();
disp(T);

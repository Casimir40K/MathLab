%% MathLab Config Script (square-DOF, thermo-enabled, no recycle)
% Purpose: provide a robust baseline case that is square and typically converges
% without recycle-loop stiffness.
%
% Topology:
%   S1 --Link--> S2 --Heater(Tout)--> Sh --Reactor(X)--> S4 --Cooler(Tout)--> Sc
%
% Notes:
% - S1 is fully specified (known feed).
% - All downstream streams are unknown and solved from unit equations.
% - This gives a square system by construction for ns = 3 species.

clear; clc;

species = {'H2', 'O2', 'H2O'};
fs = proc.Flowsheet(species);

% --- Streams ---
S1 = proc.Stream("S1", species);
S1.n_dot = 10.0; S1.T = 300.0; S1.P = 100000;
S1.y = [0.80 0.20 0.00];
S1.known.n_dot = true;
S1.known.T = true;
S1.known.P = true;
S1.known.y(:) = true;
fs.addStream(S1);

S2 = proc.Stream("S2", species);
S2.n_dot = 10.0; S2.T = 300.0; S2.P = 100000;
S2.y = [0.80; 0.20; 1e-12];
fs.addStream(S2);

Sh = proc.Stream("Sh", species);
Sh.n_dot = 9.5; Sh.T = 480.0; Sh.P = 100000;
Sh.y = [0.78; 0.19; 0.03];
fs.addStream(Sh);

S4 = proc.Stream("S4", species);
S4.n_dot = 9.0; S4.T = 520.0; S4.P = 100000;
S4.y = [0.70; 0.10; 0.20];
fs.addStream(S4);

Sc = proc.Stream("Sc", species);
Sc.n_dot = 9.0; Sc.T = 320.0; Sc.P = 100000;
Sc.y = [0.65; 0.08; 0.27];
fs.addStream(Sc);

% --- Units ---
fs.addUnit(proc.units.Link(S1, S2));

thermoLib = thermo.ThermoLibrary();
mix = thermo.IdealGasMixture(species, thermoLib);
fs.addUnit(proc.units.Heater(S2, Sh, mix, 'Tout', 500.0));

rxn.reactants = [1 2];
rxn.products = 3;
rxn.stoich = [-2 -1 2];
rxn.name = "H2 oxidation";
fs.addUnit(proc.units.Reactor(Sh, S4, rxn, 0.30));

thermoLib = thermo.ThermoLibrary();
mix = thermo.IdealGasMixture(species, thermoLib);
fs.addUnit(proc.units.Cooler(S4, Sc, mix, 'Tout', 320.0));

% --- DOF check ---
[nUnknown, nEq] = fs.checkDOF();
fprintf('Square target: unknowns=%d, equations=%d\n', nUnknown, nEq);
if nUnknown ~= nEq
    error('Config is not square (unknowns=%d, equations=%d).', nUnknown, nEq);
end

% --- Solve ---
solver = fs.solve('maxIter', 200, 'tolAbs', 1e-9, 'verbose', true);

% Fail-fast if not converged
if solver.useWeightedNormForConvergence
    finalNorm = solver.weightedResidualHistory(end);
    normName = '||W*r||';
else
    finalNorm = solver.residualHistory(end);
    normName = '||r||';
end
if ~isfinite(finalNorm) || finalNorm > solver.tolAbs
    error('Did not converge: final %s = %.3e > tolAbs = %.3e', normName, finalNorm, solver.tolAbs);
end

T = fs.streamTable();
disp(T);

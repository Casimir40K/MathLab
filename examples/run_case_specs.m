%RUN_CASE_SPECS Demonstrates spec/solver-control blocks working together.
clear; clc;

species = {'A'};
fs = proc.Flowsheet(species);

% Streams
F = proc.Stream('F', species);
P = proc.Stream('P', species);
R = proc.Stream('R', species);

% Fix y/T/P as known; solve n_dot values only.
for s = {F,P,R}
    st = s{1};
    st.y = 1;
    st.T = 300;
    st.P = 1e5;
    st.known.y(:) = true;
    st.known.T = true;
    st.known.P = true;
    st.known.n_dot = false;
end

fs.addStream(F); fs.addStream(P); fs.addStream(R);

% Source block: fixed feed total flow (no redundant sum(y)=1 equation).
src = proc.units.Source(F, struct('totalFlow', 10));

% Splitter with adjustable first split fraction.
spl = proc.units.Splitter(F, {P, R}, 'fractions', [0.5 0.4]);

% Design target: product total flow = 6 mol/s.
ds = proc.units.DesignSpec(P, 'total_flow', 6, 1);

% Adjust: manipulate splitter splitFractions(1) in [0,1] to satisfy ds.
adj = proc.units.Adjust(ds, spl, 'splitFractions', 1, 0, 1);

% Calculator: enforce y_P = y_F / y_F = 1 (simple algebraic scaffolding).
calc = proc.units.Calculator(P, 'y', F, 'y', '/', F, 'y');
calc.lhsIndex = 1; calc.aIndex = 1; calc.bIndex = 1;

% Constraint: equality-only constraint on recycle temperature placeholder.
con = proc.units.Constraint(R, 'T', 300);

% Sink blocks (no residuals) for topology completeness.
skP = proc.units.Sink(P);
skR = proc.units.Sink(R);

fs.addUnit(src);
fs.addUnit(spl);
fs.addUnit(ds);
fs.addUnit(adj);
fs.addUnit(calc);
fs.addUnit(con);
fs.addUnit(skP);
fs.addUnit(skR);

solver = fs.solve('maxIter', 80, 'tolAbs', 1e-10, 'printToConsole', true, 'consoleStride', 1);
T = fs.streamTable();
disp(T);

fprintf('\nSolved manipulated split fraction f1 = %.6f\n', spl.splitFractions(1));
fprintf('Product flow target = %.3f, solved P.n_dot = %.6f\n', ds.target, P.n_dot);

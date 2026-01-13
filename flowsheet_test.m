clear; clc;

species = {'H2','O2','H2O'};

% --------------------
% Streams
% --------------------
S1 = Stream("S1", species);   % feed (known)
S2 = Stream("S2", species);   % mixer outlet
S3 = Stream("S3", species);   % link outlet (reactor inlet)
S4 = Stream("S4", species);   % reactor outlet
S5 = Stream("S5", species);   % product (mostly H2O)
S6 = Stream("S6", species);   % separator "recycle" outlet (pre-purge)
S7 = Stream("S7", species);   % purge recycle outlet to mixer
Sp = Stream("Sp", species);   % purge outlet leaving system

% --------------------
% Known feed S1
% --------------------
S1.n_dot = 10;
S1.T     = 300;
S1.P     = 1e5;
S1.y     = [0.8 0.2 0];

S1.known.n_dot = true;
S1.known.T     = true;
S1.known.P     = true;
S1.known.y(:)  = true;

% --------------------
% Initial guesses (NOT known)
% --------------------
guessStream(S2,  12, [0.75 0.20 0.05]);
guessStream(S3,  12, [0.75 0.20 0.05]);
guessStream(S4,  12, [0.60 0.10 0.30]);
guessStream(S5,   3, [1e-6 1e-6 0.999998]);
guessStream(S6,   2, [0.80 0.20 1e-6]);
guessStream(S7,   2, [0.80 0.20 1e-6]);
guessStream(Sp,   0.2,[0.80 0.20 1e-6]);

% --------------------
% Units
% --------------------
% Mixer now takes S1 + S7 (not S6)
M1  = Mixer({S1, S7}, S2);

% Optional link/piping
L23 = Link(S2, S3);

% Reactor: 2H2 + O2 -> 2H2O
rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "Water formation";
conversion = 0.7;
R1 = Reactor(S3, S4, rxn, conversion);

% Separator: OutletA = S5 (water product), OutletB = S6 (unreacted to recycle line)
epsSplit = 1e-6;
phiSep = [epsSplit, epsSplit, 1-epsSplit];  % send mostly H2O to S5
Sep1 = Separator(S4, S5, S6, phiSep);

% Purge: split S6 -> S7 (recycle to mixer) + Sp (purge out)
betaRecycle = 0.95; % 95% back to mixer, 5% purge
P1 = Purge(S6, S7, Sp, betaRecycle);

% --------------------
% Solve
% --------------------
streams = {S1,S2,S3,S4,S5,S6,S7,Sp};
units   = {M1, L23, R1, Sep1, P1};

solver = ProcessSolver(streams, units);
solver.maxIter = 80;
solver.tolAbs  = 1e-9;
solver.verbose = true;

solver.solve();

T = solver.streamTable();
disp(T);

% ---- helper ----
function guessStream(S, ndot, y)
    S.n_dot = ndot;
    S.T = 300;
    S.P = 1e5;
    S.y = y;
end

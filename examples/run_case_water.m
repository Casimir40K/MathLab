clear; clc;

species = {'H2','O2','H2O'};
fs = Flowsheet(species);

% Streams
S1 = Stream("S1", species);
S2 = Stream("S2", species);
S3 = Stream("S3", species);
S4 = Stream("S4", species);
S5 = Stream("S5", species);
S6 = Stream("S6", species);
S7 = Stream("S7", species);
Sp = Stream("Sp", species);

% Add streams to flowsheet
for s = {S1,S2,S3,S4,S5,S6,S7,Sp}
    fs.addStream(s{1});
end

% Known feed
S1.n_dot = 10; S1.T = 300; S1.P = 1e5; S1.y = [0.8 0.2 0];
S1.known.n_dot = true; S1.known.T = true; S1.known.P = true; S1.known.y(:) = true;


% Ensure only S1 is "known"
for s = {S2,S3,S4,S5,S6,S7,Sp}
    s{1}.known.n_dot = false;
    s{1}.known.T = false;
    s{1}.known.P = false;
    s{1}.known.y(:) = false;
end



% Initial guesses (NOT known)
guess(S2, 12, [0.75 0.20 0.05]);
guess(S3, 12, [0.75 0.20 0.05]);
guess(S4, 12, [0.60 0.10 0.30]);
guess(S5,  3, [1e-6 1e-6 0.999998]);
guess(S6,  2, [0.80 0.20 1e-6]);
guess(S7,  2, [0.80 0.20 1e-6]);
guess(Sp,0.2, [0.80 0.20 1e-6]);

% Units
M1  = Mixer({S1, S7}, S2);
L23 = Link(S2, S3);

rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];      % 2H2 + O2 -> 2H2O
rxn.name      = "Water formation";
R1 = Reactor(S3, S4, rxn, 0.7);

epsSplit = 1e-6;
phiSep = [epsSplit, epsSplit, 1-epsSplit];   % outletA=S5 gets mostly H2O
Sep1 = Separator(S4, S5, S6, phiSep);

P1 = Purge(S6, S7, Sp, 0.95);                % 95% recycle, 5% purge

% Add units
for u = {M1,L23,R1,Sep1,P1}
    fs.addUnit(u{1});
end


[nU, nE] = fs.checkDOF();
% Solve
fs.solve('maxIter', 80, 'tolAbs', 1e-9, 'verbose', true);

% Stream table
T = fs.streamTable();
disp(T);

function guess(S, ndot, y)
    S.n_dot = ndot;
    S.T = 300;
    S.P = 1e5;
    S.y = y;
end

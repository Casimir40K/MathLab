% Define streams
species = {'H2','O2','H2O'};
S1 = Stream('S1', species);
S2 = Stream('S2', species);  % reactor outlet
S3 = Stream('S3', species);  % optional, unused in this test

% Initial known S1
S1.n_dot = 10;
S1.T     = 300;
S1.P     = 1e5;
S1.y     = [0.5 0.5 0];

% Define reaction
rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-1 -1 2];
rxn.name      = 'H2O formation';
conversion = 0.5;

% Create reactor
reactor = Reactor(S1, S2, rxn, conversion);

% Example solver with just 1 unit
streams = {S1, S2};
units   = {reactor};

solver = ProcessSolver(streams, units);
solver.solve();

% Generate table
StreamTable = solver.generateStreamTable();
disp(StreamTable)


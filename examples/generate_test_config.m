%% generate_test_config.m — Creates a test config .mat file for MathLab
%
%  Run this once to produce 'water_recycle_config.mat' which you can then:
%    1. Load in MathLabApp via Species tab -> Load Config
%    2. Run headlessly:  [T, solver] = runFromConfig('water_recycle_config.mat');
%
%  System: 2H2 + O2 -> 2H2O with recycle loop and purge

clear; clc;

fprintf('Generating test config: water_recycle_config.mat\n');

% === Species ===
cfg.speciesNames = {'H2', 'O2', 'H2O'};
cfg.speciesMW    = [2.016, 32.00, 18.015];

% === Streams ===
%  S1 = fresh feed (known)
%  S2 = mixer outlet
%  S3 = link to reactor
%  S4 = reactor outlet
%  S5 = separator -> H2O product
%  S6 = separator -> gas recycle
%  S7 = purge -> recycle to mixer
%  Sp = purge stream out

streamDefs = {
%   name   n_dot    T    P       y                kn_n  kn_T  kn_P  kn_y
    'S1',  10,     300, 1e5,  [0.80  0.20  0.00],  true, true, true, true;
    'S2',  12,     300, 1e5,  [0.75  0.20  0.05],  false,false,false,false;
    'S3',  12,     300, 1e5,  [0.75  0.20  0.05],  false,false,false,false;
    'S4',  12,     300, 1e5,  [0.60  0.10  0.30],  false,false,false,false;
    'S5',  3,      300, 1e5,  [1e-6  1e-6  0.999998], false,false,false,false;
    'S6',  2,      300, 1e5,  [0.80  0.20  1e-6],  false,false,false,false;
    'S7',  2,      300, 1e5,  [0.80  0.20  1e-6],  false,false,false,false;
    'Sp',  0.2,    300, 1e5,  [0.80  0.20  1e-6],  false,false,false,false;
};

for i = 1:size(streamDefs, 1)
    sd.name       = streamDefs{i, 1};
    sd.n_dot      = streamDefs{i, 2};
    sd.T          = streamDefs{i, 3};
    sd.P          = streamDefs{i, 4};
    sd.y          = streamDefs{i, 5};
    sd.known_n_dot = streamDefs{i, 6};
    sd.known_T     = streamDefs{i, 7};
    sd.known_P     = streamDefs{i, 8};
    sd.known_y     = streamDefs{i, 9};
    if sd.known_y
        sd.known_y = true(1, numel(cfg.speciesNames));
    else
        sd.known_y = false(1, numel(cfg.speciesNames));
    end
    cfg.streams(i) = sd;
end

% === Unit Definitions (serializable structs) ===
% These are the same format MathLabApp saves internally.

% Unit 1: Mixer  {S1, S7} -> S2
def1.type = 'Mixer';
def1.inlets = {'S1', 'S7'};
def1.outlet = 'S2';

% Unit 2: Link  S2 -> S3
def2.type = 'Link';
def2.inlet = 'S2';
def2.outlet = 'S3';

% Unit 3: Reactor  S3 -> S4 (2H2 + O2 -> 2H2O, X=0.7)
def3.type = 'Reactor';
def3.inlet = 'S3';
def3.outlet = 'S4';
def3.conversion = 0.7;
rxn.reactants = [1 2];
rxn.products  = [3];
rxn.stoich    = [-2 -1 2];
rxn.name      = "Water formation";
def3.reactions = rxn;

% Unit 4: Separator  S4 -> S5 (H2O product), S6 (gas recycle)
def4.type = 'Separator';
def4.inlet = 'S4';
def4.outletA = 'S5';
def4.outletB = 'S6';
eps = 1e-6;
def4.phi = [eps, eps, 1-eps];   % nearly all H2O goes to outlet A

% Unit 5: Purge  S6 -> S7 (recycle, 95%), Sp (purge, 5%)
def5.type = 'Purge';
def5.inlet = 'S6';
def5.recycle = 'S7';
def5.purge = 'Sp';
def5.beta = 0.95;

cfg.unitDefs = {def1, def2, def3, def4, def5};

% === Solver settings ===
cfg.maxIter = 200;
cfg.tolAbs  = 1e-9;

% === Save ===
save('water_recycle_config.mat', '-struct', 'cfg');
fprintf('Saved: water_recycle_config.mat\n');
fprintf('\nTo solve from command line:\n');
fprintf('  [T, solver] = runFromConfig(''water_recycle_config.mat'');\n');
fprintf('\nTo load in GUI:\n');
fprintf('  app = MathLabApp(''water_recycle_config.mat'');\n');
fprintf('  OR: open GUI, go to Species tab, click Load Config.\n');

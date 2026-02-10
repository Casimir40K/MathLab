%% run_case_topology.m
% Demonstrates topology-focused unit operations (mass-flow only):
% Splitter, Recycle, Bypass, and Manifold/Header.

clear; clc;

species = {'A','B'};

%% --- Streams ---
S_feed = proc.Stream('S_feed', species);
S_feed.n_dot = 100; S_feed.y = [0.7 0.3];

S_procIn = proc.Stream('S_procIn', species);   S_procIn.n_dot = 75; S_procIn.y = [0.7 0.3];
S_bypass = proc.Stream('S_bypass', species);   S_bypass.n_dot = 25; S_bypass.y = [0.7 0.3];
S_procOut = proc.Stream('S_procOut', species); S_procOut.n_dot = 60; S_procOut.y = [0.6 0.4];
S_mixOut = proc.Stream('S_mixOut', species);   S_mixOut.n_dot = 85; S_mixOut.y = [0.6294117647 0.3705882353];

S_split1 = proc.Stream('S_split1', species);   S_split1.n_dot = 51; S_split1.y = [0.6294117647 0.3705882353];
S_split2 = proc.Stream('S_split2', species);   S_split2.n_dot = 34; S_split2.y = [0.6294117647 0.3705882353];

S_hdrIn1 = proc.Stream('S_hdrIn1', species);   S_hdrIn1.n_dot = 51; S_hdrIn1.y = [0.6294117647 0.3705882353];
S_hdrIn2 = proc.Stream('S_hdrIn2', species);   S_hdrIn2.n_dot = 34; S_hdrIn2.y = [0.6294117647 0.3705882353];
S_hdrOut1 = proc.Stream('S_hdrOut1', species); S_hdrOut1.n_dot = 34; S_hdrOut1.y = [0.6294117647 0.3705882353];
S_hdrOut2 = proc.Stream('S_hdrOut2', species); S_hdrOut2.n_dot = 51; S_hdrOut2.y = [0.6294117647 0.3705882353];

S_recycleSrc = proc.Stream('S_recycleSrc', species); S_recycleSrc.n_dot = 20; S_recycleSrc.y = [0.5 0.5];
S_tear = proc.Stream('S_tear', species);             S_tear.n_dot = 20;       S_tear.y = [0.5 0.5];

%% --- Units in action ---
% 1) Bypass: convenience splitter + mixer topology
uBypass = proc.units.Bypass(S_feed, S_procIn, S_bypass, S_procOut, S_mixOut, 0.25);

% 2) Splitter: one inlet -> two outlets via fractions
uSplit = proc.units.Splitter(S_mixOut, {S_split1, S_split2}, 'fractions', [0.6 0.4]);

% 3) Manifold/Header: routing/equality constraints (swap channels)
uMan = proc.units.Manifold({S_hdrIn1, S_hdrIn2}, {S_hdrOut1, S_hdrOut2}, [2 1]);

% 4) Recycle block: explicit tear bookkeeping only
uRec = proc.units.Recycle(S_recycleSrc, S_tear);

%% --- Assertions: mass-balance residuals should be near zero ---
assert(max(abs(uBypass.equations())) < 1e-10, 'Bypass mass balance failed.');
assert(max(abs(uSplit.equations()))  < 1e-10, 'Splitter mass balance failed.');
assert(max(abs(uMan.equations()))    < 1e-10, 'Manifold routing/equality failed.');
assert(max(abs(uRec.equations()))    < 1e-10, 'Recycle bookkeeping failed.');

% Additional explicit total-flow checks
assert(abs(S_feed.n_dot - (S_procIn.n_dot + S_bypass.n_dot)) < 1e-10, 'Bypass split flow mismatch.');
assert(abs(S_mixOut.n_dot - (S_bypass.n_dot + S_procOut.n_dot)) < 1e-10, 'Bypass mix flow mismatch.');
assert(abs(S_mixOut.n_dot - (S_split1.n_dot + S_split2.n_dot)) < 1e-10, 'Splitter total-flow mismatch.');

fprintf('Topology example passed: all mass-balance assertions satisfied.\n');

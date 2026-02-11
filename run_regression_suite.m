function summary = run_regression_suite(varargin)
%RUN_REGRESSION_SUITE End-to-end regression suite for MathLab.
%   SUMMARY = RUN_REGRESSION_SUITE() runs deterministic checks for
%   solver workflows and all built-in unit blocks.
%
%   SUMMARY = RUN_REGRESSION_SUITE('verbose', false) suppresses per-test logs.
%   SUMMARY = RUN_REGRESSION_SUITE('errorOnFailure', false) returns summary
%   without throwing, even when one or more tests fail.
%
%   Intended use before merging/upgrading MathLab:
%       summary = run_regression_suite();
%
%   The runner always executes all tests and aggregates failures.

    p = inputParser;
    p.addParameter('verbose', true, @(x)islogical(x) && isscalar(x));
    p.addParameter('errorOnFailure', true, @(x)islogical(x) && isscalar(x));
    p.parse(varargin{:});
    verbose = p.Results.verbose;
    errorOnFailure = p.Results.errorOnFailure;

    tests = {
        @testSolveWaterRecycleFlowsheet
        @testRunFromConfigRoundTrip
        @testMassOnlyReactorVariants
        @testTopologyUnits
        @testSourceSinkDesignSpecAdjustCalculatorConstraint
    };

    n = numel(tests);
    results = repmat(struct('name',"",'passed',false,'seconds',0,'message',""), n, 1);

    tSuite = tic;
    for i = 1:n
        f = tests{i};
        t0 = tic;
        try
            f();
            results(i).name = string(func2str(f));
            results(i).passed = true;
            results(i).seconds = toc(t0);
            results(i).message = "OK";
            if verbose
                fprintf('[PASS] %s (%.3fs)\n', results(i).name, results(i).seconds);
            end
        catch ME
            results(i).name = string(func2str(f));
            results(i).passed = false;
            results(i).seconds = toc(t0);
            results(i).message = string(getReport(ME, 'basic', 'hyperlinks', 'off'));
            if verbose
                fprintf('[FAIL] %s (%.3fs)\n', results(i).name, results(i).seconds);
                fprintf('%s\n', results(i).message);
            end
        end
    end

    summary = struct();
    summary.totalTests = n;
    summary.passedTests = sum([results.passed]);
    summary.failedTests = n - summary.passedTests;
    summary.totalSeconds = toc(tSuite);
    summary.results = results;
    summary.failedNames = strings(0, 1);
    summary.failedMessages = strings(0, 1);

    if summary.failedTests == 0
        if verbose
            fprintf('\nMathLab regression suite passed: %d/%d tests in %.3fs\n', ...
                summary.passedTests, summary.totalTests, summary.totalSeconds);
        end
    else
        failedIdx = find(~[results.passed]);
        summary.failedNames = string({results(failedIdx).name}).';
        summary.failedMessages = string({results(failedIdx).message}).';

        if verbose
            fprintf('\nMathLab regression suite found %d failure(s):\n', summary.failedTests);
            for j = 1:numel(failedIdx)
                r = results(failedIdx(j));
                fprintf('  - %s (%.3fs)\n', r.name, r.seconds);
            end
        end

        if errorOnFailure
            msg = sprintf('Regression suite completed with %d failure(s) out of %d test(s).', ...
                summary.failedTests, summary.totalTests);
            for j = 1:numel(failedIdx)
                r = results(failedIdx(j));
                msg = sprintf('%s\n\n- %s\n%s', msg, r.name, r.message);
            end
            error('MathLab:RegressionSuiteFailed', '%s', msg);
        end
    end
end

function testSolveWaterRecycleFlowsheet()
    species = {'H2','O2','H2O'};
    fs = proc.Flowsheet(species);

    S1 = proc.Stream("S1", species);
    S2 = proc.Stream("S2", species);
    S3 = proc.Stream("S3", species);
    S4 = proc.Stream("S4", species);
    S5 = proc.Stream("S5", species);
    S6 = proc.Stream("S6", species);
    S7 = proc.Stream("S7", species);
    Sp = proc.Stream("Sp", species);

    for s = {S1,S2,S3,S4,S5,S6,S7,Sp}
        fs.addStream(s{1});
    end

    S1.setKnown('n_dot', 10);
    S1.setKnown('T', 300);
    S1.setKnown('P', 1e5);
    S1.setKnown('y', [2/3 1/3 0]);

    S2.setGuess(12, [0.75 0.20 0.05]);
    S3.setGuess(12, [0.75 0.20 0.05]);
    S4.setGuess(12, [0.60 0.10 0.30]);
    S5.setGuess(3,  [1e-6 1e-6 0.999998]);
    S6.setGuess(2,  [0.80 0.20 1e-6]);
    S7.setGuess(2,  [0.80 0.20 1e-6]);
    Sp.setGuess(0.2,[0.80 0.20 1e-6]);

    M1  = proc.units.Mixer({S1, S7}, S2);
    L23 = proc.units.Link(S2, S3);

    rxn.reactants = [1 2];
    rxn.products  = [3];
    rxn.stoich    = [-2 -1 2];
    rxn.name      = "Water formation";
    R1 = proc.units.Reactor(S3, S4, rxn, 0.7);

    epsSplit = 1e-6;
    phiSep = [epsSplit, epsSplit, 1-epsSplit];
    Sep1 = proc.units.Separator(S4, S5, S6, phiSep);

    P1 = proc.units.Purge(S6, S7, Sp, 0.95);

    for u = {M1, L23, R1, Sep1, P1}
        fs.addUnit(u{1});
    end

    [nU, nE] = fs.checkDOF('quiet', true);
    assert(nU == nE, 'Water recycle case is not square: unknowns=%d equations=%d', nU, nE);

    solver = fs.solve('maxIter', 250, 'tolAbs', 1e-9, 'printToConsole', false);
    assert(~isempty(solver.residualHistory), 'No residual history captured for water recycle solve.');
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'Water recycle did not converge to tolerance: ||r||=%.3e tol=%.3e', ...
        solver.residualHistory(end), solver.tolAbs);
end

function testRunFromConfigRoundTrip()
    cfgPath = [tempname() '.mat'];
    outDir = tempname();

    cfg = buildWaterConfigStruct();
    save(cfgPath, '-struct', 'cfg');

    [T, solver] = runFromConfig(cfgPath, 'plot', false, 'verbose', false, 'outputDir', outDir);

    assert(istable(T), 'runFromConfig did not return a table.');
    assert(height(T) == numel(cfg.streams), 'runFromConfig table row count mismatch.');
    assert(~isempty(solver.residualHistory), 'runFromConfig solver has empty residual history.');
    assert(solver.residualHistory(end) < solver.tolAbs, ...
        'runFromConfig did not converge to tolerance: ||r||=%.3e tol=%.3e', ...
        solver.residualHistory(end), solver.tolAbs);

    if isfolder(outDir)
        rmdir(outDir, 's');
    end
    if isfile(cfgPath)
        delete(cfgPath);
    end
end

function testMassOnlyReactorVariants()
    species = {'A','B','C'};

    S1_in = proc.Stream('S1_in', species);
    S1_in.n_dot = 10; S1_in.y = [0.8 0.2 0.0];
    S1_out = proc.Stream('S1_out', species);
    S1_out.n_dot = 10; S1_out.y = [0.6 0.4 0.0];
    nu1 = [-1; 1; 0];
    uStoich = proc.units.StoichiometricReactor(S1_in, S1_out, nu1, ...
        'extent', 2.0, 'extentMode', 'fixed', 'referenceSpecies', 1);
    assertNearZero(uStoich.equations(), 1e-10, 'StoichiometricReactor fixed extent failed');

    S2_in = proc.Stream('S2_in', species);
    S2_in.n_dot = 12; S2_in.y = [0.5 0.5 0.0];
    S2_out = proc.Stream('S2_out', species);
    S2_out.n_dot = 12; S2_out.y = [0.3 0.7 0.0];
    nu2 = [-1; 1; 0];
    uConv = proc.units.ConversionReactor(S2_in, S2_out, nu2, 1, 0.4, 'conversionMode', 'fixed');
    assertNearZero(uConv.equations(), 1e-10, 'ConversionReactor fixed conversion failed');

    S3_in = proc.Stream('S3_in', species);
    S3_in.n_dot = 10; S3_in.y = [0.8 0.2 0.0];
    S3_out = proc.Stream('S3_out', species);
    S3_out.n_dot = 10; S3_out.y = [0.4 0.2 0.4];
    uYield = proc.units.YieldReactor(S3_in, S3_out, 1, 0.5, 3, 1.0, 'conversionMode', 'fixed');
    assertNearZero(uYield.equations(), 1e-10, 'YieldReactor fixed conversion failed');

    S4_in = proc.Stream('S4_in', species);
    S4_in.n_dot = 10; S4_in.y = [0.5 0.5 0.0];
    S4_out = proc.Stream('S4_out', species);
    % For A <-> B with nu=[-1 +1 0], Keq=4 => yB/yA = 4
    S4_out.n_dot = 10; S4_out.y = [0.2 0.8 0.0];
    uEq = proc.units.EquilibriumReactor(S4_in, S4_out, [-1;1;0], 4.0, 'referenceSpecies', 1);
    assertNearZero(uEq.equations(), 1e-10, 'EquilibriumReactor equilibrium check failed');
end

function testTopologyUnits()
    species = {'A','B'};

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

    uBypass = proc.units.Bypass(S_feed, S_procIn, S_bypass, S_procOut, S_mixOut, 0.25);
    uSplit = proc.units.Splitter(S_mixOut, {S_split1, S_split2}, 'fractions', [0.6 0.4]);
    uMan = proc.units.Manifold({S_hdrIn1, S_hdrIn2}, {S_hdrOut1, S_hdrOut2}, [2 1]);
    uRec = proc.units.Recycle(S_recycleSrc, S_tear);

    assertNearZero(uBypass.equations(), 1e-10, 'Bypass equations failed');
    assertNearZero(uSplit.equations(), 1e-10, 'Splitter equations failed');
    assertNearZero(uMan.equations(), 1e-10, 'Manifold equations failed');
    assertNearZero(uRec.equations(), 1e-10, 'Recycle equations failed');

    assert(abs(S_feed.n_dot - (S_procIn.n_dot + S_bypass.n_dot)) < 1e-10, 'Bypass split flow mismatch');
    assert(abs(S_mixOut.n_dot - (S_bypass.n_dot + S_procOut.n_dot)) < 1e-10, 'Bypass mix flow mismatch');
    assert(abs(S_mixOut.n_dot - (S_split1.n_dot + S_split2.n_dot)) < 1e-10, 'Splitter total-flow mismatch');
end

function testSourceSinkDesignSpecAdjustCalculatorConstraint()
    species = {'A','B','C'};

    s = proc.Stream('S_source', species);
    s.n_dot = 10;
    s.y = [0.2 0.3 0.5];
    s.T = 350;
    s.P = 2e5;

    srcOpts = struct();
    srcOpts.totalFlow = 10;
    srcOpts.componentFlows = [2 3 5];
    srcOpts.composition = [0.2 0.3 0.5];
    srcOpts.specifyT = true;
    srcOpts.specifyP = true;
    srcOpts.T = 350;
    srcOpts.P = 2e5;
    uSource = proc.units.Source(s, srcOpts);
    assertNearZero(uSource.equations(), 1e-10, 'Source equations failed');

    uSink = proc.units.Sink(s);
    assertNearZero(uSink.equations(), 1e-10, 'Sink equations failed');

    ds = proc.units.DesignSpec(s, 'comp_flow', 3, 2);
    assertNearZero(ds.equations(), 1e-10, 'DesignSpec equation failed');

    dsAdj = proc.units.DesignSpec(s, 'total_flow', 12);
    adj = proc.units.Adjust(dsAdj, s, 'n_dot', NaN, 1, 20);
    adj.setVariableValue(12);
    assert(abs(adj.getVariableValue() - 12) < 1e-12, 'Adjust set/get variable failed');
    assertNearZero(adj.equations(), 1e-10, 'Adjust equation failed after variable update');

    sA = proc.Stream('S_A', species); sA.n_dot = 10; sA.y = [0.4 0.3 0.3];
    sB = proc.Stream('S_B', species); sB.n_dot = 4;  sB.y = [0.2 0.5 0.3];
    sC = proc.Stream('S_C', species); sC.n_dot = 14; sC.y = [0.3 0.36 0.34];

    calc = proc.units.Calculator(sC, 'n_dot', sA, 'n_dot', '+', sB, 'n_dot');
    assertNearZero(calc.equations(), 1e-10, 'Calculator equation failed');

    con = proc.units.Constraint(s, 'P', 2e5);
    assertNearZero(con.equations(), 1e-10, 'Constraint equation failed');
end

function cfg = buildWaterConfigStruct()
    cfg.speciesNames = {'H2', 'O2', 'H2O'};
    cfg.speciesMW = [2.016, 32.00, 18.015];

    streamDefs = {
        'S1',  10,   300, 1e5, [0.80 0.20 0.00],  true,  true,  true,  true;
        'S2',  12,   300, 1e5, [0.75 0.20 0.05],  false, false, false, false;
        'S3',  12,   300, 1e5, [0.75 0.20 0.05],  false, false, false, false;
        'S4',  12,   300, 1e5, [0.60 0.10 0.30],  false, false, false, false;
        'S5',  3,    300, 1e5, [1e-6 1e-6 0.999998], false, false, false, false;
        'S6',  2,    300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
        'S7',  2,    300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
        'Sp',  0.2,  300, 1e5, [0.80 0.20 1e-6],  false, false, false, false;
    };

    for i = 1:size(streamDefs, 1)
        sd.name = streamDefs{i, 1};
        sd.n_dot = streamDefs{i, 2};
        sd.T = streamDefs{i, 3};
        sd.P = streamDefs{i, 4};
        sd.y = streamDefs{i, 5};
        sd.known_n_dot = streamDefs{i, 6};
        sd.known_T = streamDefs{i, 7};
        sd.known_P = streamDefs{i, 8};
        sd.known_y = streamDefs{i, 9};
        if sd.known_y
            sd.known_y = true(1, numel(cfg.speciesNames));
        else
            sd.known_y = false(1, numel(cfg.speciesNames));
        end
        cfg.streams(i) = sd; %#ok<AGROW>
    end

    def1.type = 'Mixer';
    def1.inlets = {'S1', 'S7'};
    def1.outlet = 'S2';

    def2.type = 'Link';
    def2.inlet = 'S2';
    def2.outlet = 'S3';

    def3.type = 'Reactor';
    def3.inlet = 'S3';
    def3.outlet = 'S4';
    def3.conversion = 0.7;
    rxn.reactants = [1 2];
    rxn.products = [3];
    rxn.stoich = [-2 -1 2];
    rxn.name = "Water formation";
    def3.reactions = rxn;

    def4.type = 'Separator';
    def4.inlet = 'S4';
    def4.outletA = 'S5';
    def4.outletB = 'S6';
    e = 1e-6;
    def4.phi = [e, e, 1-e];

    def5.type = 'Purge';
    def5.inlet = 'S6';
    def5.recycle = 'S7';
    def5.purge = 'Sp';
    def5.beta = 0.95;

    cfg.unitDefs = {def1, def2, def3, def4, def5};
    cfg.maxIter = 250;
    cfg.tolAbs = 1e-9;
end

function assertNearZero(values, tol, msg)
    maxAbs = max(abs(values(:)));
    assert(maxAbs < tol, '%s (max|res|=%.3e, tol=%.3e)', msg, maxAbs, tol);
end

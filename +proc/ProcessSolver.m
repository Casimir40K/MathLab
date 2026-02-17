classdef ProcessSolver < handle
    properties
        streams
        units
        ns

        maxIter = 60
        tolAbs  = 1e-9
        fdEps   = 1e-7
        fdScheme string = "forward"   % forward|central|mixed
        fdCentralColumns double = []   % used when fdScheme="mixed"

        % Jacobian controls
        kFD = 6
        enableBroyden logical = true
        broydenMinStepNorm2 = 1e-20
        broydenMinRcond = 1e-14

        % Weighted residual controls (W * r, W * J)
        equationWeights double = []
        defaultResidualScale = 1
        flowResidualScale = 1
        temperatureResidualScale = 1
        pressureResidualScale = 1
        useWeightedNormForConvergence logical = true

        % Auto-scale: derive per-equation weights from initial residual
        % magnitudes so that all equations contribute equally to the norm.
        autoScale logical = false
        autoScaleMinMagnitude double = 1e-6

        % Jacobian refresh trigger when convergence stalls
        stallRatioThreshold = 0.9
        stallIterWindow = 3

        % Optional high-level settings bundle; fields matching solver
        % properties are applied at solve() start.
        solverSettings struct = struct()

        % Remove unit-level normalization residuals when y is already
        % constrained by softmax parameterization in unpackUnknowns().
        removeRedundantNormalizationConstraints logical = true

        printToConsole = false
        consoleStride  = 10

        damping = 1.0

        % Safety bounds
        nDotMin = 1e-12
        nDotMax = 1e8
        TMin    = 1
        TMax    = 5000
        PMin    = 1
        PMax    = 1e9

        % Captured log lines for UI
        logLines string = strings(0,1)

        % Convergence history (populated during solve)
        residualHistory double = []
        weightedResidualHistory double = []
        stepHistory     double = []
        alphaHistory    double = []

        % Runtime counter (including line-search and FD probes)
        residualEvalCount double = 0

        % Optional callback: called each iteration as iterCallback(iter, rNorm)
        % Set this before calling solve() to get real-time updates.
        iterCallback = []   % function_handle or empty

        % Hidden debug controls (off by default)
        debug logical = false
        debugLevel double = 2
        debugTopN double = 10
        debugEvery double = 0
        debugOut double = 1
        debugEqNames logical = true
    end

    properties (Dependent)
        verbose
    end

    properties (Access = private)
        map
        zMin
        zMax
    end

    methods
        function obj = ProcessSolver(streams, units)
            obj.streams = streams;
            obj.units   = units;
            obj.ns      = numel(streams{1}.y);
            obj.zMin = log(obj.nDotMin);
            obj.zMax = log(obj.nDotMax);
            obj.logLines = strings(0,1);
        end

        function v = get.verbose(obj), v = obj.printToConsole; end
        function set.verbose(obj, v),  obj.printToConsole = logical(v); end

        function solve(obj)
            obj.applySolverSettingsStruct();
            dbg = obj.resolveDebugOptions();

            obj.logLines = strings(0,1);
            obj.residualHistory = [];
            obj.weightedResidualHistory = [];
            obj.stepHistory     = [];
            obj.alphaHistory    = [];

            obj.residualEvalCount = 0;

            nDisabled = obj.configureNormalizationConstraints();
            if obj.removeRedundantNormalizationConstraints
                obj.log('Normalization constraints disabled on %d unit(s) (y uses softmax parameterization).', nDisabled);
            else
                obj.log('Normalization constraints kept on all units.');
            end

            [x, obj.map] = obj.packUnknowns();
            eqNames = obj.buildEquationLabels();

            vars = string({obj.map.var});
            obj.log('Packed unknowns: %d total (%d T, %d P)', ...
                numel(x), sum(vars=="T"), sum(vars=="P"));

            [r, ok] = obj.tryResiduals(x);
            if ~ok
                error('Initial residual returned NaN/Inf. Check initial guesses (n_dot,y,T,P).');
            end
            w = obj.buildEquationWeights(eqNames, numel(r), r);
            if obj.autoScale
                obj.log('Auto-scaling enabled: weights derived from initial |r| (minMag=%.1e, wRange=[%.2e, %.2e])', ...
                    obj.autoScaleMinMagnitude, min(w), max(w));
            end
            r0u = norm(r);
            r0w = norm(w .* r);
            obj.residualHistory(end+1) = r0u;
            obj.weightedResidualHistory(end+1) = r0w;
            obj.stepHistory(end+1)     = NaN;
            obj.alphaHistory(end+1)    = NaN;

            obj.log('Initial ||r|| = %.6e, ||W*r|| = %.6e (unknowns=%d, eqs=%d)', r0u, r0w, numel(x), numel(r));

            % Fire callback for initial state
            if obj.useWeightedNormForConvergence
                obj.fireCallback(0, r0w);
            else
                obj.fireCallback(0, r0u);
            end

            J = [];
            forceFD = true;
            stallCount = 0;
            disableBroydenOnce = false;

            for k = 1:obj.maxIter
                rnU = norm(r);
                rnW = norm(w .* r);
                rnConv = rnU;
                if obj.useWeightedNormForConvergence
                    rnConv = rnW;
                end
                if rnConv < obj.tolAbs
                    obj.residualHistory(end+1) = rnU;
                    obj.weightedResidualHistory(end+1) = rnW;
                    obj.stepHistory(end+1)     = 0;
                    obj.alphaHistory(end+1)    = 0;
                    obj.log('Converged at iter %d: ||r||=%.6e, ||W*r||=%.6e (resEvals=%d)', k, rnU, rnW, obj.residualEvalCount);
                    obj.fireCallback(k, rnConv);
                    break
                end

                doFD = forceFD || isempty(J) || mod(k-1, max(1,obj.kFD)) == 0;
                if doFD
                    J  = obj.fdJacobianSafe(x, r);
                    jacobianMode = "FD";
                    forceFD = false;
                else
                    jacobianMode = "REUSE";
                end

                dx = obj.solveLinearLM(J, -r, w);

                if any(~isfinite(dx))
                    error('dx contains NaN/Inf. Model may be ill-conditioned.');
                end

                [accepted, x_new, r_new, alpha, bt, stagnationReject] = obj.backtrackingLineSearch(x, dx, rnW, w);
                if ~accepted
                    if stagnationReject
                        obj.log('Iter %3d: stagnation reject (no strict ||W*r|| decrease found in line search).', k);
                    end

                    % Fallback: discard reused/Broyden Jacobian and retry with
                    % a fresh finite-difference Jacobian at the current state.
                    J  = obj.fdJacobianSafe(x, r);
                    jacobianMode = "FD-RETRY";
                    forceFD = false;

                    dx = obj.solveLinearLM(J, -r, w);
                    [accepted, x_new, r_new, alpha, bt, stagnationReject] = obj.backtrackingLineSearch(x, dx, rnW, w);

                    if ~accepted && stagnationReject
                        obj.log('Iter %3d: stagnation reject persisted after FD retry.', k);
                    end

                    if ~accepted
                        error('Line search failed at iteration %d.', k);
                    end
                end

                % Accepted step
                s = x_new - x;
                rPrev = r;
                x = x_new;
                r = r_new;

                % Update Jacobian after accepted step
                if obj.enableBroyden && ~disableBroydenOnce
                    [J, broydenAccepted] = obj.tryBroydenUpdate(J, s, r - rPrev);
                    if broydenAccepted
                        jacobianMode = jacobianMode + "+BROYDEN";
                    else
                        forceFD = true;
                        jacobianMode = jacobianMode + "+BROYDEN-SKIP";
                    end
                elseif disableBroydenOnce
                    disableBroydenOnce = false;
                    jacobianMode = jacobianMode + "+BROYDEN-OFF";
                end

                rnWNew = norm(w .* r);
                if rnWNew / max(rnW, eps) > obj.stallRatioThreshold
                    stallCount = stallCount + 1;
                else
                    stallCount = 0;
                end
                if stallCount >= max(1, round(obj.stallIterWindow))
                    forceFD = true;
                    disableBroydenOnce = true;
                    stallCount = 0;
                    obj.log('Stall detected at iter %d (ratio=%.3f). Forcing FD rebuild and skipping Broyden next step.', ...
                        k, rnWNew / max(rnW, eps));
                end

                % Record history
                obj.residualHistory(end+1) = rnU;
                obj.weightedResidualHistory(end+1) = rnW;
                obj.stepHistory(end+1)     = norm(dx);
                obj.alphaHistory(end+1)    = alpha;

                relRnU = rnU / max(r0u, eps);
                relRnW = rnW / max(r0w, eps);
                obj.log('Iter %3d: ||r||=%.4e (rel=%.3e)  ||W*r||=%.4e (rel=%.3e)  ||dx||=%.3e  alpha=%.3e  bt=%d  J=%s', ...
                    k, rnU, relRnU, rnW, relRnW, norm(dx), alpha, bt, jacobianMode);

                if dbg.level >= 1
                    obj.debugPrintIter(k, rnW, r, dx, alpha, bt, dbg);
                    if dbg.level >= 3 && dbg.every > 0 && mod(k, dbg.every) == 0
                        obj.debugPrintTopResiduals(r, dbg, eqNames, sprintf('iter %d', k));
                    end
                    if dbg.level >= 2 && dbg.every > 0 && mod(k, dbg.every) == 0
                        obj.debugPrintMixerCompositionConsistency(r, dbg, sprintf('iter %d', k));
                    end
                end

                % Fire callback for real-time plotting
                obj.fireCallback(k, rnConv);



                if k == obj.maxIter
                    finalR = norm(r);
                    finalRW = norm(w .* r);
                    obj.residualHistory(end+1) = finalR;
                    obj.weightedResidualHistory(end+1) = finalRW;
                    obj.stepHistory(end+1) = NaN;
                    obj.alphaHistory(end+1) = NaN;
                    obj.log('Max iterations reached. Final ||r||=%.6e, ||W*r||=%.6e (resEvals=%d)', finalR, finalRW, obj.residualEvalCount);
                    if obj.useWeightedNormForConvergence
                        obj.fireCallback(k+1, finalRW);
                    else
                        obj.fireCallback(k+1, finalR);
                    end
                    warning('Max iterations reached. Final ||r||=%.6e, ||W*r||=%.6e', finalR, finalRW);
                end
            end

            if dbg.level >= 2
                obj.debugPrintTopResiduals(r, dbg, eqNames, 'solver exit');
                obj.debugPrintMixerCompositionConsistency(r, dbg, 'solver exit');
            end

            if ~obj.printToConsole && ~isempty(obj.logLines)
                fprintf('%s\n', obj.logLines(end));
            end

            obj.unpackUnknowns(x);
        end

        function T = streamTable(obj)
            N = numel(obj.streams);
            names = strings(N,1); n_dot = nan(N,1);
            TT = nan(N,1); PP = nan(N,1); Y = nan(N,obj.ns);
            for i = 1:N
                s = obj.streams{i};
                names(i) = string(s.name);
                n_dot(i) = s.n_dot; TT(i) = s.T; PP(i) = s.P;
                Y(i,:)   = s.y(:).';
            end
            T = table(names, n_dot, TT, PP);
            for j = 1:obj.ns
                T.(sprintf('y_%s', obj.streams{1}.species{j})) = Y(:,j);
            end
        end
    end

    methods (Access = private)
        function applySolverSettingsStruct(obj)
            if isempty(obj.solverSettings) || ~isstruct(obj.solverSettings)
                return
            end
            fn = fieldnames(obj.solverSettings);
            for i = 1:numel(fn)
                if isprop(obj, fn{i})
                    obj.(fn{i}) = obj.solverSettings.(fn{i});
                end
            end
        end

        function nDisabled = configureNormalizationConstraints(obj)
            nDisabled = 0;
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                if isprop(unit, 'includeNormalizationConstraints')
                    unit.includeNormalizationConstraints = ~obj.removeRedundantNormalizationConstraints;
                    if obj.removeRedundantNormalizationConstraints
                        nDisabled = nDisabled + 1;
                    end
                end
            end
        end

        function [J, accepted] = tryBroydenUpdate(obj, J, s, y)
            accepted = false;
            s2 = s.' * s;
            if ~(isfinite(s2) && s2 > obj.broydenMinStepNorm2)
                return
            end

            Js = J * s;
            u = (y - Js) / s2;
            Jcand = J + u * s.';

            if any(~isfinite(Jcand(:)))
                return
            end

            n = size(Jcand,2);
            JTJ = Jcand.' * Jcand;
            lambda = 1e-12 * max(1, trace(JTJ) / max(1,n));
            rc = rcond(JTJ + lambda * eye(n));
            if ~isfinite(rc) || rc < obj.broydenMinRcond
                return
            end

            J = Jcand;
            accepted = true;
        end

        function fireCallback(obj, iter, rNorm)
            if ~isempty(obj.iterCallback) && isa(obj.iterCallback, 'function_handle')
                try
                    obj.iterCallback(iter, rNorm);
                catch
                    % Don't let a callback crash the solver
                end
            end
        end

        function log(obj, msg, varargin)
            line = string(sprintf(msg, varargin{:}));
            obj.logLines(end+1,1) = line;
            if obj.printToConsole
                k = numel(obj.logLines);
                if obj.consoleStride <= 1 || mod(k, obj.consoleStride) == 0
                    fprintf('%s\n', line);
                end
            end
        end

        function [r, ok] = tryResiduals(obj, x)
            obj.residualEvalCount = obj.residualEvalCount + 1;
            obj.unpackUnknowns(x);
            r = [];
            for u = 1:numel(obj.units)
                ru = obj.units{u}.equations();
                r  = [r; ru(:)];
            end
            ok = all(isfinite(r));
        end

        function dbg = resolveDebugOptions(obj)
            dbg = struct( ...
                'level', max(0, floor(obj.debugLevel)), ...
                'topN', max(1, floor(obj.debugTopN)), ...
                'every', max(0, floor(obj.debugEvery)), ...
                'out', obj.debugOut, ...
                'eqNames', logical(obj.debugEqNames));

            if obj.debug && dbg.level < 1
                dbg.level = 1;
            end

            if isstruct(obj.solverSettings) && isfield(obj.solverSettings, 'debugStruct')
                ds = obj.solverSettings.debugStruct;
                if isstruct(ds)
                    if isfield(ds, 'level'),   dbg.level = max(dbg.level, floor(ds.level)); end
                    if isfield(ds, 'topN'),    dbg.topN = max(1, floor(ds.topN)); end
                    if isfield(ds, 'every'),   dbg.every = max(0, floor(ds.every)); end
                    if isfield(ds, 'out'),     dbg.out = ds.out; end
                    if isfield(ds, 'eqNames'), dbg.eqNames = logical(ds.eqNames); end
                end
            end

            envLevel = str2double(getenv('MATHLAB_DEBUG'));
            if isfinite(envLevel) && envLevel > 0
                dbg.level = max(dbg.level, floor(envLevel));
            end
        end

        function debugPrintIter(obj, iter, rn2, r, dx, alpha, bt, dbg)
            rnInf = norm(r, inf);
            dxn = norm(dx, 2);
            [maxVal, maxIdx] = max(abs(r));
            if isempty(maxIdx), maxIdx = 0; maxVal = NaN; maxSigned = NaN;
            else, maxSigned = r(maxIdx);
            end

            fprintf(dbg.out, 'Iter %3d: ||r||2=%.3e  ||r||inf=%.3e  ||dx||=%.3e  alpha=%.3e  bt=%d  maxEq=%d (|r|=%.3e, r=%+.3e)\n', ...
                iter, rn2, rnInf, dxn, alpha, bt, maxIdx, maxVal, maxSigned);
        end

        function debugPrintTopResiduals(obj, r, dbg, eqNames, context)
            if isempty(r)
                return
            end

            n = min(numel(r), dbg.topN);
            [~, order] = sort(abs(r), 'descend');
            topIdx = order(1:n);

            fprintf(dbg.out, 'Top %d residual components (%s):\n', n, context);
            for i = 1:n
                idx = topIdx(i);
                label = sprintf('eq %4d', idx);
                if dbg.eqNames && idx <= numel(eqNames) && strlength(eqNames(idx)) > 0
                    label = char(eqNames(idx));
                end
                fprintf(dbg.out, '  [%3d] %-40s : %+.3e\n', idx, label, r(idx));
            end
        end

        function eqNames = buildEquationLabels(obj)
            eqNames = strings(0,1);
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                unitResiduals = unit.equations();
                nEq = numel(unitResiduals);

                labels = strings(nEq,1);
                if ismethod(unit, 'equationLabels')
                    try
                        labels = string(unit.equationLabels());
                    catch
                        labels = strings(nEq,1);
                    end
                end

                if numel(labels) ~= nEq
                    labels = strings(nEq,1);
                end

                unitName = class(unit);
                if ismethod(unit, 'describe')
                    try
                        unitName = string(unit.describe());
                    catch
                        unitName = string(class(unit));
                    end
                end

                for i = 1:nEq
                    if strlength(labels(i)) == 0
                        labels(i) = sprintf('%s: eq %d', char(unitName), i);
                    end
                end
                eqNames = [eqNames; labels(:)];
            end
        end

        function J = fdJacobianSafe(obj, x, r0)
            n = numel(x); m = numel(r0);
            J = zeros(m,n);
            for k = 1:n
                step = obj.fdEps * max(1, abs(x(k)));
                doCentral = obj.useCentralDifferenceForColumn(k);

                if doCentral
                    xPlus = x;
                    xMinus = x;
                    xPlus(k) = xPlus(k) + step;
                    xMinus(k) = xMinus(k) - step;
                    [rPlus, okPlus] = obj.tryResiduals(xPlus);
                    [rMinus, okMinus] = obj.tryResiduals(xMinus);

                    if okPlus && okMinus
                        J(:,k) = (rPlus - rMinus) / (2 * step);
                    elseif okPlus
                        J(:,k) = (rPlus - r0) / step;
                    elseif okMinus
                        J(:,k) = (r0 - rMinus) / step;
                    else
                        J(:,k) = 0;
                    end
                else
                    x2 = x;
                    x2(k) = x2(k) + step;
                    [r2, ok] = obj.tryResiduals(x2);
                    if ~ok
                        J(:,k) = 0;
                    else
                        J(:,k) = (r2 - r0) / step;
                    end
                end
            end
        end

        function [accepted, x_new, r_new, alpha, bt, stagnationReject] = backtrackingLineSearch(obj, x, dx, rnW, w)
            alpha = obj.damping;
            bt = 0;
            accepted = false;
            stagnationReject = false;
            x_new = x;
            r_new = nan(size(dx));

            decreaseTol = 1e-8;
            noiseTol = 1e-14;
            strictTarget = rnW * (1 - decreaseTol);
            flatSeen = false;

            while bt < 30
                xCand = x + alpha*dx;
                [rCand, okCand] = obj.tryResiduals(xCand);
                if okCand
                    rnWCand = norm(w .* rCand);
                    if rnWCand <= strictTarget
                        accepted = true;
                        x_new = xCand;
                        r_new = rCand;
                        return
                    end

                    if rnWCand <= rnW * (1 + noiseTol)
                        flatSeen = true;
                    end
                end
                alpha = alpha * 0.5;
                bt = bt + 1;
                if alpha < 1e-10
                    break;
                end
            end

            stagnationReject = flatSeen;
        end

        function dx = solveLinearLM(~, J, b, w)
            Jw = J .* w;
            bw = b .* w;
            n = size(J,2);
            JTJ = Jw.' * Jw;  JTb = Jw.' * bw;
            lambda = 1e-6 * max(1, trace(JTJ)/max(1,n));
            I = eye(n);
            for it = 1:12
                dx = (JTJ + lambda*I) \ JTb;
                if all(isfinite(dx)), return; end
                lambda = lambda * 10;
            end
            dx = zeros(n,1);
        end

        function tf = useCentralDifferenceForColumn(obj, idx)
            scheme = lower(strtrim(char(obj.fdScheme)));
            switch scheme
                case 'central'
                    tf = true;
                case 'mixed'
                    tf = any(idx == obj.fdCentralColumns);
                otherwise
                    tf = false;
            end
        end

        function w = buildEquationWeights(obj, eqNames, nEq, r0)
            if ~isempty(obj.equationWeights)
                ew = obj.equationWeights(:);
                if isscalar(ew)
                    w = repmat(ew, nEq, 1);
                elseif numel(ew) == nEq
                    w = ew;
                else
                    error('equationWeights must be scalar or length %d.', nEq);
                end
            elseif obj.autoScale && nargin >= 4 && ~isempty(r0)
                % Derive per-equation weights from initial residual
                % magnitudes so that all equations contribute equally.
                w = ones(nEq, 1);
                for i = 1:nEq
                    mag = abs(r0(min(i, numel(r0))));
                    w(i) = 1 / max(mag, obj.autoScaleMinMagnitude);
                end
            else
                w = ones(nEq,1) / max(obj.defaultResidualScale, eps);
                for i = 1:nEq
                    lbl = lower(char(eqNames(min(i, numel(eqNames)))));
                    if contains(lbl, 'pressure') || contains(lbl, ' p') || contains(lbl, 'dp')
                        w(i) = 1 / max(obj.pressureResidualScale, eps);
                    elseif contains(lbl, 'temp') || contains(lbl, 'enthalpy') || contains(lbl, 'energy')
                        w(i) = 1 / max(obj.temperatureResidualScale, eps);
                    elseif contains(lbl, 'flow') || contains(lbl, 'mass') || contains(lbl, 'mole') || contains(lbl, 'n_dot')
                        w(i) = 1 / max(obj.flowResidualScale, eps);
                    end
                end
            end
            w(~isfinite(w) | w <= 0) = 1;
        end

        function [x, map] = packUnknowns(obj)
            x = []; map = struct('streamIndex',{},'var',{},'subIndex',{},'unitIndex',{},'bounds',{},'owner',{},'field',{});
            for si = 1:numel(obj.streams)
                s = obj.streams{si};
                if obj.isUnknownScalar(s,'n_dot')
                    nd = obj.safeInit(s.n_dot,1.0);
                    x(end+1,1) = log(max(nd,obj.nDotMin));
                    map(end+1) = struct('streamIndex',si,'var','z','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
                if obj.anyYUnknown(s)
                    [packIdx, a0] = obj.initialCompositionLogits(s);

                    % Gauge-fixing for composition logits:
                    % Only (nUnknownComponents-1) logits are packed and one
                    % unknown component is anchored at zero in unpackUnknowns().
                    % This removes the softmax shift invariance so we do not
                    % re-introduce redundant composition DOFs.
                    for j = 1:numel(packIdx)
                        x(end+1,1) = a0(j);
                        map(end+1) = struct('streamIndex',si,'var','a','subIndex',packIdx(j), 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                    end
                end
                knownT = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'T')&&...
                    islogical(s.known.T)&&isscalar(s.known.T)&&s.known.T;
                if ~knownT
                    x(end+1,1) = obj.safeInit(s.T,300);
                    map(end+1) = struct('streamIndex',si,'var','T','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
                knownP = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'P')&&...
                    islogical(s.known.P)&&isscalar(s.known.P)&&s.known.P;
                if ~knownP
                    x(end+1,1) = obj.safeInit(s.P,1e5);
                    map(end+1) = struct('streamIndex',si,'var','P','subIndex',[], 'unitIndex',NaN,'bounds',[-Inf Inf],'owner',[],'field','');
                end
            end

            % Optional unit-level manipulated unknowns (e.g., Adjust blocks)
            for ui = 1:numel(obj.units)
                u = obj.units{ui};
                if ~ismethod(u, 'unknownSpecs')
                    continue;
                end
                specs = u.unknownSpecs();
                if isempty(specs)
                    continue;
                end
                if ~isstruct(specs)
                    error('unknownSpecs() for %s must return a struct array.', class(u));
                end
                for k = 1:numel(specs)
                    s = specs(k);
                    x(end+1,1) = obj.safeInit(s.initial, 0); %#ok<AGROW>
                    map(end+1) = struct( ...
                        'streamIndex', NaN, ...
                        'var', 'u', ...
                        'subIndex', obj.structFieldOr(s, 'index', NaN), ...
                        'unitIndex', ui, ...
                        'bounds', [obj.structFieldOr(s, 'lower', -Inf), obj.structFieldOr(s, 'upper', Inf)], ...
                        'owner', s.owner, ...
                        'field', s.field); %#ok<GFLD>
                end
            end
        end

        function unpackUnknowns(obj, x)
            z = nan(numel(obj.streams),1);
            a = nan(numel(obj.streams), obj.ns);
            for k = 1:numel(obj.map)
                si=obj.map(k).streamIndex; var=obj.map(k).var; sub=obj.map(k).subIndex;
                switch var
                    case 'z', z(si) = x(k);
                    case 'a', a(si,sub) = x(k);
                    case 'T', obj.streams{si}.T = x(k);
                    case 'P', obj.streams{si}.P = x(k);
                    case 'u'
                        xi = min(max(x(k), obj.map(k).bounds(1)), obj.map(k).bounds(2));
                        owner = obj.map(k).owner;
                        field = obj.map(k).field;
                        if ~isprop(owner, field)
                            error('Unknown manipulated field "%s" on %s.', field, class(owner));
                        end
                        if isnan(sub)
                            owner.(field) = xi;
                        else
                            arr = owner.(field);
                            arr(sub) = xi;
                            owner.(field) = arr;
                        end
                end
            end
            for si = 1:numel(obj.streams)
                s = obj.streams{si};
                if ~isnan(z(si))
                    s.n_dot = exp(min(max(z(si),obj.zMin),obj.zMax));
                end
                if obj.anyYUnknown(s)
                    s.y = obj.reconstructComposition(s, a(si,:));
                end
                if ~isnan(s.T), s.T = min(max(s.T,obj.TMin),obj.TMax); end
                if ~isnan(s.P), s.P = min(max(s.P,obj.PMin),obj.PMax); end
            end
        end


        function v = structFieldOr(~, s, fieldName, defaultValue)
            if isfield(s, fieldName)
                v = s.(fieldName);
            else
                v = defaultValue;
            end
        end

        function tf = isUnknownScalar(~,s,fn)
            if isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,fn)
                v=s.known.(fn);
                if islogical(v)&&isscalar(v), tf=~v; else, tf=true; end
            else, tf=true;
            end
        end

        function tf = anyYUnknown(obj,s)
            unknownIdx = obj.unknownCompositionIndices(s);
            tf = ~isempty(unknownIdx);
        end

        function knownMask = compositionKnownMask(obj, s)
            if isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'y')
                ky=s.known.y;
                if islogical(ky)&&numel(ky)==obj.ns
                    knownMask = logical(reshape(ky,1,[]));
                    return;
                end
            end

            knownMask = false(1,obj.ns);
        end

        function unknownIdx = unknownCompositionIndices(obj, s)
            knownMask = obj.compositionKnownMask(s);
            unknownIdx = find(~knownMask);
        end

        function [packIdx, a0] = initialCompositionLogits(obj, s)
            unknownIdx = obj.unknownCompositionIndices(s);
            nUnknown = numel(unknownIdx);
            if nUnknown <= 1
                packIdx = [];
                a0 = [];
                return;
            end

            y0 = s.y;
            if isempty(y0) || any(~isfinite(y0)) || numel(y0) ~= obj.ns
                y0 = ones(1,obj.ns) / obj.ns;
            end
            y0 = max(reshape(y0,1,[]), 0);

            knownMask = obj.compositionKnownMask(s);
            knownSum = sum(y0(knownMask));
            remaining = max(1 - knownSum, 0);

            yUnknown = y0(unknownIdx);
            yUnknown = max(yUnknown, 0);
            if sum(yUnknown) <= 0
                yUnknown = ones(1,nUnknown) / nUnknown;
            else
                yUnknown = yUnknown / sum(yUnknown);
            end

            % Represent unknown composition as remaining * softmax(aUnknown).
            % Pack only first (nUnknown-1) entries and anchor last one to 0.
            if remaining > 0
                pUnknown = yUnknown;
            else
                pUnknown = ones(1,nUnknown) / nUnknown;
            end

            aUnknown = log(max(pUnknown,1e-12));
            anchor = aUnknown(end);
            aUnknown = aUnknown - anchor;

            packIdx = unknownIdx(1:end-1);
            a0 = aUnknown(1:end-1).';
        end

        function y = reconstructComposition(obj, s, packedA)
            y = s.y;
            if isempty(y) || any(~isfinite(y)) || numel(y) ~= obj.ns
                y = ones(obj.ns,1) / obj.ns;
            end
            y = reshape(y,[],1);

            knownMask = obj.compositionKnownMask(s);
            unknownIdx = find(~knownMask);
            nUnknown = numel(unknownIdx);
            if nUnknown == 0
                y = obj.normalizeSimplex(y);
                obj.warnIfCompositionNotNormalized(s, y);
                return;
            end

            knownSum = sum(y(knownMask));
            remaining = 1 - knownSum;

            if nUnknown == 1
                y(unknownIdx) = remaining;
                y = y / sum(y);
                obj.warnIfCompositionNotNormalized(s, y);
                return;
            end

            % softmax() expects only the packed free logits (nUnknown-1).
            % It appends the anchored final logit internally.
            aUnknown = zeros(nUnknown-1,1);
            packIdx = unknownIdx(1:end-1);
            for j = 1:numel(packIdx)
                comp = packIdx(j);
                if isfinite(packedA(comp))
                    aUnknown(j) = packedA(comp);
                end
            end

            % Gauge-fixed softmax: last unknown component is anchored to 0,
            % so only (nUnknown-1) independent logits are required.
            y(unknownIdx) = remaining .* obj.softmax(aUnknown);
            y = y / sum(y);
            obj.warnIfCompositionNotNormalized(s, y);
        end

        function v = safeInit(~,c,fb)
            if isempty(c)||isnan(c), v=fb; else, v=c; end
        end

        function y = softmax(~,aPacked)
            % Reconstruct full logits by anchoring the final component at 0,
            % then apply stable shift-by-max softmax.
            aFull = [aPacked(:); 0];
            aFull = aFull - max(aFull);
            e = exp(aFull);
            y = e / sum(e);
        end

        function y = normalizeSimplex(~,y)
            y = y(:);
            s = sum(y);
            if ~isfinite(s) || s == 0
                y = ones(numel(y),1) / numel(y);
            else
                y = y / s;
            end
        end

        function warnIfCompositionNotNormalized(obj, s, y)
            if obj.debugLevel < 1
                return
            end
            sumY = sum(y);
            delta = sumY - 1;
            if isfinite(delta) && abs(delta) > 1e-10
                fprintf(obj.debugOut, 'WARN composition normalization drift: stream=%s, sum(y)-1=%+.3e\n', ...
                    string(s.name), delta);
            end
        end

        function debugPrintMixerCompositionConsistency(obj, r, dbg, context)
            [mixer, dominantEq, dominantVal] = obj.findDominantMixer(r);
            if isempty(mixer)
                return
            end

            fprintf(dbg.out, 'Composition normalization + component-flow consistency (%s):\n', context);
            fprintf(dbg.out, '  Dominant mixer: %s (eq %d, r=%+.3e)\n', string(mixer.describe()), dominantEq, dominantVal);

            streamsToReport = [mixer.inlets(:); {mixer.outlet}];
            for i = 1:numel(streamsToReport)
                s = streamsToReport{i};
                y = s.y(:);
                sumY = sum(y);
                minY = min(y);
                maxY = max(y);
                compFlowSum = sum(s.n_dot .* y);
                diffFlow = compFlowSum - s.n_dot;
                fprintf(dbg.out, '  %s: sum(y)=%.15f (sum(y)-1=%+.3e) min=%.6e max=%.6e\n', ...
                    string(s.name), sumY, sumY - 1, minY, maxY);
                fprintf(dbg.out, '      n_dot=%.6e, sum(n_dot*y)=%.6e, diff=%+.3e\n', ...
                    s.n_dot, compFlowSum, diffFlow);
            end
        end

        function [dominantMixer, eqIdx, eqVal] = findDominantMixer(obj, r)
            dominantMixer = [];
            eqIdx = NaN;
            eqVal = NaN;
            cursor = 1;
            bestAbs = -Inf;
            for u = 1:numel(obj.units)
                unit = obj.units{u};
                nEq = numel(unit.equations());
                idx = cursor:(cursor + nEq - 1);
                if isa(unit, 'proc.units.Mixer') && ~isempty(idx)
                    [localAbs, localPos] = max(abs(r(idx)));
                    if isfinite(localAbs) && localAbs > bestAbs
                        bestAbs = localAbs;
                        dominantMixer = unit;
                        eqIdx = idx(localPos);
                        eqVal = r(eqIdx);
                    end
                end
                cursor = cursor + nEq;
            end
        end
    end
end

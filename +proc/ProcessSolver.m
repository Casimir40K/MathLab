classdef ProcessSolver < handle
    properties
        streams
        units
        ns

        maxIter = 60
        tolAbs  = 1e-9
        fdEps   = 1e-7

        % Jacobian controls
        kFD = 6
        enableBroyden logical = true
        broydenMinStepNorm2 = 1e-20
        broydenMinRcond = 1e-14

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
        stepHistory     double = []
        alphaHistory    double = []

        % Runtime counter (including line-search and FD probes)
        residualEvalCount double = 0

        % Optional callback: called each iteration as iterCallback(iter, rNorm)
        % Set this before calling solve() to get real-time updates.
        iterCallback = []   % function_handle or empty

        % Hidden debug controls (off by default)
        debug logical = false
        debugLevel double = 0
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
            r0 = norm(r);
            obj.residualHistory(end+1) = r0;
            obj.stepHistory(end+1)     = NaN;
            obj.alphaHistory(end+1)    = NaN;

            obj.log('Initial ||r|| = %.6e (unknowns=%d, eqs=%d)', r0, numel(x), numel(r));

            % Fire callback for initial state
            obj.fireCallback(0, r0);

            J = [];
            forceFD = true;

            for k = 1:obj.maxIter
                rn = norm(r);
                if rn < obj.tolAbs
                    obj.residualHistory(end+1) = rn;
                    obj.stepHistory(end+1)     = 0;
                    obj.alphaHistory(end+1)    = 0;
                    obj.log('Converged at iter %d: ||r||=%.6e (resEvals=%d)', k, rn, obj.residualEvalCount);
                    obj.fireCallback(k, rn);
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

                dx = obj.solveLinearLM(J, -r);

                if any(~isfinite(dx))
                    error('dx contains NaN/Inf. Model may be ill-conditioned.');
                end

                [accepted, x_new, r_new, alpha, bt] = obj.backtrackingLineSearch(x, dx, rn);
                if ~accepted
                    % Fallback: discard reused/Broyden Jacobian and retry with
                    % a fresh finite-difference Jacobian at the current state.
                    J  = obj.fdJacobianSafe(x, r);
                    jacobianMode = "FD-RETRY";
                    forceFD = false;

                    dx = obj.solveLinearLM(J, -r);
                    [accepted, x_new, r_new, alpha, bt] = obj.backtrackingLineSearch(x, dx, rn);

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
                if obj.enableBroyden
                    [J, broydenAccepted] = obj.tryBroydenUpdate(J, s, r - rPrev);
                    if broydenAccepted
                        jacobianMode = jacobianMode + "+BROYDEN";
                    else
                        forceFD = true;
                        jacobianMode = jacobianMode + "+BROYDEN-SKIP";
                    end
                end

                % Record history
                obj.residualHistory(end+1) = rn;
                obj.stepHistory(end+1)     = norm(dx);
                obj.alphaHistory(end+1)    = alpha;

                relRn = rn / max(r0, eps);
                obj.log('Iter %3d: ||r||=%.4e (rel=%.3e)  ||dx||=%.3e  alpha=%.3e  bt=%d  J=%s', ...
                    k, rn, relRn, norm(dx), alpha, bt, jacobianMode);

                if dbg.level >= 1
                    obj.debugPrintIter(k, rn, r, dx, alpha, bt, dbg);
                    if dbg.level >= 3 && dbg.every > 0 && mod(k, dbg.every) == 0
                        obj.debugPrintTopResiduals(r, dbg, eqNames, sprintf('iter %d', k));
                    end
                end

                % Fire callback for real-time plotting
                obj.fireCallback(k, rn);



                if k == obj.maxIter
                    finalR = norm(r);
                    obj.residualHistory(end+1) = finalR;
                    obj.stepHistory(end+1) = NaN;
                    obj.alphaHistory(end+1) = NaN;
                    obj.log('Max iterations reached. Final ||r||=%.6e (resEvals=%d)', finalR, obj.residualEvalCount);
                    obj.fireCallback(k+1, finalR);
                    warning('Max iterations reached. Final ||r||=%.6e', finalR);
                end
            end

            if dbg.level >= 2
                obj.debugPrintTopResiduals(r, dbg, eqNames, 'solver exit');
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
                x2 = x;
                step = obj.fdEps * max(1, abs(x(k)));
                x2(k) = x2(k) + step;
                [r2, ok] = obj.tryResiduals(x2);
                if ~ok, J(:,k) = 0;
                else,   J(:,k) = (r2 - r0) / step;
                end
            end
        end

        function [accepted, x_new, r_new, alpha, bt] = backtrackingLineSearch(obj, x, dx, rn)
            alpha = obj.damping;
            bt = 0;
            accepted = false;
            x_new = x;
            r_new = nan(size(dx));

            while bt < 30
                xCand = x + alpha*dx;
                [rCand, okCand] = obj.tryResiduals(xCand);
                if okCand && norm(rCand) <= rn
                    accepted = true;
                    x_new = xCand;
                    r_new = rCand;
                    return
                end
                alpha = alpha * 0.5;
                bt = bt + 1;
                if alpha < 1e-10
                    break;
                end
            end
        end

        function dx = solveLinearLM(~, J, b)
            n = size(J,2);
            JTJ = J.' * J;  JTb = J.' * b;
            lambda = 1e-6 * max(1, trace(JTJ)/max(1,n));
            I = eye(n);
            for it = 1:12
                dx = (JTJ + lambda*I) \ JTb;
                if all(isfinite(dx)), return; end
                lambda = lambda * 10;
            end
            dx = zeros(n,1);
        end

        function [x, map] = packUnknowns(obj)
            x = []; map = struct('streamIndex',{},'var',{},'subIndex',{});
            for si = 1:numel(obj.streams)
                s = obj.streams{si};
                if obj.isUnknownScalar(s,'n_dot')
                    nd = obj.safeInit(s.n_dot,1.0);
                    x(end+1,1) = log(max(nd,obj.nDotMin));
                    map(end+1) = struct('streamIndex',si,'var','z','subIndex',[]);
                end
                if obj.anyYUnknown(s)
                    y0 = s.y;
                    if any(isnan(y0))||isempty(y0), y0=ones(1,obj.ns)/obj.ns; end
                    y0 = obj.normalizeSimplex(y0);
                    a0 = log(max(y0,1e-12));
                    for j = 1:obj.ns
                        x(end+1,1) = a0(j);
                        map(end+1) = struct('streamIndex',si,'var','a','subIndex',j);
                    end
                end
                knownT = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'T')&&...
                    islogical(s.known.T)&&isscalar(s.known.T)&&s.known.T;
                if ~knownT
                    x(end+1,1) = obj.safeInit(s.T,300);
                    map(end+1) = struct('streamIndex',si,'var','T','subIndex',[]);
                end
                knownP = isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'P')&&...
                    islogical(s.known.P)&&isscalar(s.known.P)&&s.known.P;
                if ~knownP
                    x(end+1,1) = obj.safeInit(s.P,1e5);
                    map(end+1) = struct('streamIndex',si,'var','P','subIndex',[]);
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
                end
            end
            for si = 1:numel(obj.streams)
                s = obj.streams{si};
                if ~isnan(z(si))
                    s.n_dot = exp(min(max(z(si),obj.zMin),obj.zMax));
                end
                if any(~isnan(a(si,:)))
                    s.y = obj.softmax(a(si,:));
                end
                if ~isnan(s.T), s.T = min(max(s.T,obj.TMin),obj.TMax); end
                if ~isnan(s.P), s.P = min(max(s.P,obj.PMin),obj.PMax); end
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
            ns=obj.ns;
            if isprop(s,'known')&&isstruct(s.known)&&isfield(s.known,'y')
                ky=s.known.y;
                if islogical(ky)&&numel(ky)==ns, tf=any(~ky); else, tf=true; end
            else, tf=true;
            end
        end

        function v = safeInit(~,c,fb)
            if isempty(c)||isnan(c), v=fb; else, v=c; end
        end

        function y = softmax(~,a)
            a=a-max(a); ea=exp(a); y=ea/sum(ea);
        end

        function y = normalizeSimplex(~,y)
            y=max(y,1e-12); y=y/sum(y);
        end
    end
end

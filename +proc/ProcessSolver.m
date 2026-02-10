classdef ProcessSolver < handle
    properties
        streams
        units
        ns

        maxIter = 60
        tolAbs  = 1e-9
        fdEps   = 1e-7

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

        % === Convergence history (populated after solve) ===
        residualHistory double = []   % ||r|| at each iteration
        stepHistory     double = []   % ||dx|| at each iteration
        alphaHistory    double = []   % line search step size
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
            obj.logLines = strings(0,1);
            obj.residualHistory = [];
            obj.stepHistory     = [];
            obj.alphaHistory    = [];

            [x, obj.map] = obj.packUnknowns();

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

            for k = 1:obj.maxIter
                [r, ok] = obj.tryResiduals(x);
                if ~ok
                    error('Residual became NaN/Inf at iteration %d.', k);
                end

                rn = norm(r);
                if rn < obj.tolAbs
                    obj.residualHistory(end+1) = rn;
                    obj.stepHistory(end+1)     = 0;
                    obj.alphaHistory(end+1)    = 0;
                    obj.log('Converged at iter %d: ||r||=%.6e', k, rn);
                    break
                end

                J  = obj.fdJacobianSafe(x, r);
                dx = obj.solveLinearLM(J, -r);

                if any(~isfinite(dx))
                    error('dx contains NaN/Inf. Model may be ill-conditioned.');
                end

                alpha = obj.damping;
                bt = 0;
                while bt < 30
                    x_new = x + alpha*dx;
                    [r_new, okNew] = obj.tryResiduals(x_new);
                    if okNew && norm(r_new) <= rn, break; end
                    alpha = alpha * 0.5;
                    bt = bt + 1;
                    if alpha < 1e-10
                        error('Line search failed at iteration %d.', k);
                    end
                end

                % Record history
                obj.residualHistory(end+1) = rn;
                obj.stepHistory(end+1)     = norm(dx);
                obj.alphaHistory(end+1)    = alpha;

                obj.log('Iter %3d: ||r||=%.4e  ||dx||=%.3e  alpha=%.3e  bt=%d', ...
                    k, rn, norm(dx), alpha, bt);

                x = x + alpha*dx;

                if k == obj.maxIter
                    finalR = norm(obj.tryResiduals(x));
                    obj.residualHistory(end+1) = finalR;
                    obj.stepHistory(end+1) = NaN;
                    obj.alphaHistory(end+1) = NaN;
                    obj.log('Max iterations reached. Final ||r||=%.6e', finalR);
                    warning('Max iterations reached. Final ||r||=%.6e', finalR);
                end
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
            obj.unpackUnknowns(x);
            r = [];
            for u = 1:numel(obj.units)
                ru = obj.units{u}.equations();
                r  = [r; ru(:)];
            end
            ok = all(isfinite(r));
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

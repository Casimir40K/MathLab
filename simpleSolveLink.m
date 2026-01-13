function x = simpleSolveLink(S1, S2, link, tol)
    if nargin < 4
        tol = 1e-12;
    end

    % Initial guess for unknowns
    x = [S1.n_dot, S1.T, S1.P, S1.y];

    iter = 0;
    maxIter = 50;
    while iter < maxIter
        iter = iter + 1;

        % Assign guess into S2
        S2.n_dot = x(1);
        S2.T     = x(2);
        S2.P     = x(3);
        S2.y     = x(4:6);

        % Residuals
        F = link.equations();

        % Update guess (for a Link, the solution is exact)
        % F = out - in → new x = x - F
        x = x - F;

        % Check convergence
        if max(abs(F)) < tol
            break
        end
    end
end


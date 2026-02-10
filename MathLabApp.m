classdef MathLabApp < handle
    %MATHLABAPP  Steady-state process solver GUI
    %
    %   app = MathLabApp;
    %   app = MathLabApp('config.mat');    % load a saved config on startup
    %
    %   Requires the +proc package folder in the same directory.

    % =====================================================================
    %  UI HANDLES
    % =====================================================================
    properties (Access = private)
        Fig
        Tabs
        StatusBar

        % -- Tab 1: Species & Config --
        SpeciesTab
        SpeciesTable
        AddSpeciesBtn
        RemoveSpeciesBtn
        NewSpeciesName
        NewSpeciesMW
        ApplySpeciesBtn
        SaveConfigBtn
        LoadConfigBtn
        InstructionsArea

        % -- Tab 2: Streams --
        StreamsTab
        StreamValTable
        StreamKnownTable
        AddStreamBtn
        RemoveStreamBtn
        StreamNameField
        StreamDOFLabel       % live DOF on this tab too

        % -- Tab 3: Units & Flowsheet --
        UnitsTab
        UnitsListBox
        AddUnitDropDown
        AddUnitBtn
        ConfigUnitBtn
        RemoveUnitBtn
        FlowsheetAxes
        UnitDOFLabel         % live DOF on this tab too

        % -- Tab 4: Solve --
        SolveTab
        MaxIterField
        TolField
        SolveBtn
        DOFLabel
        ResidualAxes
        LogArea

        % -- Tab 5: Results --
        ResultsTab
        ResultsTable

        % -- Tab 6: Sensitivity --
        SensTab
        SensParamDropDown
        SensUnitDropDown
        SensMinField
        SensMaxField
        SensNptsField
        SensOutputStreamDD
        SensOutputFieldDD
        SensRunBtn
        SensAxes
        SensMaxIterField
        SensTolField
        SensStatusLabel

        % -- Project & Output --
        ProjectTitleField
        SaveResultsBtn
    end

    % =====================================================================
    %  MODEL STATE
    % =====================================================================
    properties (Access = private)
        speciesNames cell   = {'H2','O2','H2O'}
        speciesMW    double = [2.016, 32.00, 18.015]

        streams  cell = {}
        units    cell = {}
        unitDefs cell = {}    % serializable unit definitions for save/load
        lastSolver = []
        lastFlowsheet = []
        projectTitle char = 'MathLab_Project'
    end

    % =====================================================================
    %  CONSTRUCTOR
    % =====================================================================
    methods (Access = public)
        function app = MathLabApp(configFile)
            app.buildUI();
            if nargin >= 1 && ~isempty(configFile)
                app.loadConfig(configFile);
            else
                app.refreshSpeciesTable();
                app.applySpecies();
            end
        end
    end

    % =====================================================================
    %  UI CONSTRUCTION
    % =====================================================================
    methods (Access = private)

        function buildUI(app)
            app.Fig = uifigure('Name','MathLab — Process Solver', ...
                'Position',[60 40 1120 720], 'Resize','on', ...
                'Color',[0.96 0.96 0.97]);

            gl = uigridlayout(app.Fig, [2 1], ...
                'RowHeight',{'1x', 24}, 'Padding',[0 0 0 0], 'RowSpacing',0);

            app.Tabs = uitabgroup(gl);
            app.Tabs.Layout.Row = 1;

            app.StatusBar = uilabel(gl, 'Text','  Ready', ...
                'FontColor',[0.25 0.25 0.25], ...
                'BackgroundColor',[0.88 0.89 0.91], ...
                'FontSize', 12);
            app.StatusBar.Layout.Row = 2;

            app.buildSpeciesTab();
            app.buildStreamsTab();
            app.buildUnitsTab();
            app.buildSolveTab();
            app.buildResultsTab();
            app.buildSensitivityTab();
        end

        % ================================================================
        %  TAB 1: SPECIES & CONFIG
        % ================================================================
        function buildSpeciesTab(app)
            t = uitab(app.Tabs, 'Title', ' Species ');
            app.SpeciesTab = t;

            gl = uigridlayout(t, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',12);

            % --- Left: species editor + save/load ---
            leftP = uipanel(gl, 'Title','Species & Properties', 'FontWeight','bold');
            leftG = uigridlayout(leftP, [7 1], ...
                'RowHeight',{'1x', 30, 30, 36, 30, 36, 36}, 'Padding',[8 8 8 8], 'RowSpacing',4);

            app.SpeciesTable = uitable(leftG, 'ColumnEditable',[true true], ...
                'ColumnName', {'Name','MW (kg/kmol)'}, ...
                'CellEditCallback', @(src,evt) app.onSpeciesTableEdit(src,evt));

            % Add row
            addR = uigridlayout(leftG, [1 3], 'ColumnWidth',{'1x','1x',80}, ...
                'Padding',[0 0 0 0]);
            app.NewSpeciesName = uieditfield(addR,'text','Placeholder','Name');
            app.NewSpeciesMW   = uieditfield(addR,'numeric','Value',28.0,'Limits',[0.001 1e6]);
            app.AddSpeciesBtn  = uibutton(addR,'push','Text','+ Add', ...
                'ButtonPushedFcn',@(~,~) app.addSpeciesRow());

            app.RemoveSpeciesBtn = uibutton(leftG,'push','Text','Remove Selected Row', ...
                'ButtonPushedFcn',@(~,~) app.removeSpeciesRow());

            app.ApplySpeciesBtn = uibutton(leftG,'push', ...
                'Text','Apply Species (resets streams & units)', ...
                'FontWeight','bold', 'BackgroundColor',[0.82 0.90 1.0], ...
                'ButtonPushedFcn',@(~,~) app.applySpecies());

            % Project title row
            titleRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{110,'1x'}, ...
                'Padding',[0 0 0 0]);
            uilabel(titleRow,'Text','Project title:','FontWeight','bold');
            app.ProjectTitleField = uieditfield(titleRow,'text', ...
                'Value',app.projectTitle, ...
                'ValueChangedFcn',@(src,~) app.onProjectTitleChanged(src));

            % Save / Load row
            slRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[0 0 0 0]);
            app.SaveConfigBtn = uibutton(slRow,'push','Text','Save Config', ...
                'Icon','', 'FontWeight','bold', ...
                'BackgroundColor',[0.92 0.95 0.85], ...
                'ButtonPushedFcn',@(~,~) app.saveConfigToOutput());
            app.LoadConfigBtn = uibutton(slRow,'push','Text','Load Config...', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.95 0.92 0.85], ...
                'ButtonPushedFcn',@(~,~) app.loadConfigDialog());

            % Save results row
            resRow = uigridlayout(leftG, [1 1], 'ColumnWidth',{'1x'}, ...
                'Padding',[0 0 0 0]);
            app.SaveResultsBtn = uibutton(resRow,'push','Text','Save Results', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.85 0.92 0.95], ...
                'ButtonPushedFcn',@(~,~) app.saveResultsToOutput());

            % --- Right: instructions ---
            rightP = uipanel(gl, 'Title','How to Use MathLab', 'FontWeight','bold');
            rightG = uigridlayout(rightP, [1 1], 'Padding',[8 8 8 8]);
            app.InstructionsArea = uitextarea(rightG, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',12, 'Value', { ...
                'WORKFLOW'; ...
                '========'; ...
                ''; ...
                '1. SPECIES  — define names + MW, click Apply.'; ...
                '2. STREAMS  — add streams, set values & known flags.'; ...
                '3. UNITS    — add unit ops, pick stream connections.'; ...
                '4. SOLVE    — check DOF, click Solve, see residuals.'; ...
                '5. RESULTS  — full solved stream table.'; ...
                '6. SENSITIVITY — sweep a parameter.'; ...
                ''; ...
                'SAVE / LOAD'; ...
                '==========='; ...
                'Save Config: saves your entire flowsheet setup'; ...
                '  to a .mat file you can reload later.'; ...
                'Load Config: restores species, streams, units.'; ...
                ''; ...
                'COMMAND LINE (no GUI):'; ...
                '  [T, solver] = runFromConfig(''myfile.mat'');'; ...
                '  This solves and saves solver to output/.'; ...
                ''; ...
                'TIPS'; ...
                '===='; ...
                '- Mole fractions (y) must sum to 1.0'; ...
                '- All streams need finite positive guesses'; ...
                '- Watch the DOF counter on Streams/Units tabs'; ...
                '- Feed streams: all values Known'});
        end

        % ================================================================
        %  TAB 2: STREAMS
        % ================================================================
        function buildStreamsTab(app)
            t = uitab(app.Tabs, 'Title', ' Streams ');
            app.StreamsTab = t;
            gl = uigridlayout(t, [4 1], 'RowHeight',{24,'1x','1x',36}, ...
                'Padding',[12 12 12 12], 'RowSpacing',6);

            % DOF bar
            app.StreamDOFLabel = uilabel(gl, 'Text','DOF: —', ...
                'FontWeight','bold', 'FontSize',13, ...
                'BackgroundColor',[0.92 0.93 0.95]);
            app.StreamDOFLabel.Layout.Row = 1;

            % Stream values
            topP = uipanel(gl, 'Title', ...
                'Stream Values (double-click cell to edit)', 'FontWeight','bold');
            topP.Layout.Row = 2;
            topG = uigridlayout(topP, [1 1], 'Padding',[4 4 4 4]);
            app.StreamValTable = uitable(topG, 'ColumnEditable',true, ...
                'CellEditCallback', @(src,evt) app.onStreamValEdit(src,evt));

            % Known flags
            midP = uipanel(gl, 'Title', ...
                'Known Flags (checked = you specify it, unchecked = solver finds it)', ...
                'FontWeight','bold');
            midP.Layout.Row = 3;
            midG = uigridlayout(midP, [1 1], 'Padding',[4 4 4 4]);
            app.StreamKnownTable = uitable(midG, 'ColumnEditable',true, ...
                'CellEditCallback', @(src,evt) app.onKnownEdit(src,evt));

            % Add/Remove bar
            botG = uigridlayout(gl, [1 4], ...
                'ColumnWidth',{100, 120, 110, 140}, 'Padding',[0 0 0 0]);
            botG.Layout.Row = 4;
            uilabel(botG,'Text','New stream:','FontWeight','bold');
            app.StreamNameField = uieditfield(botG,'text','Value','S1');
            app.AddStreamBtn = uibutton(botG,'push','Text','Add Stream', ...
                'BackgroundColor',[0.82 0.95 0.82], ...
                'ButtonPushedFcn',@(~,~) app.addStreamFromUI());
            app.RemoveStreamBtn = uibutton(botG,'push','Text','Remove Selected', ...
                'BackgroundColor',[1.0 0.88 0.88], ...
                'ButtonPushedFcn',@(~,~) app.removeSelectedStream());
        end

        % ================================================================
        %  TAB 3: UNITS & FLOWSHEET
        % ================================================================
        function buildUnitsTab(app)
            t = uitab(app.Tabs, 'Title', ' Units & Flowsheet ');
            app.UnitsTab = t;
            gl = uigridlayout(t, [2 2], 'ColumnWidth',{'1x','1x'}, ...
                'RowHeight',{24, '1x'}, 'Padding',[12 12 12 12], 'RowSpacing',6);

            % DOF bar spanning both columns
            app.UnitDOFLabel = uilabel(gl, 'Text','DOF: —', ...
                'FontWeight','bold', 'FontSize',13, ...
                'BackgroundColor',[0.92 0.93 0.95]);
            app.UnitDOFLabel.Layout.Row = 1;
            app.UnitDOFLabel.Layout.Column = [1 2];

            % Left: unit list + controls
            leftP = uipanel(gl, 'Title','Unit Operations', 'FontWeight','bold');
            leftP.Layout.Row = 2; leftP.Layout.Column = 1;
            leftG = uigridlayout(leftP, [3 1], 'RowHeight',{'1x',30,30}, ...
                'Padding',[6 6 6 6], 'RowSpacing',4);

            app.UnitsListBox = uilistbox(leftG, 'Items',{}, 'Value',{});

            addRow = uigridlayout(leftG, [1 2], ...
                'ColumnWidth',{140,'1x'}, 'Padding',[0 0 0 0]);
            app.AddUnitDropDown = uidropdown(addRow, ...
                'Items',{'Mixer','Link','Reactor','StoichiometricReactor','ConversionReactor','YieldReactor','EquilibriumReactor','Separator','Purge','Splitter','Recycle','Bypass','Manifold'},'Value','Mixer');
            app.AddUnitBtn = uibutton(addRow,'push','Text','Add Unit...', ...
                'BackgroundColor',[0.82 0.95 0.82], ...
                'ButtonPushedFcn',@(~,~) app.addUnitFromUI());

            actRow = uigridlayout(leftG, [1 2], ...
                'ColumnWidth',{'1x','1x'}, 'Padding',[0 0 0 0]);
            app.ConfigUnitBtn = uibutton(actRow,'push','Text','Configure...', ...
                'ButtonPushedFcn',@(~,~) app.configureSelectedUnit());
            app.RemoveUnitBtn = uibutton(actRow,'push','Text','Remove', ...
                'BackgroundColor',[1.0 0.88 0.88], ...
                'ButtonPushedFcn',@(~,~) app.removeSelectedUnit());

            % Right: flowsheet diagram
            rightP = uipanel(gl, 'Title','Process Flow Diagram', 'FontWeight','bold');
            rightP.Layout.Row = 2; rightP.Layout.Column = 2;
            rightG = uigridlayout(rightP, [1 1], 'Padding',[4 4 4 4]);
            app.FlowsheetAxes = uiaxes(rightG);
            title(app.FlowsheetAxes, 'Add units to see diagram');
            app.FlowsheetAxes.XTick = []; app.FlowsheetAxes.YTick = [];
            box(app.FlowsheetAxes, 'on');
        end

        % ================================================================
        %  TAB 4: SOLVE  (rebuilt — simple 4-row layout)
        % ================================================================
        function buildSolveTab(app)
            t = uitab(app.Tabs, 'Title', ' Solve ');
            app.SolveTab = t;

            % 4 rows: DOF bar | controls row | convergence plot | log
            gl = uigridlayout(t, [4 1], ...
                'RowHeight', {28, 40, '2x', '1x'}, ...
                'Padding', [12 12 12 12], 'RowSpacing', 8);

            % --- Row 1: DOF status ---
            app.DOFLabel = uilabel(gl, 'Text', 'DOF: — (add streams and units first)', ...
                'FontWeight','bold', 'FontSize', 14, ...
                'BackgroundColor',[0.92 0.93 0.95]);
            app.DOFLabel.Layout.Row = 1;

            % --- Row 2: solver controls ---
            ctrlG = uigridlayout(gl, [1 5], ...
                'ColumnWidth', {120, 80, 120, 110, 180}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8);
            ctrlG.Layout.Row = 2;

            uilabel(ctrlG, 'Text', 'Max Iterations:', ...
                'HorizontalAlignment','right', 'FontWeight','bold');
            app.MaxIterField = uieditfield(ctrlG, 'numeric', 'Value', 200, ...
                'Limits', [1 100000], 'RoundFractionalValues', 'on');
            uilabel(ctrlG, 'Text', 'Tolerance (abs):', ...
                'HorizontalAlignment','right', 'FontWeight','bold');
            app.TolField = uieditfield(ctrlG, 'numeric', 'Value', 1e-9, ...
                'Limits', [1e-15 1]);
            app.SolveBtn = uibutton(ctrlG, 'push', 'Text', 'SOLVE', ...
                'FontWeight','bold', 'FontSize', 16, ...
                'BackgroundColor', [0.18 0.62 0.30], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~,~) app.runSolver());

            % --- Row 3: convergence plot ---
            plotP = uipanel(gl, 'Title','Convergence (real-time)', 'FontWeight','bold');
            plotP.Layout.Row = 3;
            plotG = uigridlayout(plotP, [1 1], 'Padding',[4 4 4 4]);
            app.ResidualAxes = uiaxes(plotG);
            ylabel(app.ResidualAxes, '||residual||');
            xlabel(app.ResidualAxes, 'Iteration');
            app.ResidualAxes.YScale = 'log';
            grid(app.ResidualAxes, 'on');
            title(app.ResidualAxes, 'Click SOLVE to start');

            % --- Row 4: solver log ---
            logP = uipanel(gl, 'Title','Solver Log', 'FontWeight','bold');
            logP.Layout.Row = 4;
            logG = uigridlayout(logP, [1 1], 'Padding',[4 4 4 4]);
            app.LogArea = uitextarea(logG, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',11);
        end

        % ================================================================
        %  TAB 5: RESULTS
        % ================================================================
        function buildResultsTab(app)
            t = uitab(app.Tabs, 'Title', ' Results ');
            app.ResultsTab = t;
            gl = uigridlayout(t, [1 1], 'Padding',[12 12 12 12]);
            app.ResultsTable = uitable(gl);
        end

        % ================================================================
        %  TAB 6: SENSITIVITY
        % ================================================================
        function buildSensitivityTab(app)
            t = uitab(app.Tabs, 'Title', ' Sensitivity ');
            app.SensTab = t;
            gl = uigridlayout(t, [2 1], 'RowHeight',{190,'1x'}, ...
                'Padding',[12 12 12 12], 'RowSpacing',8);

            % Top: controls in a 5-row, 4-col grid
            topP = uipanel(gl, 'Title','Setup', 'FontWeight','bold');
            topP.Layout.Row = 1;
            topG = uigridlayout(topP, [5 4], ...
                'ColumnWidth', {130, '1x', 130, '1x'}, ...
                'RowHeight', {26, 26, 26, 26, 26}, ...
                'Padding', [8 8 8 8], 'RowSpacing', 4, 'ColumnSpacing', 8);

            % Row 1
            uilabel(topG,'Text','Sweep param:','FontWeight','bold');
            app.SensParamDropDown = uidropdown(topG, ...
                'Items',{'Reactor conversion','Purge beta', ...
                         'Separator phi(1)','Stream n_dot','Stream T','Stream P'}, ...
                'Value','Reactor conversion', ...
                'ValueChangedFcn',@(~,~) app.onSensParamChanged());
            uilabel(topG,'Text','Target unit/stream:','FontWeight','bold');
            app.SensUnitDropDown = uidropdown(topG,'Items',{'(none)'},'Value','(none)', ...
                'ValueChangedFcn',@(~,~) app.validateSensSelection());

            % Row 2
            uilabel(topG,'Text','Min / Max / Pts:','FontWeight','bold');
            rangeG = uigridlayout(topG, [1 3], ...
                'ColumnWidth',{'1x','1x',60}, 'Padding',[0 0 0 0]);
            app.SensMinField = uieditfield(rangeG,'numeric','Value',0.1);
            app.SensMaxField = uieditfield(rangeG,'numeric','Value',0.9);
            app.SensNptsField = uieditfield(rangeG,'numeric','Value',15, ...
                'Limits',[2 200],'RoundFractionalValues','on');
            uilabel(topG,'Text','Output stream:','FontWeight','bold');
            app.SensOutputStreamDD = uidropdown(topG,'Items',{'(none)'},'Value','(none)');

            % Row 3
            uilabel(topG,'Text','Output field:','FontWeight','bold');
            app.SensOutputFieldDD = uidropdown(topG, ...
                'Items',{'n_dot','T','P','y(1)','y(2)','y(3)'},'Value','n_dot');
            uilabel(topG,'Text','');
            uilabel(topG,'Text','');

            % Row 4: solver parameters
            uilabel(topG,'Text','Max iterations:','FontWeight','bold');
            app.SensMaxIterField = uieditfield(topG,'numeric','Value',300, ...
                'Limits',[1 100000],'RoundFractionalValues','on');
            uilabel(topG,'Text','Tolerance (abs):','FontWeight','bold');
            app.SensTolField = uieditfield(topG,'numeric','Value',1e-8, ...
                'Limits',[1e-15 1]);

            % Row 5: status + run button
            app.SensStatusLabel = uilabel(topG,'Text','', ...
                'FontColor',[0.5 0.5 0.5],'FontAngle','italic');
            app.SensStatusLabel.Layout.Column = [1 2];
            uilabel(topG,'Text','');
            app.SensRunBtn = uibutton(topG,'push','Text','Run Sensitivity', ...
                'FontWeight','bold','BackgroundColor',[0.25 0.50 0.80],'FontColor','w', ...
                'ButtonPushedFcn',@(~,~) app.runSensitivity());

            % Bottom: plot
            botP = uipanel(gl, 'Title','Results', 'FontWeight','bold');
            botP.Layout.Row = 2;
            botG = uigridlayout(botP, [1 1], 'Padding',[4 4 4 4]);
            app.SensAxes = uiaxes(botG);
            title(app.SensAxes, 'Run analysis to see results');
            grid(app.SensAxes, 'on');
        end
    end

    % =====================================================================
    %  SPECIES CALLBACKS
    % =====================================================================
    methods (Access = private)

        function refreshSpeciesTable(app)
            N = numel(app.speciesNames);
            data = cell(N, 2);
            for i = 1:N
                data{i,1} = app.speciesNames{i};
                data{i,2} = app.speciesMW(i);
            end
            app.SpeciesTable.Data = data;
        end

        function onSpeciesTableEdit(app, ~, evt)
            r = evt.Indices(1); c = evt.Indices(2);
            if r < 1 || r > numel(app.speciesNames), return; end
            if c == 1,     app.speciesNames{r} = evt.NewData;
            elseif c == 2, app.speciesMW(r) = evt.NewData;
            end
        end

        function addSpeciesRow(app)
            nm = strtrim(app.NewSpeciesName.Value);
            if isempty(nm), return; end
            app.speciesNames{end+1} = nm;
            app.speciesMW(end+1) = app.NewSpeciesMW.Value;
            app.NewSpeciesName.Value = '';
            app.refreshSpeciesTable();
        end

        function removeSpeciesRow(app)
            sel = app.SpeciesTable.Selection;
            if isempty(sel), return; end
            r = sel(1);
            if r >= 1 && r <= numel(app.speciesNames)
                app.speciesNames(r) = [];
                app.speciesMW(r) = [];
                app.refreshSpeciesTable();
            end
        end

        function applySpecies(app)
            if isempty(app.speciesNames)
                uialert(app.Fig, 'Species list cannot be empty.', 'Error'); return;
            end
            app.streams = {};
            app.units = {};
            app.unitDefs = {};
            app.lastSolver = [];

            % Default feed stream
            app.addStreamInternal('Feed');
            s = app.streams{1};
            s.n_dot = 10; s.T = 300; s.P = 1e5;
            ns = numel(app.speciesNames);
            y0 = zeros(1,ns); y0(1) = 1;
            s.y = y0;
            s.known.n_dot = true; s.known.T = true; s.known.P = true;
            s.known.y(:) = true;

            app.refreshStreamTables();
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.updateSensDropdowns();
            app.StreamNameField.Value = 'S2';
            app.setStatus(sprintf('Species set: {%s}. Feed created.', ...
                strjoin(app.speciesNames,', ')));
        end
    end

    % =====================================================================
    %  STREAM CALLBACKS
    % =====================================================================
    methods (Access = private)

        function addStreamInternal(app, name)
            s = proc.Stream(string(name), app.speciesNames);
            s.n_dot = 1; s.T = 300; s.P = 1e5;
            s.y = ones(1, numel(app.speciesNames)) / numel(app.speciesNames);
            app.streams{end+1} = s;
        end

        function addStreamFromUI(app)
            name = strtrim(app.StreamNameField.Value);
            if isempty(name)
                uialert(app.Fig,'Enter a name.','Error'); return;
            end
            for i = 1:numel(app.streams)
                if strcmp(string(app.streams{i}.name), name)
                    uialert(app.Fig,sprintf('"%s" exists.',name),'Duplicate'); return;
                end
            end
            app.addStreamInternal(name);
            app.refreshStreamTables();
            app.updateDOF();
            app.updateSensDropdowns();
            % Auto-increment
            tok = regexp(name, '^([A-Za-z_]*)(\d+)$','tokens');
            if ~isempty(tok)
                app.StreamNameField.Value = sprintf('%s%d',tok{1}{1},str2double(tok{1}{2})+1);
            end
        end

        function removeSelectedStream(app)
            sel = app.StreamValTable.Selection;
            if isempty(sel), return; end
            row = sel(1);
            if row >= 1 && row <= numel(app.streams)
                app.streams(row) = [];
                app.refreshStreamTables();
                app.updateDOF();
                app.updateSensDropdowns();
            end
        end

        function refreshStreamTables(app)
            ns = numel(app.speciesNames);
            N = numel(app.streams);

            colNames = [{'Name','n_dot','T (K)','P (Pa)'}, ...
                cellfun(@(sp) ['y_' sp], app.speciesNames, 'Uni',false)];
            data = cell(N, 4+ns);
            for i = 1:N
                s = app.streams{i};
                data{i,1} = char(string(s.name));
                data{i,2} = s.n_dot; data{i,3} = s.T; data{i,4} = s.P;
                for j = 1:ns
                    if j <= numel(s.y), data{i,4+j} = s.y(j);
                    else,               data{i,4+j} = 0;
                    end
                end
            end
            app.StreamValTable.Data = data;
            app.StreamValTable.ColumnName = colNames;
            app.StreamValTable.ColumnEditable = [false, true(1, 3+ns)];

            knData = cell(N, 5);
            for i = 1:N
                s = app.streams{i};
                knData{i,1} = char(string(s.name));
                knData{i,2} = s.known.n_dot;
                knData{i,3} = s.known.T;
                knData{i,4} = s.known.P;
                knData{i,5} = all(s.known.y);
            end
            app.StreamKnownTable.Data = knData;
            app.StreamKnownTable.ColumnName = {'Name','n_dot','T','P','y (all)'};
            app.StreamKnownTable.ColumnEditable = [false, true, true, true, true];
        end

        function onStreamValEdit(app, ~, evt)
            row = evt.Indices(1); col = evt.Indices(2);
            if row < 1 || row > numel(app.streams), return; end
            s = app.streams{row};
            ns = numel(app.speciesNames);
            switch col
                case 2, s.n_dot = evt.NewData;
                case 3, s.T = evt.NewData;
                case 4, s.P = evt.NewData;
                otherwise
                    j = col - 4;
                    if j >= 1 && j <= ns, s.y(j) = evt.NewData; end
            end
        end

        function onKnownEdit(app, ~, evt)
            row = evt.Indices(1); col = evt.Indices(2);
            if row < 1 || row > numel(app.streams), return; end
            s = app.streams{row};
            val = logical(evt.NewData);
            switch col
                case 2, s.known.n_dot = val;
                case 3, s.known.T = val;
                case 4, s.known.P = val;
                case 5, s.known.y(:) = val;
            end
            app.updateDOF();
        end

        function syncStreamsFromTable(app)
            D = app.StreamValTable.Data;
            if isempty(D), return; end
            ns = numel(app.speciesNames);
            for i = 1:min(size(D,1), numel(app.streams))
                s = app.streams{i};
                s.n_dot = D{i,2}; s.T = D{i,3}; s.P = D{i,4};
                for j = 1:ns, s.y(j) = D{i,4+j}; end
            end
        end
    end

    % =====================================================================
    %  LIVE DOF
    % =====================================================================
    methods (Access = private)
        function updateDOF(app)
            if isempty(app.streams) || isempty(app.units)
                txt = 'DOF: add streams and units first';
                clr = [0.5 0.5 0.5];
            else
                fs = app.buildFlowsheet();
                [nU, nE] = fs.checkDOF('quiet',true);
                if nU == nE
                    txt = sprintf('DOF: %d unknowns = %d equations  (square — ready to solve)', nU, nE);
                    clr = [0.0 0.45 0.0];
                elseif nU > nE
                    txt = sprintf('DOF: %d unknowns, %d equations  (under-constrained, need %d more specs)', nU, nE, nU-nE);
                    clr = [0.75 0.45 0.0];
                else
                    txt = sprintf('DOF: %d unknowns, %d equations  (over-constrained by %d)', nU, nE, nE-nU);
                    clr = [0.75 0.0 0.0];
                end
            end

            % Update all DOF labels
            app.DOFLabel.Text = txt;
            app.DOFLabel.FontColor = clr;
            app.StreamDOFLabel.Text = txt;
            app.StreamDOFLabel.FontColor = clr;
            app.UnitDOFLabel.Text = txt;
            app.UnitDOFLabel.FontColor = clr;
        end

        function fs = buildFlowsheet(app)
            fs = proc.Flowsheet(app.speciesNames);
            for i = 1:numel(app.streams), fs.addStream(app.streams{i}); end
            for i = 1:numel(app.units),   fs.addUnit(app.units{i}); end
        end
    end

    % =====================================================================
    %  UNITS
    % =====================================================================
    methods (Access = private)

        function refreshUnitsListBox(app)
            items = cell(1, numel(app.units));
            for i = 1:numel(app.units)
                u = app.units{i};
                if ismethod(u,'describe')
                    items{i} = sprintf('[%d] %s', i, u.describe());
                else
                    items{i} = sprintf('[%d] %s', i, class(u));
                end
            end
            if isempty(items)
                app.UnitsListBox.Items = {'(no units — add one above)'};
                app.UnitsListBox.Value = {};
            else
                app.UnitsListBox.Items = items;
                app.UnitsListBox.Value = items(1);
            end
            app.updateSensDropdowns();
        end

        function addUnitFromUI(app)
            typ = app.AddUnitDropDown.Value;
            sNames = app.getStreamNames();
            if numel(sNames) < 2
                uialert(app.Fig,'Need at least 2 streams.','Error'); return;
            end
            switch typ
                case 'Link',      app.dialogLink(sNames);
                case 'Mixer',     app.dialogMixer(sNames);
                case 'Reactor',   app.dialogReactor(sNames);
                case 'StoichiometricReactor', app.dialogStoichiometricReactor(sNames);
                case 'ConversionReactor', app.dialogConversionReactor(sNames);
                case 'YieldReactor', app.dialogYieldReactor(sNames);
                case 'EquilibriumReactor', app.dialogEquilibriumReactor(sNames);
                case 'Separator', app.dialogSeparator(sNames);
                case 'Purge',     app.dialogPurge(sNames);
                case 'Splitter',  app.dialogSplitter(sNames);
                case 'Recycle',   app.dialogRecycle(sNames);
                case 'Bypass',    app.dialogBypass(sNames);
                case 'Manifold',  app.dialogManifold(sNames);
            end
        end

        function configureSelectedUnit(app)
            idx = app.getSelectedUnitIdx();
            if isempty(idx), return; end
            sNames = app.getStreamNames();
            cn = class(app.units{idx});
            if contains(cn,'Link'),      app.dialogLink(sNames,idx);
            elseif contains(cn,'Mixer'), app.dialogMixer(sNames,idx);
            elseif contains(cn,'StoichiometricReactor'), app.dialogStoichiometricReactor(sNames,idx);
            elseif contains(cn,'ConversionReactor'), app.dialogConversionReactor(sNames,idx);
            elseif contains(cn,'YieldReactor'), app.dialogYieldReactor(sNames,idx);
            elseif contains(cn,'EquilibriumReactor'), app.dialogEquilibriumReactor(sNames,idx);
            elseif contains(cn,'Reactor'), app.dialogReactor(sNames,idx);
            elseif contains(cn,'Separator'), app.dialogSeparator(sNames,idx);
            elseif contains(cn,'Purge'), app.dialogPurge(sNames,idx);
            elseif contains(cn,'Splitter'), app.dialogSplitter(sNames,idx);
            elseif contains(cn,'Recycle'), app.dialogRecycle(sNames,idx);
            elseif contains(cn,'Bypass'), app.dialogBypass(sNames,idx);
            elseif contains(cn,'Manifold'), app.dialogManifold(sNames,idx);
            end
        end

        function removeSelectedUnit(app)
            idx = app.getSelectedUnitIdx();
            if isempty(idx), return; end
            app.units(idx) = [];
            app.unitDefs(idx) = [];
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
        end

        function idx = getSelectedUnitIdx(app)
            idx = [];
            sel = app.UnitsListBox.Value;
            if isempty(sel) || isempty(app.units), return; end
            if iscell(sel), sel = sel{1}; end
            tok = regexp(sel,'^\[(\d+)\]','tokens');
            if isempty(tok), return; end
            idx = str2double(tok{1}{1});
            if idx < 1 || idx > numel(app.units), idx = []; end
        end

        function commitUnit(app, u, def, editIdx)
            if isempty(editIdx)
                app.units{end+1} = u;
                app.unitDefs{end+1} = def;
            else
                app.units{editIdx} = u;
                app.unitDefs{editIdx} = def;
            end
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
        end
    end

    % =====================================================================
    %  FLOWSHEET DIAGRAM
    % =====================================================================
    methods (Access = private)
        function refreshFlowsheetDiagram(app)
            ax = app.FlowsheetAxes;
            cla(ax);
            if isempty(app.units)
                title(ax,'Add units to see diagram'); return;
            end

            src = {}; tgt = {}; elbl = {};
            for i = 1:numel(app.units)
                u = app.units{i};
                uName = sprintf('U%d:%s', i, app.shortTypeName(u));
                cn = class(u);
                if contains(cn,'Link')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Mixer')
                    for k=1:numel(u.inlets)
                        src{end+1}=char(string(u.inlets{k}.name)); tgt{end+1}=uName; elbl{end+1}='';
                    end
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Reactor')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'Separator')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outletA.name)); elbl{end+1}='A';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outletB.name)); elbl{end+1}='B';
                elseif contains(cn,'Purge')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.recycle.name)); elbl{end+1}='rec';
                    src{end+1}=uName; tgt{end+1}=char(string(u.purge.name)); elbl{end+1}='pur';
                elseif contains(cn,'Splitter')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    for k=1:numel(u.outlets)
                        src{end+1}=uName; tgt{end+1}=char(string(u.outlets{k}.name)); elbl{end+1}=sprintf('out%d',k);
                    end
                elseif contains(cn,'Recycle')
                    src{end+1}=char(string(u.source.name)); tgt{end+1}=uName; elbl{end+1}='src';
                    src{end+1}=uName; tgt{end+1}=char(string(u.tear.name)); elbl{end+1}='tear';
                elseif contains(cn,'Bypass')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.processInlet.name)); elbl{end+1}='proc in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.bypassStream.name)); elbl{end+1}='bypass';
                    src{end+1}=char(string(u.processReturn.name)); tgt{end+1}=uName; elbl{end+1}='proc ret';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='out';
                elseif contains(cn,'Manifold')
                    for k=1:numel(u.inlets)
                        src{end+1}=char(string(u.inlets{k}.name)); tgt{end+1}=uName; elbl{end+1}=sprintf('in%d',k);
                    end
                    for k=1:numel(u.outlets)
                        src{end+1}=uName; tgt{end+1}=char(string(u.outlets{k}.name)); elbl{end+1}=sprintf('out%d',k);
                    end
                end
            end
            if isempty(src), title(ax,'No connections'); return; end

            G = digraph(src, tgt);
            nNames = G.Nodes.Name; nN = numel(nNames);
            nc = zeros(nN,3); ms = 8*ones(nN,1);
            for n=1:nN
                if startsWith(nNames{n},'U')
                    nc(n,:)=[0.2 0.5 0.8]; ms(n)=14;
                else
                    nc(n,:)=[0.85 0.33 0.1]; ms(n)=7;
                end
            end
            h = plot(ax,G,'Layout','layered','Direction','right', ...
                'EdgeLabel',elbl,'NodeColor',nc,'MarkerSize',ms, ...
                'NodeFontSize',9,'EdgeFontSize',8,'ArrowSize',10, ...
                'LineWidth',1.5,'NodeFontWeight','bold');

            % Distinct markers and colors per unit type
            unitColors = struct( ...
                'Mixer',    [0.20 0.60 0.30], ...
                'Link',     [0.40 0.40 0.40], ...
                'Reactor',  [0.85 0.20 0.20], ...
                'StoichiometricReactor', [0.85 0.20 0.20], ...
                'ConversionReactor', [0.85 0.20 0.20], ...
                'YieldReactor', [0.85 0.20 0.20], ...
                'EquilibriumReactor', [0.85 0.20 0.20], ...
                'Separator',[0.10 0.40 0.80], ...
                'Purge',    [0.70 0.40 0.80], ...
                'Splitter', [0.90 0.55 0.10], ...
                'Recycle',  [0.50 0.50 0.10], ...
                'Bypass',   [0.10 0.65 0.65], ...
                'Manifold', [0.35 0.25 0.70]);
            unitMarkers = struct( ...
                'Mixer',    'h', ...  % hexagon
                'Link',     's', ...  % square
                'Reactor',  'd', ...  % diamond
                'StoichiometricReactor', 'd', ...
                'ConversionReactor', 'd', ...
                'YieldReactor', 'd', ...
                'EquilibriumReactor', 'd', ...
                'Separator','^', ...  % triangle up
                'Purge',    'v', ...     % triangle down
                'Splitter', '>', ...
                'Recycle',  '<', ...
                'Bypass',   'p', ...
                'Manifold', 'o');
            for i = 1:numel(app.units)
                uName = sprintf('U%d:%s', i, app.shortTypeName(app.units{i}));
                uType = app.shortTypeName(app.units{i});
                nodeIdx = find(strcmp(nNames, uName));
                if ~isempty(nodeIdx) && isfield(unitMarkers, uType)
                    highlight(h, nodeIdx, ...
                        'Marker', unitMarkers.(uType), ...
                        'NodeColor', unitColors.(uType), ...
                        'MarkerSize', 16);
                end
            end

            title(ax,'Process Flow Diagram');
            ax.XTick=[]; ax.YTick=[];
        end
    end

    % =====================================================================
    %  UNIT DIALOGS
    % =====================================================================
    methods (Access = private)

        function dialogLink(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Link', 350, 140, ...
                {{'Inlet:','dropdown',sNames}, {'Outlet:','dropdown',sNames}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Link'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                u=proc.units.Link(app.findStream(def.inlet),app.findStream(def.outlet));
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogMixer(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Mixer', 420, 140, ...
                {{'Inlets (comma-sep):','text',strjoin(sNames(1:min(2,end)),', ')}, ...
                 {'Outlet:','dropdown',sNames}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                inN=cellfun(@(s)char(string(s.name)),u.inlets,'Uni',false);
                ctrls{1}.Value=strjoin(inN,', ');
                ctrls{2}.Value=char(string(u.outlet.name));
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                inNms=strtrim(strsplit(ctrls{1}.Value,','));
                inS={};
                for k=1:numel(inNms)
                    s=app.findStream(inNms{k});
                    if isempty(s)
                        uialert(d,sprintf('"%s" not found.',inNms{k}),'Error'); return;
                    end
                    inS{end+1}=s; %#ok
                end
                def.type='Mixer'; def.inlets=inNms; def.outlet=ctrls{2}.Value;
                u=proc.units.Mixer(inS,app.findStream(def.outlet));
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            spStr = strjoin(app.speciesNames,', ');

            d = uifigure('Name','Configure Reactor','Position',[250 180 500 380], ...
                'Resize','off','WindowStyle','modal');
            dg = uigridlayout(d,[8 2],'ColumnWidth',{170,'1x'}, ...
                'RowHeight',repmat({28},1,8),'Padding',[12 12 12 12],'RowSpacing',4);

            uilabel(dg,'Text','Inlet:','FontWeight','bold');
            ddIn = uidropdown(dg,'Items',sNames);
            uilabel(dg,'Text','Outlet:','FontWeight','bold');
            ddOut = uidropdown(dg,'Items',sNames);
            uilabel(dg,'Text','Conversion (0–1):','FontWeight','bold');
            efConv = uieditfield(dg,'numeric','Value',0.5,'Limits',[0 1]);
            lbl=uilabel(dg,'Text',sprintf('Species: %s (1..%d)',spStr,ns));
            lbl.FontColor=[0.4 0.4 0.4]; uilabel(dg,'Text','');
            uilabel(dg,'Text','Reactant indices:','FontWeight','bold');
            efReact = uieditfield(dg,'text','Value','1 2');
            uilabel(dg,'Text','Product indices:','FontWeight','bold');
            efProd = uieditfield(dg,'text','Value',num2str(ns));
            uilabel(dg,'Text','Stoich vector:','FontWeight','bold');
            efStoich = uieditfield(dg,'text','Value',num2str(zeros(1,ns)));

            btnG = uigridlayout(dg,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0]);
            btnG.Layout.Row=8; btnG.Layout.Column=[1 2];
            uibutton(btnG,'push','Text','OK','FontWeight','bold', ...
                'BackgroundColor',[0.82 0.95 0.82],'ButtonPushedFcn',@(~,~)okCb());
            uibutton(btnG,'push','Text','Cancel','ButtonPushedFcn',@(~,~)delete(d));

            if ~isempty(editIdx)
                u=app.units{editIdx};
                ddIn.Value=char(string(u.inlet.name));
                ddOut.Value=char(string(u.outlet.name));
                efConv.Value=u.conversion;
                r=u.reactions(1);
                efReact.Value=num2str(r.reactants);
                efProd.Value=num2str(r.products);
                efStoich.Value=num2str(r.stoich);
            elseif numel(sNames)>=2, ddOut.Value=sNames{2}; end

            function okCb()
                rxn.reactants=str2num(efReact.Value); %#ok
                rxn.products=str2num(efProd.Value); %#ok
                rxn.stoich=str2num(efStoich.Value); %#ok
                rxn.name="reaction";
                if isempty(rxn.reactants)||isempty(rxn.products)||numel(rxn.stoich)~=ns
                    uialert(d,sprintf('Stoich must have %d entries.',ns),'Error'); return;
                end
                def.type='Reactor'; def.inlet=ddIn.Value; def.outlet=ddOut.Value;
                def.conversion=efConv.Value; def.reactions=rxn;
                u=proc.units.Reactor(app.findStream(def.inlet),...
                    app.findStream(def.outlet),rxn,efConv.Value);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogStoichiometricReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Configure StoichiometricReactor', 520, 240, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Nu vector:','text',num2str(zeros(1,ns))}, ...
                 {'Extent mode (fixed/solve):','text','fixed'}, ...
                 {'Extent (if fixed):','numeric',0}, ...
                 {'Reference species index:','numeric',1}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=num2str(u.nu.');
                ctrls{4}.Value=u.extentMode;
                ctrls{5}.Value=u.extent;
                ctrls{6}.Value=u.referenceSpecies;
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error'); return;
                end
                def.type='StoichiometricReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.extentMode=strtrim(lower(ctrls{4}.Value));
                def.extent=ctrls{5}.Value; def.referenceSpecies=ctrls{6}.Value;
                u=proc.units.StoichiometricReactor(app.findStream(def.inlet), app.findStream(def.outlet), def.nu, ...
                    'extent', def.extent, 'extentMode', def.extentMode, 'referenceSpecies', def.referenceSpecies);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogConversionReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Configure ConversionReactor', 520, 240, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Nu vector:','text',num2str(zeros(1,ns))}, ...
                 {'Key species index:','numeric',1}, ...
                 {'Conversion mode (fixed/solve):','text','fixed'}, ...
                 {'Conversion X (if fixed):','numeric',0.5}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=num2str(u.nu.');
                ctrls{4}.Value=u.keySpecies;
                ctrls{5}.Value=u.conversionMode;
                ctrls{6}.Value=u.conversion;
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error'); return;
                end
                def.type='ConversionReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.keySpecies=ctrls{4}.Value;
                def.conversionMode=strtrim(lower(ctrls{5}.Value)); def.conversion=ctrls{6}.Value;
                u=proc.units.ConversionReactor(app.findStream(def.inlet), app.findStream(def.outlet), def.nu, ...
                    def.keySpecies, def.conversion, 'conversionMode', def.conversionMode);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogYieldReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure YieldReactor', 540, 250, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Basis species index (A):','numeric',1}, ...
                 {'Conversion mode (fixed/solve):','text','fixed'}, ...
                 {'Conversion X (if fixed):','numeric',0.5}, ...
                 {'Product species indices:','text','2'}, ...
                 {'Product yields:','text','1'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=u.basisSpecies;
                ctrls{4}.Value=u.conversionMode;
                ctrls{5}.Value=u.conversion;
                ctrls{6}.Value=num2str(u.productSpecies(:).');
                ctrls{7}.Value=num2str(u.productYields(:).');
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                pIdx = str2num(ctrls{6}.Value); %#ok
                pY = str2num(ctrls{7}.Value); %#ok
                if numel(pIdx) ~= numel(pY)
                    uialert(d,'Product indices and yields must have same length.','Error'); return;
                end
                def.type='YieldReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.basisSpecies=ctrls{3}.Value;
                def.conversionMode=strtrim(lower(ctrls{4}.Value)); def.conversion=ctrls{5}.Value;
                def.productSpecies=pIdx; def.productYields=pY;
                u=proc.units.YieldReactor(app.findStream(def.inlet), app.findStream(def.outlet), ...
                    def.basisSpecies, def.conversion, def.productSpecies, def.productYields, ...
                    'conversionMode', def.conversionMode);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogEquilibriumReactor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Configure EquilibriumReactor', 520, 230, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Nu vector:','text',num2str(zeros(1,ns))}, ...
                 {'Equilibrium K:','numeric',1}, ...
                 {'Reference species index:','numeric',1}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                ctrls{3}.Value=num2str(u.nu.');
                ctrls{4}.Value=u.Keq;
                ctrls{5}.Value=u.referenceSpecies;
            elseif numel(sNames)>=2
                ctrls{2}.Value=sNames{2};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                nu = str2num(ctrls{3}.Value); %#ok
                if numel(nu) ~= ns
                    uialert(d,sprintf('Nu vector must have %d entries.',ns),'Error'); return;
                end
                def.type='EquilibriumReactor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                def.nu=nu; def.Keq=ctrls{4}.Value; def.referenceSpecies=ctrls{5}.Value;
                u=proc.units.EquilibriumReactor(app.findStream(def.inlet), app.findStream(def.outlet), ...
                    def.nu, def.Keq, 'referenceSpecies', def.referenceSpecies);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogSeparator(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Configure Separator', 480, 200, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet A:','dropdown',sNames}, ...
                 {'Outlet B:','dropdown',sNames}, ...
                 {sprintf('phi -> A (%s):',strjoin(app.speciesNames,',')),'text',num2str(repmat(0.5,1,ns))}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outletA.name));
                ctrls{3}.Value=char(string(u.outletB.name));
                ctrls{4}.Value=num2str(u.phi);
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                phi=str2num(ctrls{4}.Value); %#ok
                if numel(phi)~=ns
                    uialert(d,sprintf('phi needs %d values.',ns),'Error'); return;
                end
                def.type='Separator'; def.inlet=ctrls{1}.Value;
                def.outletA=ctrls{2}.Value; def.outletB=ctrls{3}.Value; def.phi=phi;
                u=proc.units.Separator(app.findStream(def.inlet),...
                    app.findStream(def.outletA),app.findStream(def.outletB),phi);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogPurge(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Purge', 420, 200, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Recycle:','dropdown',sNames}, ...
                 {'Purge:','dropdown',sNames}, ...
                 {'Beta (recycle frac):','numeric',0.9}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.recycle.name));
                ctrls{3}.Value=char(string(u.purge.name));
                ctrls{4}.Value=u.beta;
            elseif numel(sNames)>=3
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Purge'; def.inlet=ctrls{1}.Value;
                def.recycle=ctrls{2}.Value; def.purge=ctrls{3}.Value;
                def.beta=ctrls{4}.Value;
                u=proc.units.Purge(app.findStream(def.inlet),...
                    app.findStream(def.recycle),app.findStream(def.purge),def.beta);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        % Generic dialog builder
        function [d, ctrls] = makeDialog(~, titleStr, w, h, fields)
            nf = numel(fields);
            totalH = max(h, 50 + nf*36);
            d = uifigure('Name',titleStr,'Position',[300 300 w totalH], ...
                'Resize','off','WindowStyle','modal');
            dg = uigridlayout(d, [nf+1, 2], 'ColumnWidth',{160,'1x'}, ...
                'RowHeight',[repmat({28},1,nf),{36}], 'Padding',[12 12 12 12]);
            ctrls = cell(1,nf);
            for i = 1:nf
                f = fields{i};
                uilabel(dg,'Text',f{1},'FontWeight','bold');
                switch f{2}
                    case 'dropdown'
                        ctrls{i} = uidropdown(dg,'Items',f{3},'Value',f{3}{1});
                    case 'text'
                        ctrls{i} = uieditfield(dg,'text','Value',f{3});
                    case 'numeric'
                        ctrls{i} = uieditfield(dg,'numeric','Value',f{3});
                end
            end
        end

        function addDialogButtons(~, d, okFcn)
            dg = d.Children(1);
            nRows = numel(dg.RowHeight);
            btnG = uigridlayout(dg,[1 2],'ColumnWidth',{'1x','1x'},'Padding',[0 0 0 0]);
            btnG.Layout.Row = nRows; btnG.Layout.Column = [1 2];
            uibutton(btnG,'push','Text','OK','FontWeight','bold', ...
                'BackgroundColor',[0.82 0.95 0.82],'ButtonPushedFcn',@(~,~)okFcn());
            uibutton(btnG,'push','Text','Cancel','ButtonPushedFcn',@(~,~)delete(d));
        end
    end

    % =====================================================================
    %  SOLVER (with real-time residual plot)
    % =====================================================================
    methods (Access = private)

        function runSolver(app)
            app.syncStreamsFromTable();

            if isempty(app.streams)
                uialert(app.Fig,'No streams.','Error'); return;
            end
            if isempty(app.units)
                uialert(app.Fig,'No units.','Error'); return;
            end

            fs = app.buildFlowsheet();
            app.lastFlowsheet = fs;
            app.updateDOF();

            maxIt = app.MaxIterField.Value;
            tol   = app.TolField.Value;

            % Prepare real-time plot
            cla(app.ResidualAxes);
            hLine = animatedline(app.ResidualAxes, 'Color',[0.15 0.5 0.75], ...
                'LineWidth',1.8, 'Marker','o', 'MarkerSize',3);
            yline(app.ResidualAxes, tol, '--r', 'Tolerance', 'LineWidth',1);
            xlabel(app.ResidualAxes,'Iteration');
            ylabel(app.ResidualAxes,'||r||');
            app.ResidualAxes.YScale = 'log';
            grid(app.ResidualAxes,'on');
            title(app.ResidualAxes,'Solving...');

            app.LogArea.Value = {'Solving...'};
            drawnow;

            % Callback for real-time updates
            function iterCb(iter, rNorm)
                addpoints(hLine, iter, rNorm);
                drawnow limitrate;
            end

            try
                solver = fs.solve('maxIter',maxIt,'tolAbs',tol, ...
                    'printToConsole',false,'iterCallback',@iterCb);
                app.lastSolver = solver;

                % Final plot cleanup
                title(app.ResidualAxes, ...
                    sprintf('Converged in %d iterations', numel(solver.residualHistory)-1));

                app.LogArea.Value = cellstr(solver.logLines);

                T = fs.streamTable();
                app.ResultsTable.Data = T;
                app.ResultsTable.ColumnName = T.Properties.VariableNames;

                app.refreshStreamTables();
                app.setStatus('Solve completed.');

            catch ME
                title(app.ResidualAxes, 'FAILED');
                logLines = [{'SOLVE FAILED:'; ME.message; ''}; ...
                    arrayfun(@(f) sprintf('  %s (line %d)',f.name,f.line), ME.stack,'Uni',false)];
                app.LogArea.Value = logLines;
                app.writeErrorLog('solve_error', logLines);
                app.setStatus('Solve failed — see log (saved to output/logs).');
            end
        end
    end

    % =====================================================================
    %  SAVE / LOAD CONFIG
    % =====================================================================
    methods (Access = private)


        function dialogSplitter(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Splitter', 520, 220, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlets (comma-sep):','text',strjoin(sNames(1:min(2,end)),', ')}, ...
                 {'Mode (fractions/flows):','text','fractions'}, ...
                 {'Values:','text','0.5 0.5'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                outN=cellfun(@(s)char(string(s.name)),u.outlets,'Uni',false);
                ctrls{2}.Value=strjoin(outN,', ');
                if ~isempty(u.splitFractions)
                    ctrls{3}.Value='fractions';
                    ctrls{4}.Value=num2str(u.splitFractions);
                else
                    ctrls{3}.Value='flows';
                    ctrls{4}.Value=num2str(u.specifiedOutletFlows);
                end
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                outNms=strtrim(strsplit(ctrls{2}.Value,','));
                outS={};
                for k=1:numel(outNms)
                    s=app.findStream(outNms{k});
                    if isempty(s), uialert(d,sprintf('"%s" not found.',outNms{k}),'Error'); return; end
                    outS{end+1}=s; %#ok
                end
                vals=str2num(ctrls{4}.Value); %#ok
                if numel(vals)~=numel(outS)
                    uialert(d,'Values length must match number of outlets.','Error'); return;
                end
                mode=lower(strtrim(ctrls{3}.Value));
                def.type='Splitter'; def.inlet=ctrls{1}.Value; def.outlets=outNms;
                if strcmp(mode,'fractions')
                    def.splitFractions=vals;
                    u=proc.units.Splitter(app.findStream(def.inlet),outS,'fractions',vals);
                else
                    def.specifiedOutletFlows=vals;
                    u=proc.units.Splitter(app.findStream(def.inlet),outS,'flows',vals);
                end
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogRecycle(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Recycle', 400, 140, ...
                {{'Source stream:','dropdown',sNames}, {'Tear stream:','dropdown',sNames}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.source.name));
                ctrls{2}.Value=char(string(u.tear.name));
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Recycle'; def.source=ctrls{1}.Value; def.tear=ctrls{2}.Value;
                u=proc.units.Recycle(app.findStream(def.source), app.findStream(def.tear));
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogBypass(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Bypass', 520, 260, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Process inlet stream:','dropdown',sNames}, ...
                 {'Bypass stream:','dropdown',sNames}, ...
                 {'Process return stream:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Bypass fraction (0..1):','numeric',0.2}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.processInlet.name));
                ctrls{3}.Value=char(string(u.bypassStream.name));
                ctrls{4}.Value=char(string(u.processReturn.name));
                ctrls{5}.Value=char(string(u.outlet.name));
                ctrls{6}.Value=u.bypassFraction;
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Bypass';
                def.inlet=ctrls{1}.Value; def.processInlet=ctrls{2}.Value;
                def.bypassStream=ctrls{3}.Value; def.processReturn=ctrls{4}.Value;
                def.outlet=ctrls{5}.Value; def.bypassFraction=ctrls{6}.Value;
                u=proc.units.Bypass(app.findStream(def.inlet), app.findStream(def.processInlet), ...
                    app.findStream(def.bypassStream), app.findStream(def.processReturn), ...
                    app.findStream(def.outlet), def.bypassFraction);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogManifold(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Manifold', 520, 220, ...
                {{'Inlets (comma-sep):','text',strjoin(sNames(1:min(2,end)),', ')}, ...
                 {'Outlets (comma-sep):','text',strjoin(sNames(1:min(2,end)),', ')}, ...
                 {'Route vector:','text','1 2'}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                inN=cellfun(@(s)char(string(s.name)),u.inlets,'Uni',false);
                outN=cellfun(@(s)char(string(s.name)),u.outlets,'Uni',false);
                ctrls{1}.Value=strjoin(inN,', ');
                ctrls{2}.Value=strjoin(outN,', ');
                ctrls{3}.Value=num2str(u.route);
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                inNms=strtrim(strsplit(ctrls{1}.Value,','));
                outNms=strtrim(strsplit(ctrls{2}.Value,','));
                route=str2num(ctrls{3}.Value); %#ok
                if numel(route)~=numel(outNms)
                    uialert(d,'Route length must equal number of outlets.','Error'); return;
                end
                inS={}; outS={};
                for k=1:numel(inNms)
                    s=app.findStream(inNms{k}); if isempty(s), uialert(d,sprintf('"%s" not found.',inNms{k}),'Error'); return; end
                    inS{end+1}=s; %#ok
                end
                for k=1:numel(outNms)
                    s=app.findStream(outNms{k}); if isempty(s), uialert(d,sprintf('"%s" not found.',outNms{k}),'Error'); return; end
                    outS{end+1}=s; %#ok
                end
                if any(route < 1) || any(route > numel(inS))
                    uialert(d,'Route indices must reference inlet list.','Error'); return;
                end
                def.type='Manifold'; def.inlets=inNms; def.outlets=outNms; def.route=route;
                u=proc.units.Manifold(inS,outS,route);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function saveConfigDialog(app)
            [file, path] = uiputfile('*.mat', 'Save Config', 'mathlab_config.mat');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            app.syncStreamsFromTable();
            app.saveConfig(filepath);
            app.setStatus(sprintf('Config saved to %s', filepath));
        end

        function saveConfigToOutput(app)
            app.syncStreamsFromTable();
            outDir = app.ensureOutputDir('saves');
            fname = app.autoFileName('config', 'mat');
            filepath = fullfile(outDir, fname);
            app.saveConfig(filepath);
            app.setStatus(sprintf('Config saved to %s', filepath));
        end

        function saveResultsToOutput(app)
            if isempty(app.lastSolver)
                uialert(app.Fig,'No solver results yet. Run the solver first.','No Results');
                return;
            end
            outDir = app.ensureOutputDir('results');
            fname = app.autoFileName('results', 'mat');
            filepath = fullfile(outDir, fname);
            solverData = app.lastSolver; %#ok
            if ~isempty(app.lastFlowsheet)
                streamTable = app.lastFlowsheet.streamTable(); %#ok
                save(filepath, 'solverData', 'streamTable');
            else
                save(filepath, 'solverData');
            end
            app.setStatus(sprintf('Results saved to %s', filepath));
        end

        function onProjectTitleChanged(app, src)
            app.projectTitle = strtrim(src.Value);
            if isempty(app.projectTitle)
                app.projectTitle = 'MathLab_Project';
                src.Value = app.projectTitle;
            end
        end

        function loadConfigDialog(app)
            [file, path] = uigetfile('*.mat', 'Load Config');
            if isequal(file, 0), return; end
            filepath = fullfile(path, file);
            app.loadConfig(filepath);
            app.setStatus(sprintf('Config loaded from %s', filepath));
        end

        function saveConfig(app, filepath)
            % Serialize entire flowsheet state to a .mat file
            cfg = struct();
            cfg.speciesNames = app.speciesNames;
            cfg.speciesMW    = app.speciesMW;

            % Serialize streams
            N = numel(app.streams);
            streamData = struct();
            for i = 1:N
                s = app.streams{i};
                sd.name  = char(string(s.name));
                sd.n_dot = s.n_dot;
                sd.T     = s.T;
                sd.P     = s.P;
                sd.y     = s.y;
                sd.known_n_dot = s.known.n_dot;
                sd.known_T     = s.known.T;
                sd.known_P     = s.known.P;
                sd.known_y     = s.known.y;
                streamData(i) = sd;
            end
            cfg.streams = streamData;

            % Serialize unit definitions (not the objects themselves)
            cfg.unitDefs = app.unitDefs;

            % Solver settings
            cfg.maxIter = app.MaxIterField.Value;
            cfg.tolAbs  = app.TolField.Value;

            % Project title
            cfg.projectTitle = app.projectTitle;

            save(filepath, '-struct', 'cfg');

            % Also generate a companion .m script
            mFile = strrep(filepath, '.mat', '_script.m');
            app.generateScript(mFile, cfg);
        end

        function loadConfig(app, filepath)
            cfg = load(filepath);

            % Restore species
            app.speciesNames = cfg.speciesNames;
            app.speciesMW    = cfg.speciesMW;
            app.refreshSpeciesTable();

            % Restore streams
            app.streams = {};
            for i = 1:numel(cfg.streams)
                sd = cfg.streams(i);
                s = proc.Stream(string(sd.name), app.speciesNames);
                s.n_dot = sd.n_dot;
                s.T     = sd.T;
                s.P     = sd.P;
                s.y     = sd.y;
                s.known.n_dot = sd.known_n_dot;
                s.known.T     = sd.known_T;
                s.known.P     = sd.known_P;
                s.known.y     = sd.known_y;
                app.streams{end+1} = s;
            end

            % Restore units from definitions
            app.units = {};
            app.unitDefs = {};
            if isfield(cfg, 'unitDefs') && ~isempty(cfg.unitDefs)
                for i = 1:numel(cfg.unitDefs)
                    def = cfg.unitDefs{i};
                    u = app.buildUnitFromDef(def);
                    if ~isempty(u)
                        app.units{end+1} = u;
                        app.unitDefs{end+1} = def;
                    end
                end
            end

            % Restore solver settings
            if isfield(cfg,'maxIter'), app.MaxIterField.Value = cfg.maxIter; end
            if isfield(cfg,'tolAbs'),  app.TolField.Value = cfg.tolAbs; end

            % Restore project title
            if isfield(cfg,'projectTitle')
                app.projectTitle = cfg.projectTitle;
                app.ProjectTitleField.Value = cfg.projectTitle;
            end

            app.refreshStreamTables();
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.updateSensDropdowns();

            % Auto-suggest next stream name
            if ~isempty(app.streams)
                lastName = char(string(app.streams{end}.name));
                tok = regexp(lastName,'^([A-Za-z_]*)(\d+)$','tokens');
                if ~isempty(tok)
                    app.StreamNameField.Value = sprintf('%s%d',tok{1}{1},str2double(tok{1}{2})+1);
                end
            end
        end

        function u = buildUnitFromDef(app, def)
            u = [];
            switch def.type
                case 'Link'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Link(sIn, sOut);
                    end
                case 'Mixer'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = app.findStream(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sOut)
                        u = proc.units.Mixer(inS, sOut);
                    end
                case 'Reactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.Reactor(sIn, sOut, def.reactions, def.conversion);
                    end
                case 'StoichiometricReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.StoichiometricReactor(sIn, sOut, def.nu, ...
                            'extent', def.extent, 'extentMode', def.extentMode, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'ConversionReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.ConversionReactor(sIn, sOut, def.nu, def.keySpecies, ...
                            def.conversion, 'conversionMode', def.conversionMode);
                    end
                case 'YieldReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.YieldReactor(sIn, sOut, def.basisSpecies, def.conversion, ...
                            def.productSpecies, def.productYields, 'conversionMode', def.conversionMode);
                    end
                case 'EquilibriumReactor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        u = proc.units.EquilibriumReactor(sIn, sOut, def.nu, def.Keq, ...
                            'referenceSpecies', def.referenceSpecies);
                    end
                case 'Separator'
                    sIn = app.findStream(def.inlet);
                    sA  = app.findStream(def.outletA);
                    sB  = app.findStream(def.outletB);
                    if ~isempty(sIn) && ~isempty(sA) && ~isempty(sB)
                        u = proc.units.Separator(sIn, sA, sB, def.phi);
                    end
                case 'Purge'
                    sIn  = app.findStream(def.inlet);
                    sRec = app.findStream(def.recycle);
                    sPur = app.findStream(def.purge);
                    if ~isempty(sIn) && ~isempty(sRec) && ~isempty(sPur)
                        u = proc.units.Purge(sIn, sRec, sPur, def.beta);
                    end
                case 'Splitter'
                    sIn = app.findStream(def.inlet);
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = app.findStream(def.outlets{k});
                        if isempty(s), return; end
                        outS{end+1} = s; %#ok
                    end
                    if ~isempty(sIn)
                        if isfield(def, 'splitFractions')
                            u = proc.units.Splitter(sIn, outS, 'fractions', def.splitFractions);
                        else
                            u = proc.units.Splitter(sIn, outS, 'flows', def.specifiedOutletFlows);
                        end
                    end
                case 'Recycle'
                    sSrc = app.findStream(def.source);
                    sTear = app.findStream(def.tear);
                    if ~isempty(sSrc) && ~isempty(sTear)
                        u = proc.units.Recycle(sSrc, sTear);
                    end
                case 'Bypass'
                    sIn = app.findStream(def.inlet);
                    sProcIn = app.findStream(def.processInlet);
                    sByp = app.findStream(def.bypassStream);
                    sRet = app.findStream(def.processReturn);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sProcIn) && ~isempty(sByp) && ~isempty(sRet) && ~isempty(sOut)
                        u = proc.units.Bypass(sIn, sProcIn, sByp, sRet, sOut, def.bypassFraction);
                    end
                case 'Manifold'
                    inS = {};
                    for k = 1:numel(def.inlets)
                        s = app.findStream(def.inlets{k});
                        if isempty(s), return; end
                        inS{end+1} = s; %#ok
                    end
                    outS = {};
                    for k = 1:numel(def.outlets)
                        s = app.findStream(def.outlets{k});
                        if isempty(s), return; end
                        outS{end+1} = s; %#ok
                    end
                    u = proc.units.Manifold(inS, outS, def.route);
            end
        end

        function generateScript(~, filepath, cfg)
            % Write a human-readable .m script that recreates the flowsheet
            fid = fopen(filepath, 'w');
            if fid < 0, return; end

            fprintf(fid, '%%%% MathLab Config Script (auto-generated)\n');
            fprintf(fid, '%% Run this to recreate the flowsheet and solve.\n');
            fprintf(fid, '%% You can also use: [T, solver] = runFromConfig(''%s'');\n\n', ...
                strrep(filepath,'_script.m','.mat'));
            fprintf(fid, 'clear; clc;\n\n');

            % Species
            fprintf(fid, 'species = {');
            for i = 1:numel(cfg.speciesNames)
                if i>1, fprintf(fid, ', '); end
                fprintf(fid, '''%s''', cfg.speciesNames{i});
            end
            fprintf(fid, '};\n');
            fprintf(fid, 'fs = proc.Flowsheet(species);\n\n');

            % Streams
            fprintf(fid, '%% --- Streams ---\n');
            for i = 1:numel(cfg.streams)
                sd = cfg.streams(i);
                fprintf(fid, '%s = proc.Stream("%s", species);\n', sd.name, sd.name);
                fprintf(fid, '%s.n_dot = %.6g; %s.T = %.6g; %s.P = %.6g;\n', ...
                    sd.name, sd.n_dot, sd.name, sd.T, sd.name, sd.P);
                fprintf(fid, '%s.y = %s;\n', sd.name, mat2str(sd.y, 8));
                if sd.known_n_dot, fprintf(fid, '%s.known.n_dot = true;\n', sd.name); end
                if sd.known_T,     fprintf(fid, '%s.known.T = true;\n', sd.name); end
                if sd.known_P,     fprintf(fid, '%s.known.P = true;\n', sd.name); end
                if all(sd.known_y), fprintf(fid, '%s.known.y(:) = true;\n', sd.name); end
                fprintf(fid, 'fs.addStream(%s);\n\n', sd.name);
            end

            % Units
            if isfield(cfg,'unitDefs') && ~isempty(cfg.unitDefs)
                fprintf(fid, '%% --- Units ---\n');
                for i = 1:numel(cfg.unitDefs)
                    def = cfg.unitDefs{i};
                    switch def.type
                        case 'Link'
                            fprintf(fid, 'fs.addUnit(proc.units.Link(%s, %s));\n', def.inlet, def.outlet);
                        case 'Mixer'
                            inStr = strjoin(cellfun(@(n) n, def.inlets, 'Uni',false), ', ');
                            fprintf(fid, 'fs.addUnit(proc.units.Mixer({%s}, %s));\n', inStr, def.outlet);
                        case 'Reactor'
                            fprintf(fid, 'rxn.reactants = %s;\n', mat2str(def.reactions.reactants));
                            fprintf(fid, 'rxn.products = %s;\n', mat2str(def.reactions.products));
                            fprintf(fid, 'rxn.stoich = %s;\n', mat2str(def.reactions.stoich));
                            fprintf(fid, 'rxn.name = "%s";\n', def.reactions.name);
                            fprintf(fid, 'fs.addUnit(proc.units.Reactor(%s, %s, rxn, %.4g));\n', ...
                                def.inlet, def.outlet, def.conversion);
                        case 'StoichiometricReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.StoichiometricReactor(%s, %s, %s, ''extent'', %.6g, ''extentMode'', ''%s'', ''referenceSpecies'', %d));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.extent, def.extentMode, def.referenceSpecies);
                        case 'ConversionReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.ConversionReactor(%s, %s, %s, %d, %.6g, ''conversionMode'', ''%s''));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.keySpecies, def.conversion, def.conversionMode);
                        case 'YieldReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.YieldReactor(%s, %s, %d, %.6g, %s, %s, ''conversionMode'', ''%s''));\n', ...
                                def.inlet, def.outlet, def.basisSpecies, def.conversion, mat2str(def.productSpecies), mat2str(def.productYields), def.conversionMode);
                        case 'EquilibriumReactor'
                            fprintf(fid, 'fs.addUnit(proc.units.EquilibriumReactor(%s, %s, %s, %.6g, ''referenceSpecies'', %d));\n', ...
                                def.inlet, def.outlet, mat2str(def.nu), def.Keq, def.referenceSpecies);
                        case 'Separator'
                            fprintf(fid, 'fs.addUnit(proc.units.Separator(%s, %s, %s, %s));\n', ...
                                def.inlet, def.outletA, def.outletB, mat2str(def.phi,6));
                        case 'Purge'
                            fprintf(fid, 'fs.addUnit(proc.units.Purge(%s, %s, %s, %.4g));\n', ...
                                def.inlet, def.recycle, def.purge, def.beta);
                        case 'Splitter'
                            outStr = strjoin(cellfun(@(n) n, def.outlets, 'Uni',false), ', ');
                            if isfield(def, 'splitFractions')
                                fprintf(fid, 'fs.addUnit(proc.units.Splitter(%s, {%s}, ''fractions'', %s));\n', ...
                                    def.inlet, outStr, mat2str(def.splitFractions,6));
                            else
                                fprintf(fid, 'fs.addUnit(proc.units.Splitter(%s, {%s}, ''flows'', %s));\n', ...
                                    def.inlet, outStr, mat2str(def.specifiedOutletFlows,6));
                            end
                        case 'Recycle'
                            fprintf(fid, 'fs.addUnit(proc.units.Recycle(%s, %s));\n', def.source, def.tear);
                        case 'Bypass'
                            fprintf(fid, 'fs.addUnit(proc.units.Bypass(%s, %s, %s, %s, %s, %.4g));\n', ...
                                def.inlet, def.processInlet, def.bypassStream, def.processReturn, def.outlet, def.bypassFraction);
                        case 'Manifold'
                            inStr = strjoin(cellfun(@(n) n, def.inlets, 'Uni',false), ', ');
                            outStr = strjoin(cellfun(@(n) n, def.outlets, 'Uni',false), ', ');
                            fprintf(fid, 'fs.addUnit(proc.units.Manifold({%s}, {%s}, %s));\n', ...
                                inStr, outStr, mat2str(def.route));
                    end
                end
            end

            fprintf(fid, '\n%% --- Solve ---\n');
            fprintf(fid, 'solver = fs.solve(''maxIter'', %d, ''tolAbs'', %.2e, ''verbose'', true);\n', ...
                cfg.maxIter, cfg.tolAbs);
            fprintf(fid, 'T = fs.streamTable();\n');
            fprintf(fid, 'disp(T);\n');

            fclose(fid);
        end
    end

    % =====================================================================
    %  SENSITIVITY
    % =====================================================================
    methods (Access = private)

        function updateSensDropdowns(app)
            sNames = app.getStreamNames();
            if isempty(sNames), sNames = {'(none)'}; end
            app.SensOutputStreamDD.Items = sNames;

            uNames = {};
            for i = 1:numel(app.units)
                uNames{end+1} = sprintf('[%d] %s', i, app.shortTypeName(app.units{i})); %#ok
            end
            if isempty(uNames), uNames = {'(none)'}; end
            app.SensUnitDropDown.Items = [uNames, sNames];

            flds = {'n_dot','T','P'};
            for j = 1:numel(app.speciesNames)
                flds{end+1} = sprintf('y(%d) [%s]', j, app.speciesNames{j}); %#ok
            end
            app.SensOutputFieldDD.Items = flds;
        end

        function onSensParamChanged(app)
            choice = app.SensParamDropDown.Value;
            if startsWith(choice, 'Stream')
                app.SensUnitDropDown.Items = app.getStreamNames();
            else
                uNames = {};
                for i = 1:numel(app.units)
                    uNames{end+1} = sprintf('[%d] %s', i, app.shortTypeName(app.units{i})); %#ok
                end
                if isempty(uNames), uNames = {'(none)'}; end
                app.SensUnitDropDown.Items = uNames;
            end
            app.validateSensSelection();
        end

        function validateSensSelection(app)
            % Grey out run button if sweep param is impossible for selected target
            paramChoice = app.SensParamDropDown.Value;
            unitSel = app.SensUnitDropDown.Value;

            if strcmp(unitSel, '(none)')
                app.SensRunBtn.Enable = 'off';
                app.SensStatusLabel.Text = 'Select a valid target unit/stream.';
                return;
            end

            % Check if param matches unit type
            tok = regexp(unitSel,'^\[(\d+)\]','tokens');
            if ~isempty(tok)
                idx = str2double(tok{1}{1});
                if idx >= 1 && idx <= numel(app.units)
                    uType = app.shortTypeName(app.units{idx});
                    impossible = false;
                    if contains(paramChoice, 'conversion') && ~strcmp(uType, 'Reactor')
                        impossible = true;
                    elseif contains(paramChoice, 'beta') && ~strcmp(uType, 'Purge')
                        impossible = true;
                    elseif contains(paramChoice, 'phi') && ~strcmp(uType, 'Separator')
                        impossible = true;
                    end
                    if impossible
                        app.SensRunBtn.Enable = 'off';
                        app.SensStatusLabel.Text = sprintf('"%s" not applicable to %s.', ...
                            paramChoice, uType);
                        return;
                    end
                end
            end

            app.SensRunBtn.Enable = 'on';
            app.SensStatusLabel.Text = '';
        end

        function runSensitivity(app)
            app.syncStreamsFromTable();
            if isempty(app.streams) || isempty(app.units)
                uialert(app.Fig,'Build flowsheet first.','Error'); return;
            end

            paramChoice = app.SensParamDropDown.Value;
            vMin = app.SensMinField.Value;
            vMax = app.SensMaxField.Value;
            nPts = round(app.SensNptsField.Value);
            outStreamName = app.SensOutputStreamDD.Value;
            outFieldStr   = app.SensOutputFieldDD.Value;
            sensMaxIt = app.SensMaxIterField.Value;
            sensTol   = app.SensTolField.Value;

            vals = linspace(vMin, vMax, nPts);
            results = nan(1, nPts);

            unitSel = app.SensUnitDropDown.Value;
            tok = regexp(unitSel,'^\[(\d+)\]','tokens');
            unitIdx = [];
            if ~isempty(tok), unitIdx = str2double(tok{1}{1}); end

            origVal = app.getSensParamValue(paramChoice, unitIdx, unitSel);

            cla(app.SensAxes);
            app.setStatus('Running sensitivity...');
            app.SensStatusLabel.Text = sprintf('Running 0/%d ...', nPts);
            app.SensRunBtn.Enable = 'off';
            drawnow;

            for p = 1:nPts
                try
                    app.applySensParam(paramChoice, unitIdx, vals(p), unitSel);
                    fs = app.buildFlowsheet();
                    fs.solve('maxIter',sensMaxIt,'tolAbs',sensTol,'printToConsole',false);
                    results(p) = app.extractOutput(outStreamName, outFieldStr);
                catch
                    results(p) = NaN;
                end
                app.SensStatusLabel.Text = sprintf('Running %d/%d ...', p, nPts);
                drawnow limitrate;
            end

            if ~isnan(origVal)
                app.applySensParam(paramChoice, unitIdx, origVal, unitSel);
            end

            app.SensRunBtn.Enable = 'on';

            plot(app.SensAxes, vals, results, '-o', 'LineWidth',1.5, ...
                'MarkerSize',5, 'Color',[0.2 0.5 0.8]);
            xlabel(app.SensAxes, strrep(paramChoice,'_','\_'));
            ylabel(app.SensAxes, sprintf('%s . %s', outStreamName, strrep(outFieldStr,'_','\_')));
            title(app.SensAxes, 'Sensitivity Analysis');
            grid(app.SensAxes, 'on');
            nConv = sum(~isnan(results));
            statusMsg = sprintf('Sensitivity: %d/%d converged (maxIter=%d, tol=%.1e).', ...
                nConv, nPts, sensMaxIt, sensTol);
            app.SensStatusLabel.Text = statusMsg;
            app.setStatus(statusMsg);
        end

        function applySensParam(app, paramChoice, unitIdx, val, unitSel)
            if contains(paramChoice, 'conversion')
                if ~isempty(unitIdx) && unitIdx <= numel(app.units)
                    app.units{unitIdx}.conversion = val;
                end
            elseif contains(paramChoice, 'beta')
                if ~isempty(unitIdx) && unitIdx <= numel(app.units)
                    app.units{unitIdx}.beta = val;
                end
            elseif contains(paramChoice, 'phi')
                if ~isempty(unitIdx) && unitIdx <= numel(app.units)
                    app.units{unitIdx}.phi(1) = val;
                end
            elseif contains(paramChoice, 'n_dot')
                s = app.findStream(unitSel);
                if ~isempty(s), s.n_dot = val; end
            elseif contains(paramChoice, ' T')
                s = app.findStream(unitSel);
                if ~isempty(s), s.T = val; end
            elseif contains(paramChoice, ' P')
                s = app.findStream(unitSel);
                if ~isempty(s), s.P = val; end
            end
        end

        function val = getSensParamValue(app, paramChoice, unitIdx, unitSel)
            val = NaN;
            if contains(paramChoice,'conversion')
                if ~isempty(unitIdx)&&unitIdx<=numel(app.units), val=app.units{unitIdx}.conversion; end
            elseif contains(paramChoice,'beta')
                if ~isempty(unitIdx)&&unitIdx<=numel(app.units), val=app.units{unitIdx}.beta; end
            elseif contains(paramChoice,'phi')
                if ~isempty(unitIdx)&&unitIdx<=numel(app.units), val=app.units{unitIdx}.phi(1); end
            elseif contains(paramChoice,'n_dot')
                s=app.findStream(unitSel); if ~isempty(s), val=s.n_dot; end
            elseif contains(paramChoice,' T')
                s=app.findStream(unitSel); if ~isempty(s), val=s.T; end
            elseif contains(paramChoice,' P')
                s=app.findStream(unitSel); if ~isempty(s), val=s.P; end
            end
        end

        function val = extractOutput(app, streamName, fieldStr)
            s = app.findStream(streamName);
            if isempty(s), val=NaN; return; end
            if strcmp(fieldStr,'n_dot'), val=s.n_dot;
            elseif strcmp(fieldStr,'T'), val=s.T;
            elseif strcmp(fieldStr,'P'), val=s.P;
            else
                tok = regexp(fieldStr,'y\((\d+)\)','tokens');
                if ~isempty(tok), val=s.y(str2double(tok{1}{1}));
                else, val=NaN; end
            end
        end
    end

    % =====================================================================
    %  HELPERS
    % =====================================================================
    methods (Access = private)
        function names = getStreamNames(app)
            names = cellfun(@(s) char(string(s.name)), app.streams, 'Uni', false);
        end

        function s = findStream(app, name)
            s = [];
            for i = 1:numel(app.streams)
                if strcmp(char(string(app.streams{i}.name)), char(name))
                    s = app.streams{i}; return;
                end
            end
        end

        function nm = shortTypeName(~, u)
            cn = class(u); parts = strsplit(cn,'.'); nm = parts{end};
        end

        function setStatus(app, msg)
            app.StatusBar.Text = ['  ' msg];
        end
    end

    % =====================================================================
    %  OUTPUT FOLDER MANAGEMENT
    % =====================================================================
    methods (Access = private)
        function dirPath = ensureOutputDir(~, subfolder)
            % Ensure output/<subfolder> exists and return the path
            baseDir = fullfile(pwd, 'output');
            dirPath = fullfile(baseDir, subfolder);
            if ~exist(dirPath, 'dir')
                mkdir(dirPath);
            end
        end

        function fname = autoFileName(app, prefix, ext)
            % Generate filename: <ProjectTitle>_<prefix>_YYYYMMDD_HHMMSS.<ext>
            safeTitle = regexprep(app.projectTitle, '[^A-Za-z0-9_-]', '_');
            stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok
            fname = sprintf('%s_%s_%s.%s', safeTitle, prefix, stamp, ext);
        end

        function writeErrorLog(app, prefix, logLines)
            % Write error log to output/logs
            try
                logDir = app.ensureOutputDir('logs');
                fname = app.autoFileName(prefix, 'txt');
                fpath = fullfile(logDir, fname);
                fid = fopen(fpath, 'w');
                if fid >= 0
                    for k = 1:numel(logLines)
                        fprintf(fid, '%s\n', logLines{k});
                    end
                    fclose(fid);
                end
            catch
                % Silently ignore logging failures
            end
        end
    end
end

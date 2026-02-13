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

        % -- Tab 0: Setup & Config --
        SetupTab
        SaveConfigBtn
        LoadConfigBtn
        InstructionsArea

        % -- Tab 1: Species & Properties --
        SpeciesTab
        SpeciesTable
        AddSpeciesBtn
        RemoveSpeciesBtn
        NewSpeciesName
        NewSpeciesMW
        ApplySpeciesBtn
        SpeciesPropsTable

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
        ResultsShowAliasesCheck
        ResultsShowAliasColumnCheck
        ResultsNameModeLabel

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
        FlowUnitDropDown
        TempUnitDropDown
        PressureUnitDropDown
        DutyUnitDropDown
        PowerUnitDropDown
        SaveResultsBtn
        OpenUnitTableBtn

        % -- Unit Table popup --
        UnitTableFig
        UnitTable
        UnitTableStatusLabel
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
        unitPrefs struct = struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW')
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

            app.buildSetupTab();
            app.buildSpeciesTab();
            app.buildStreamsTab();
            app.buildUnitsTab();
            app.buildSolveTab();
            app.buildResultsTab();
            app.buildSensitivityTab();
        end

        % ================================================================
        %  TAB 0: SETUP & CONFIG
        % ================================================================
        function buildSetupTab(app)
            t = uitab(app.Tabs, 'Title', ' Setup ');
            app.SetupTab = t;

            gl = uigridlayout(t, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',12);

            % --- Left: project config + save/load ---
            leftP = uipanel(gl, 'Title','Project & Config', 'FontWeight','bold');
            leftG = uigridlayout(leftP, [5 1], ...
                'RowHeight',{30, 72, 36, 36, 24}, 'Padding',[8 8 8 8], 'RowSpacing',4);

            % Project title row
            titleRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{110,'1x'}, ...
                'Padding',[0 0 0 0]);
            uilabel(titleRow,'Text','Project title:','FontWeight','bold');
            app.ProjectTitleField = uieditfield(titleRow,'text', ...
                'Value',app.projectTitle, ...
                'ValueChangedFcn',@(src,~) app.onProjectTitleChanged(src));

            % Display units row
            unitRow = uigridlayout(leftG, [2 5], 'ColumnWidth', {'fit','1x','1x','1x','1x'}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6, 'RowSpacing',3);
            uilabel(unitRow,'Text','Display units:','FontWeight','bold');
            app.FlowUnitDropDown = uidropdown(unitRow, 'Items', {'mol/s','kmol/s'}, ...
                'Value', app.unitPrefs.flow, 'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('flow', src.Value));
            app.TempUnitDropDown = uidropdown(unitRow, 'Items', {'K','C'}, ...
                'Value', app.unitPrefs.temperature, 'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('temperature', src.Value));
            app.PressureUnitDropDown = uidropdown(unitRow, 'Items', {'Pa','kPa','bar'}, ...
                'Value', app.unitPrefs.pressure, 'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('pressure', src.Value));
            app.DutyUnitDropDown = uidropdown(unitRow, 'Items', {'W','kW','MW'}, ...
                'Value', app.unitPrefs.duty, 'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('duty', src.Value));

            uilabel(unitRow,'Text','');
            app.PowerUnitDropDown = uidropdown(unitRow, 'Items', {'W','kW','MW'}, ...
                'Value', app.unitPrefs.power, 'ValueChangedFcn', @(src,~) app.onUnitPrefsChanged('power', src.Value));
            uilabel(unitRow,'Text','');
            uilabel(unitRow,'Text','');
            uilabel(unitRow,'Text','');

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

            % Save results + unit table row
            resRow = uigridlayout(leftG, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[0 0 0 0]);
            app.SaveResultsBtn = uibutton(resRow,'push','Text','Save Results', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.85 0.92 0.95], ...
                'ButtonPushedFcn',@(~,~) app.saveResultsToOutput());
            app.OpenUnitTableBtn = uibutton(resRow,'push','Text','Open Unit Table', ...
                'FontWeight','bold', ...
                'BackgroundColor',[0.90 0.88 0.98], ...
                'ButtonPushedFcn',@(~,~) app.openUnitTablePopup());

            % Placeholder for spacing
            uilabel(leftG, 'Text', '');

            % --- Right: instructions ---
            rightP = uipanel(gl, 'Title','How to Use MathLab', 'FontWeight','bold');
            rightG = uigridlayout(rightP, [1 1], 'Padding',[8 8 8 8]);
            app.InstructionsArea = uitextarea(rightG, 'Editable','off', ...
                'FontName','Consolas', 'FontSize',12, 'Value', { ...
                'WORKFLOW'; ...
                '========'; ...
                ''; ...
                '1. SETUP    — set project title, save/load config.'; ...
                '2. SPECIES  — define names, MW, thermo props. Apply.'; ...
                '3. STREAMS  — add streams, set values & known flags.'; ...
                '4. UNITS    — add unit ops, pick stream connections.'; ...
                '5. SOLVE    — check DOF, click Solve, see residuals.'; ...
                '6. RESULTS  — full solved stream table.'; ...
                '7. SENSITIVITY — sweep a parameter.'; ...
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
                '- Feed streams: all values Known'; ...
                '- Species with Shomate data enable thermo units'});
        end

        % ================================================================
        %  TAB 1: SPECIES & PROPERTIES
        % ================================================================
        function buildSpeciesTab(app)
            t = uitab(app.Tabs, 'Title', ' Species ');
            app.SpeciesTab = t;

            gl = uigridlayout(t, [1 2], 'ColumnWidth',{'1x','1x'}, ...
                'Padding',[12 12 12 12], 'ColumnSpacing',12);

            % --- Left: species editor ---
            leftP = uipanel(gl, 'Title','Species List', 'FontWeight','bold');
            leftG = uigridlayout(leftP, [4 1], ...
                'RowHeight',{'1x', 30, 30, 36}, 'Padding',[8 8 8 8], 'RowSpacing',4);

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

            % --- Right: thermodynamic properties (read-only from library) ---
            rightP = uipanel(gl, 'Title','Thermodynamic Properties (from library)', 'FontWeight','bold');
            rightG = uigridlayout(rightP, [1 1], 'Padding',[8 8 8 8]);
            app.SpeciesPropsTable = uitable(rightG, 'ColumnEditable',false, ...
                'ColumnName', {'Name','MW','Cp@298 (kJ/kmol/K)','Hf298 (kJ/kmol)','S298 (kJ/kmol/K)','T range (K)'});
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
                'Items', { ...
                    'Mixer', ...
                    'Link', ...
                    'Reactor', ...
                    'StoichiometricReactor', ...
                    'ConversionReactor', ...
                    'YieldReactor', ...
                    'EquilibriumReactor', ...
                    'Heater', ...
                    'Cooler', ...
                    'HeatExchanger', ...
                    'Compressor', ...
                    'Turbine', ...
                    'Separator', ...
                    'Purge', ...
                    'Splitter', ...
                    'Recycle', ...
                    'Bypass', ...
                    'Manifold', ...
                    'Source', ...
                    'Sink', ...
                    'DesignSpec', ...
                    'Adjust', ...
                    'Calculator', ...
                    'Constraint' ...
                }, ...
                'Value', 'Mixer');
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
            gl = uigridlayout(t, [2 1], 'RowHeight',{34,'1x'}, ...
                'Padding',[12 12 12 12], 'RowSpacing',8);

            topG = uigridlayout(gl, [1 3], 'ColumnWidth',{'fit',120,'1x'}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',8);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Simulation Results', 'FontWeight','bold');
            app.OpenUnitTableBtn = uibutton(topG,'push','Text','Open Unit Table', ...
                'FontWeight','bold', 'BackgroundColor',[0.90 0.88 0.98], ...
                'ButtonPushedFcn',@(~,~) app.openUnitTablePopup());
            uilabel(topG, 'Text','Inspect solved unit metrics (duty/power/conversion/etc.) in the unit table popup.', ...
                'FontColor',[0.35 0.35 0.35]);

            app.ResultsTable = uitable(gl);
            app.ResultsTable.Layout.Row = 2;
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
            uilabel(topG,'Text','Output stream (canonical):','FontWeight','bold');
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
            app.refreshUnitTablePopup();
            app.updateSensDropdowns();
            app.refreshSpeciesPropsTable();
            app.StreamNameField.Value = 'S2';
            app.setStatus(sprintf('Species set: {%s}. Feed created.', ...
                strjoin(app.speciesNames,', ')));
        end

        function refreshSpeciesPropsTable(app)
            % Populate the thermodynamic properties table from the library
            N = numel(app.speciesNames);
            data = cell(N, 6);
            try
                lib = thermo.ThermoLibrary();
            catch
                lib = [];
            end
            for i = 1:N
                data{i,1} = app.speciesNames{i};
                data{i,2} = app.speciesMW(i);
                if ~isempty(lib) && lib.hasSpecies(app.speciesNames{i})
                    sp = lib.get(app.speciesNames{i});
                    try
                        data{i,3} = sp.cp_molar(298.15);
                    catch
                        data{i,3} = NaN;
                    end
                    data{i,4} = sp.Hf298_kJkmol;
                    data{i,5} = sp.S298_kJkmolK;
                    if ~isempty(sp.ranges)
                        Tlo = sp.ranges(1).Tmin;
                        Thi = sp.ranges(end).Tmax;
                        data{i,6} = sprintf('%.0f - %.0f', Tlo, Thi);
                    else
                        data{i,6} = 'N/A';
                    end
                else
                    data{i,3} = NaN; data{i,4} = NaN; data{i,5} = NaN;
                    data{i,6} = 'Not in library';
                end
            end
            app.SpeciesPropsTable.Data = data;
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
            yTol = app.getYSumTolerance();

            colNames = [{'Name', app.unitLabel('flow','n_dot'), app.unitLabel('temperature','T'), app.unitLabel('pressure','P')}, ...
                cellfun(@(sp) ['y_' sp], app.speciesNames, 'Uni',false), ...
                {'sum_y','y_ok'}];
            data = cell(N, 6+ns);
            for i = 1:N
                s = app.streams{i};
                data{i,1} = char(string(s.name));
                data{i,2} = app.fromSI(s.n_dot,'flow');
                data{i,3} = app.fromSI(s.T,'temperature');
                data{i,4} = app.fromSI(s.P,'pressure');
                for j = 1:ns
                    if j <= numel(s.y), data{i,4+j} = s.y(j);
                    else,               data{i,4+j} = 0;
                    end
                end
                [sumY, yStatus] = app.evaluateYSumStatus(s, yTol);
                data{i,5+ns} = sumY;
                data{i,6+ns} = yStatus;
            end
            app.StreamValTable.Data = data;
            app.StreamValTable.ColumnName = colNames;
            app.StreamValTable.ColumnEditable = [false, true(1, 3+ns), false, false];
            app.applyStreamYStyles();

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
            app.StreamKnownTable.ColumnName = {'Name',app.unitLabel('flow','n_dot'),app.unitLabel('temperature','T'),app.unitLabel('pressure','P'),'y (all)'};
            app.StreamKnownTable.ColumnEditable = [false, true, true, true, true];
        end

        function onStreamValEdit(app, ~, evt)
            row = evt.Indices(1); col = evt.Indices(2);
            if row < 1 || row > numel(app.streams), return; end
            s = app.streams{row};
            ns = numel(app.speciesNames);
            switch col
                case 2, s.n_dot = app.toSI(evt.NewData,'flow');
                case 3, s.T = app.toSI(evt.NewData,'temperature');
                case 4, s.P = app.toSI(evt.NewData,'pressure');
                otherwise
                    j = col - 4;
                    if j >= 1 && j <= ns, s.y(j) = evt.NewData; end
            end
            app.refreshStreamTables();
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
                s.n_dot = app.toSI(D{i,2},'flow');
                s.T = app.toSI(D{i,3},'temperature');
                s.P = app.toSI(D{i,4},'pressure');
                for j = 1:ns, s.y(j) = D{i,4+j}; end
            end
        end

        function tol = getYSumTolerance(app)
            tol = 1e-9;
            if ~isempty(app.TolField) && isnumeric(app.TolField.Value) && isfinite(app.TolField.Value)
                tol = app.TolField.Value;
            end
            tol = max(tol, eps);
        end

        function [sumY, yStatus] = evaluateYSumStatus(~, s, tol)
            yVals = double(s.y(:));
            yVals = yVals(isfinite(yVals));
            sumY = sum(yVals);
            err = abs(sumY - 1.0);
            if err <= tol
                yStatus = 'OK';
            elseif err <= 10*tol
                yStatus = 'WARN';
            else
                yStatus = 'ERROR';
            end
        end

        function applyStreamYStyles(app)
            if isempty(app.StreamValTable) || isempty(app.StreamValTable.Data)
                return;
            end

            removeStyle(app.StreamValTable);

            ns = numel(app.speciesNames);
            sumCol = 5 + ns;
            statusCol = 6 + ns;
            yTol = app.getYSumTolerance();

            goodStyle = uistyle('BackgroundColor',[0.86 0.96 0.86], 'FontColor',[0.00 0.40 0.00]);
            warnStyle = uistyle('BackgroundColor',[1.00 0.95 0.80], 'FontColor',[0.55 0.35 0.00]);
            badStyle  = uistyle('BackgroundColor',[1.00 0.85 0.85], 'FontColor',[0.60 0.00 0.00]);

            for i = 1:numel(app.streams)
                [~, yStatus] = app.evaluateYSumStatus(app.streams{i}, yTol);
                switch yStatus
                    case 'OK'
                        sty = goodStyle;
                    case 'WARN'
                        sty = warnStyle;
                    otherwise
                        sty = badStyle;
                end
                addStyle(app.StreamValTable, sty, 'cell', [i, sumCol]);
                addStyle(app.StreamValTable, sty, 'cell', [i, statusCol]);
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
            [resolvedDefs, aliasByOutlet] = app.resolveIdentityLinks(app.unitDefs);
            fs = proc.Flowsheet(app.speciesNames);
            for i = 1:numel(app.streams)
                fs.addStream(app.streams{i});
            end
            app.addStreamAliasesToFlowsheet(fs, aliasByOutlet);
            for i = 1:numel(resolvedDefs)
                u = app.buildUnitFromDef(resolvedDefs{i}, 'includeIdentityLink', false);
                if ~isempty(u)
                    fs.addUnit(u);
                end
            end
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
            needsOne = ismember(typ, {'Source','Sink','DesignSpec','Constraint'});
            if needsOne
                if numel(sNames) < 1
                    uialert(app.Fig,'Need at least 1 stream.','Error'); return;
                end
            else
                if numel(sNames) < 2
                    uialert(app.Fig,'Need at least 2 streams.','Error'); return;
                end
            end
            switch typ
                case 'Link',      app.dialogLink(sNames);
                case 'Mixer',     app.dialogMixer(sNames);
                case 'Reactor',   app.dialogReactor(sNames);
                case 'StoichiometricReactor', app.dialogStoichiometricReactor(sNames);
                case 'ConversionReactor', app.dialogConversionReactor(sNames);
                case 'YieldReactor', app.dialogYieldReactor(sNames);
                case 'EquilibriumReactor', app.dialogEquilibriumReactor(sNames);
                case 'Heater',    app.dialogHeater(sNames);
                case 'Cooler',    app.dialogCooler(sNames);
                case 'HeatExchanger', app.dialogHeatExchanger(sNames);
                case 'Compressor', app.dialogCompressor(sNames);
                case 'Turbine',   app.dialogTurbine(sNames);
                case 'Separator', app.dialogSeparator(sNames);
                case 'Purge',     app.dialogPurge(sNames);
                case 'Splitter',  app.dialogSplitter(sNames);
                case 'Recycle',   app.dialogRecycle(sNames);
                case 'Bypass',    app.dialogBypass(sNames);
                case 'Manifold',  app.dialogManifold(sNames);
                case 'Source',    app.dialogSource(sNames);
                case 'Sink',      app.dialogSink(sNames);
                case 'DesignSpec', app.dialogDesignSpec(sNames);
                case 'Adjust',    app.dialogAdjust(sNames);
                case 'Calculator', app.dialogCalculator(sNames);
                case 'Constraint', app.dialogConstraint(sNames);
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
            elseif contains(cn,'Heater'), app.dialogHeater(sNames,idx);
            elseif contains(cn,'Cooler'), app.dialogCooler(sNames,idx);
            elseif contains(cn,'HeatExchanger'), app.dialogHeatExchanger(sNames,idx);
            elseif contains(cn,'Compressor'), app.dialogCompressor(sNames,idx);
            elseif contains(cn,'Turbine'), app.dialogTurbine(sNames,idx);
            elseif contains(cn,'Separator'), app.dialogSeparator(sNames,idx);
            elseif contains(cn,'Purge'), app.dialogPurge(sNames,idx);
            elseif contains(cn,'Splitter'), app.dialogSplitter(sNames,idx);
            elseif contains(cn,'Recycle'), app.dialogRecycle(sNames,idx);
            elseif contains(cn,'Bypass'), app.dialogBypass(sNames,idx);
            elseif contains(cn,'Manifold'), app.dialogManifold(sNames,idx);
            elseif contains(cn,'Source'), app.dialogSource(sNames,idx);
            elseif contains(cn,'Sink'), app.dialogSink(sNames,idx);
            elseif contains(cn,'DesignSpec'), app.dialogDesignSpec(sNames,idx);
            elseif contains(cn,'Adjust'), app.dialogAdjust(sNames,idx);
            elseif contains(cn,'Calculator'), app.dialogCalculator(sNames,idx);
            elseif contains(cn,'Constraint'), app.dialogConstraint(sNames,idx);
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
            app.refreshUnitTablePopup();
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
            app.refreshUnitTablePopup();
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
                elseif contains(cn,'Heater') || contains(cn,'Cooler') || contains(cn,'Compressor') || contains(cn,'Turbine')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='';
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='';
                elseif contains(cn,'HeatExchanger')
                    src{end+1}=char(string(u.hotInlet.name)); tgt{end+1}=uName; elbl{end+1}='hot in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.hotOutlet.name)); elbl{end+1}='hot out';
                    src{end+1}=char(string(u.coldInlet.name)); tgt{end+1}=uName; elbl{end+1}='cold in';
                    src{end+1}=uName; tgt{end+1}=char(string(u.coldOutlet.name)); elbl{end+1}='cold out';
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
                elseif contains(cn,'Source')
                    src{end+1}=uName; tgt{end+1}=char(string(u.outlet.name)); elbl{end+1}='out';
                elseif contains(cn,'Sink')
                    src{end+1}=char(string(u.inlet.name)); tgt{end+1}=uName; elbl{end+1}='in';
                elseif contains(cn,'DesignSpec')
                    src{end+1}=char(string(u.stream.name)); tgt{end+1}=uName; elbl{end+1}=char(string(u.metric));
                elseif contains(cn,'Adjust')
                    src{end+1}=char(string(u.targetSpec.stream.name)); tgt{end+1}=uName; elbl{end+1}='spec';
                elseif contains(cn,'Calculator')
                    src{end+1}=uName; tgt{end+1}=uName; elbl{end+1}='calc';
                elseif contains(cn,'Constraint')
                    src{end+1}=uName; tgt{end+1}=uName; elbl{end+1}='=';
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
                'Heater',   [0.85 0.45 0.10], ...
                'Cooler',   [0.10 0.55 0.85], ...
                'HeatExchanger', [0.65 0.35 0.65], ...
                'Compressor',[0.40 0.70 0.30], ...
                'Turbine',  [0.30 0.50 0.70], ...
                'Separator',[0.10 0.40 0.80], ...
                'Purge',    [0.70 0.40 0.80], ...
                'Splitter', [0.90 0.55 0.10], ...
                'Recycle',  [0.50 0.50 0.10], ...
                'Bypass',   [0.10 0.65 0.65], ...
                'Manifold', [0.35 0.25 0.70], ...
                'Source',   [0.15 0.55 0.20], ...
                'Sink',     [0.55 0.15 0.20], ...
                'DesignSpec',[0.25 0.25 0.85], ...
                'Adjust',   [0.55 0.20 0.65], ...
                'Calculator',[0.20 0.55 0.55], ...
                'Constraint',[0.55 0.55 0.20]);
            unitMarkers = struct( ...
                'Mixer',    'h', ...  % hexagon
                'Link',     's', ...  % square
                'Reactor',  'd', ...  % diamond
                'StoichiometricReactor', 'd', ...
                'ConversionReactor', 'd', ...
                'YieldReactor', 'd', ...
                'EquilibriumReactor', 'd', ...
                'Heater',   '*', ...
                'Cooler',   'x', ...
                'HeatExchanger','o', ...
                'Compressor','+', ...
                'Turbine',  '+', ...
                'Separator','^', ...  % triangle up
                'Purge',    'v', ...     % triangle down
                'Splitter', '>', ...
                'Recycle',  '<', ...
                'Bypass',   'p', ...
                'Manifold', 'o', ...
                'Source',   '>', ...
                'Sink',     '<', ...
                'DesignSpec','d', ...
                'Adjust',   'h', ...
                'Calculator','p', ...
                'Constraint','s');
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

        function dialogHeater(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Heater', 500, 260, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'}}, ...
                 {sprintf('Thermal value (Tout [%s] or duty [%s]):', app.unitPrefs.temperature, app.unitPrefs.duty),'numeric',app.fromSI(400,'temperature')}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'}}, ...
                 {sprintf('Pressure value (dP [%s], Pout [%s], or PR):', app.unitPrefs.pressure, app.unitPrefs.pressure),'numeric',0}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=app.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=app.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=app.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=app.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Heater'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;

                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal)
                    uialert(d,'Thermal value must be finite.','Error'); return;
                end
                if strcmp(tMode,'Tout'), def.Tout=app.toSI(tVal,'temperature'); else, def.duty=app.toSI(tVal,'duty'); end

                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', app.unitPrefs.pressure),'Error'); return; end
                    def.Pout = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end

                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end

                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Heater(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCooler(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Cooler', 500, 260, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Thermal spec:','dropdown',{'Tout','duty'}}, ...
                 {sprintf('Thermal value (Tout [%s] or duty [%s]):', app.unitPrefs.temperature, app.unitPrefs.duty),'numeric',app.fromSI(300,'temperature')}, ...
                 {'Pressure spec:','dropdown',{'pass-through','dP','Pout','PR'}}, ...
                 {sprintf('Pressure value (dP [%s], Pout [%s], or PR):', app.unitPrefs.pressure, app.unitPrefs.pressure),'numeric',0}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Tout), ctrls{3}.Value='Tout'; ctrls{4}.Value=app.fromSI(u.Tout,'temperature');
                else, ctrls{3}.Value='duty'; ctrls{4}.Value=app.fromSI(u.duty,'duty'); end
                if isprop(u,'dP') && isfinite(u.dP)
                    ctrls{5}.Value='dP'; ctrls{6}.Value=app.fromSI(u.dP,'pressure');
                elseif isprop(u,'Pout') && isfinite(u.Pout)
                    ctrls{5}.Value='Pout'; ctrls{6}.Value=app.fromSI(u.Pout,'pressure');
                elseif isprop(u,'PR') && isfinite(u.PR)
                    ctrls{5}.Value='PR'; ctrls{6}.Value=u.PR;
                else
                    ctrls{5}.Value='pass-through'; ctrls{6}.Value=0;
                end
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Cooler'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;

                tMode=ctrls{3}.Value; tVal=ctrls{4}.Value;
                if ~isfinite(tVal)
                    uialert(d,'Thermal value must be finite.','Error'); return;
                end
                if strcmp(tMode,'Tout'), def.Tout=app.toSI(tVal,'temperature'); else, def.duty=app.toSI(tVal,'duty'); end

                pMode=ctrls{5}.Value; pVal=ctrls{6}.Value;
                if ~strcmp(pMode,'pass-through') && ~isfinite(pVal)
                    uialert(d,'Pressure value must be finite for selected pressure mode.','Error'); return;
                end
                if strcmp(pMode,'dP')
                    def.dP = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'Pout')
                    if pVal <= 0, uialert(d,sprintf('Pout must be > 0 %s.', app.unitPrefs.pressure),'Error'); return; end
                    def.Pout = app.toSI(pVal,'pressure');
                elseif strcmp(pMode,'PR')
                    if pVal <= 0, uialert(d,'PR must be > 0.','Error'); return; end
                    def.PR = pVal;
                end

                pCount = double(isfield(def,'dP')) + double(isfield(def,'Pout')) + double(isfield(def,'PR'));
                if pCount > 1
                    uialert(d,'Select only one pressure mode (dP, Pout, or PR).','Error'); return;
                end

                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Cooler(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogHeatExchanger(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure HeatExchanger', 520, 260, ...
                {{'Hot inlet:','dropdown',sNames}, ...
                 {'Hot outlet:','dropdown',sNames}, ...
                 {'Cold inlet:','dropdown',sNames}, ...
                 {'Cold outlet:','dropdown',sNames}, ...
                 {'Spec mode:','dropdown',{'Th_out','Tc_out','duty'}}, ...
                 {sprintf('Value (T [%s] or Q [%s]):', app.unitPrefs.temperature, app.unitPrefs.duty),'numeric',app.fromSI(350,'temperature')}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.hotInlet.name));
                ctrls{2}.Value=char(string(u.hotOutlet.name));
                ctrls{3}.Value=char(string(u.coldInlet.name));
                ctrls{4}.Value=char(string(u.coldOutlet.name));
                if isfinite(u.Th_out), ctrls{5}.Value='Th_out'; ctrls{6}.Value=app.fromSI(u.Th_out,'temperature');
                elseif isfinite(u.Tc_out), ctrls{5}.Value='Tc_out'; ctrls{6}.Value=app.fromSI(u.Tc_out,'temperature');
                else, ctrls{5}.Value='duty'; ctrls{6}.Value=app.fromSI(u.duty,'duty'); end
            elseif numel(sNames)>=4
                ctrls{2}.Value=sNames{2}; ctrls{3}.Value=sNames{3}; ctrls{4}.Value=sNames{4};
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='HeatExchanger';
                def.hotInlet=ctrls{1}.Value; def.hotOutlet=ctrls{2}.Value;
                def.coldInlet=ctrls{3}.Value; def.coldOutlet=ctrls{4}.Value;
                mode=ctrls{5}.Value; val=ctrls{6}.Value;
                if strcmp(mode,'Th_out'), def.Th_out=app.toSI(val,'temperature');
                elseif strcmp(mode,'Tc_out'), def.Tc_out=app.toSI(val,'temperature');
                else, def.duty=app.toSI(val,'duty'); end
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {};
                if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                u=proc.units.HeatExchanger(app.findStream(def.hotInlet),app.findStream(def.hotOutlet),...
                    app.findStream(def.coldInlet),app.findStream(def.coldOutlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCompressor(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Compressor', 480, 220, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'}}, ...
                 {sprintf('Value (Pout [%s] or PR):', app.unitPrefs.pressure),'numeric',app.fromSI(2e5,'pressure')}, ...
                 {'Isentropic efficiency (0-1]:','numeric',0.85}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=app.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Compressor'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=app.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Compressor(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogTurbine(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Turbine', 480, 220, ...
                {{'Inlet:','dropdown',sNames}, ...
                 {'Outlet:','dropdown',sNames}, ...
                 {'Pressure spec:','dropdown',{'Pout','PR'}}, ...
                 {sprintf('Value (Pout [%s] or PR):', app.unitPrefs.pressure),'numeric',app.fromSI(5e4,'pressure')}, ...
                 {'Isentropic efficiency (0-1]:','numeric',0.85}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.inlet.name));
                ctrls{2}.Value=char(string(u.outlet.name));
                if isfinite(u.Pout), ctrls{3}.Value='Pout'; ctrls{4}.Value=app.fromSI(u.Pout,'pressure');
                else, ctrls{3}.Value='PR'; ctrls{4}.Value=u.PR; end
                ctrls{5}.Value=u.eta;
            elseif numel(sNames)>=2, ctrls{2}.Value=sNames{2}; end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def.type='Turbine'; def.inlet=ctrls{1}.Value; def.outlet=ctrls{2}.Value;
                mode=ctrls{3}.Value; val=ctrls{4}.Value;
                if strcmp(mode,'Pout'), def.Pout=app.toSI(val,'pressure'); else, def.PR=val; end
                def.eta=ctrls{5}.Value;
                mix = app.buildThermoMixForGUI();
                if isempty(mix), uialert(d,'Species not in thermo library.','Error'); return; end
                args = {'eta', def.eta};
                if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                u=proc.units.Turbine(app.findStream(def.inlet),app.findStream(def.outlet),mix,args{:});
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

                app.refreshResultsTable();

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


        function refreshResultsTable(app)
            if isempty(app.lastFlowsheet)
                app.ResultsTable.Data = table();
                app.ResultsTable.ColumnName = {};
                return;
            end

            includeAliases = ~isempty(app.ResultsShowAliasesCheck) && app.ResultsShowAliasesCheck.Value;
            showAliasColumn = true;
            if ~isempty(app.ResultsShowAliasColumnCheck)
                showAliasColumn = app.ResultsShowAliasColumnCheck.Value;
            end

            T = app.lastFlowsheet.streamTable( ...
                'includeAliases', includeAliases, ...
                'showAliasColumn', showAliasColumn);
            T = app.convertDisplayStreamTable(T);
            app.ResultsTable.Data = T;
            app.ResultsTable.ColumnName = app.displayColumnNames(T.Properties.VariableNames);

            if includeAliases
                app.ResultsNameModeLabel.Text = 'Alias rows are enabled: a single stream handle may appear more than once under different names.';
            elseif showAliasColumn
                app.ResultsNameModeLabel.Text = 'Canonical rows shown. Alias names (if any) are listed in the aliases column.';
            else
                app.ResultsNameModeLabel.Text = 'Canonical rows shown. Enable alias rows or the aliases column to view alternate names.';
            end
        end

    end


    % =====================================================================
    %  UNIT TABLE POPUP
    % =====================================================================
    methods (Access = private)
        function openUnitTablePopup(app)
            if ~isempty(app.UnitTableFig) && isvalid(app.UnitTableFig)
                app.refreshUnitTablePopup();
                app.UnitTableFig.Visible = 'on';
                return;
            end

            app.UnitTableFig = uifigure('Name','MathLab — Unit Results Table', ...
                'Position',[120 80 980 480], 'Color',[0.97 0.97 0.98]);
            app.UnitTableFig.CloseRequestFcn = @(src,~) app.onUnitTablePopupClosed(src);

            gl = uigridlayout(app.UnitTableFig, [3 1], ...
                'RowHeight',{34,'1x',32}, 'Padding',[10 10 10 10], 'RowSpacing',6);

            topG = uigridlayout(gl, [1 4], 'ColumnWidth',{'fit','1x',110,110}, ...
                'Padding',[0 0 0 0], 'ColumnSpacing',6);
            topG.Layout.Row = 1;
            uilabel(topG, 'Text','Unit Results Table (Read-only)', 'FontWeight','bold', 'FontSize',13);
            uilabel(topG, 'Text','Type + connected streams + solved metrics (duty/power/conversion) are flattened for quick review.', ...
                'FontColor',[0.35 0.35 0.35]);
            uibutton(topG, 'push', 'Text','Export CSV', ...
                'ButtonPushedFcn',@(~,~) app.exportUnitTableToOutput('csv'));
            uibutton(topG, 'push', 'Text','Export MAT', ...
                'ButtonPushedFcn',@(~,~) app.exportUnitTableToOutput('mat'));

            app.UnitTable = uitable(gl, ...
                'ColumnEditable', false(1,9), ...
                'ColumnName', {'Unit #','Type','Connected Streams', ...
                               'Spec 1 Label','Spec 1 Value', ...
                               'Spec 2 Label','Spec 2 Value', ...
                               'Spec 3 Label','Spec 3 Value'});
            app.UnitTable.Layout.Row = 2;

            app.UnitTableStatusLabel = uilabel(gl, 'Text','', 'FontColor',[0.3 0.3 0.3]);
            app.UnitTableStatusLabel.Layout.Row = 3;

            app.refreshUnitTablePopup();
        end

        function onUnitTablePopupClosed(app, src)
            if ~isempty(src) && isvalid(src)
                delete(src);
            end
            app.UnitTableFig = [];
            app.UnitTable = [];
            app.UnitTableStatusLabel = [];
        end

        function refreshUnitTablePopup(app)
            if isempty(app.UnitTable) || ~isvalid(app.UnitTable)
                return;
            end
            T = app.buildUnitResultsTable();
            app.UnitTable.Data = T;
            app.UnitTable.ColumnName = T.Properties.VariableNames;
            if isempty(T)
                status = 'No units defined yet.';
            elseif isempty(app.lastSolver) || isempty(app.lastFlowsheet)
                status = sprintf('%d unit(s). Showing configured values. Run Solve for calculated metrics.', height(T));
            else
                status = sprintf('%d unit(s). Read-only simulation view with solved metrics.', height(T));
            end
            if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                app.UnitTableStatusLabel.Text = status;
            end
        end

        function T = buildUnitResultsTable(app)
            if ~isempty(app.lastFlowsheet) && isprop(app.lastFlowsheet, 'units')
                T = app.buildUnitTableFromObjects(app.lastFlowsheet.units);
            elseif ~isempty(app.units)
                T = app.buildUnitTableFromObjects(app.units);
            else
                T = app.buildUnitTable();
            end
        end

        function T = buildUnitTableFromObjects(app, units)
            n = numel(units);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Result1_Label','Result1_Value','Result2_Label','Result2_Value','Result3_Label','Result3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = app.serializeUnitObjectRow(i, units{i});
            end
            T = cell2table(data, 'VariableNames', cols);
        end

        function row = serializeUnitObjectRow(app, idx, u)
            row = {idx, app.shortTypeName(u), '-', '-', '-', '-', '-', '-', '-'};
            row{3} = app.unitObjectConnectedStreams(u);
            pairs = app.unitObjectResultPairs(u);
            for k = 1:min(3,size(pairs,1))
                row{3 + (k-1)*2 + 1} = pairs{k,1};
                row{3 + (k-1)*2 + 2} = pairs{k,2};
            end
        end

        function streamText = unitObjectConnectedStreams(app, u)
            names = {};
            if ismethod(u, 'streamNames')
                try
                    names = u.streamNames();
                catch
                    names = {};
                end
            end
            if isempty(names)
                streamText = '-';
            else
                streamText = app.formatSpecValue(names);
            end
        end

        function pairs = unitObjectResultPairs(app, u)
            pairs = {};
            cn = class(u);
            if contains(cn,'HeatExchanger')
                pairs = {app.unitLabel('duty','Duty'), app.safeMethodValue(u,'getDuty','duty'); ...
                         app.unitLabel('temperature','Hot Tout'), app.safePropValue(u,'hotOutlet','T','temperature'); ...
                         app.unitLabel('temperature','Cold Tout'), app.safePropValue(u,'coldOutlet','T','temperature')};
            elseif contains(cn,'Heater') || contains(cn,'Cooler')
                pairs = {app.unitLabel('duty','Duty'), app.safeMethodValue(u,'getDuty','duty'); ...
                         app.unitLabel('temperature','Tin'), app.safePropValue(u,'inlet','T','temperature'); ...
                         app.unitLabel('temperature','Tout'), app.safePropValue(u,'outlet','T','temperature')};
            elseif contains(cn,'Compressor') || contains(cn,'Turbine')
                pairs = {app.unitLabel('power','Power'), app.safeMethodValue(u,'getPower','power'); ...
                         'Pressure ratio', app.safePressureRatio(u); ...
                         'Eta', app.safeSimpleProp(u,'eta')};
            elseif contains(cn,'ConversionReactor') || contains(cn,'YieldReactor') || contains(cn,'Reactor')
                pairs = {'Conversion', app.safeSimpleProp(u,'conversion'); ...
                         app.unitLabel('temperature','Tin'), app.safePropValue(u,'inlet','T','temperature'); ...
                         app.unitLabel('temperature','Tout'), app.safePropValue(u,'outlet','T','temperature')};
            elseif contains(cn,'StoichiometricReactor')
                pairs = {'Extent', app.safeSimpleProp(u,'extent'); ...
                         'Extent mode', app.safeSimpleProp(u,'extentMode'); ...
                         'Ref species', app.safeSimpleProp(u,'referenceSpecies')};
            elseif contains(cn,'Separator')
                pairs = {'Split phi', app.safeSimpleProp(u,'phi')};
            elseif contains(cn,'Purge')
                pairs = {'Purge beta', app.safeSimpleProp(u,'beta')};
            else
                pairs = {'Description', app.safeDescribe(u)};
            end
        end

        function val = safeMethodValue(app, u, m, quantity)
            try
                if ismethod(u,m)
                    raw = u.(m)();
                    if nargin >= 4 && ~isempty(quantity)
                        raw = app.fromSI(raw, quantity);
                    end
                    val = app.formatSpecValue(raw);
                else
                    val = '-';
                end
            catch
                val = '-';
            end
        end

        function val = safeSimpleProp(app, u, p)
            try
                if isprop(u,p)
                    val = app.formatSpecValue(u.(p));
                else
                    val = '-';
                end
            catch
                val = '-';
            end
        end

        function val = safePropValue(app, u, ownerProp, fieldProp, quantity)
            try
                if isprop(u, ownerProp)
                    owner = u.(ownerProp);
                    if isprop(owner, fieldProp)
                        raw = owner.(fieldProp);
                        if nargin >= 5 && ~isempty(quantity)
                            raw = app.fromSI(raw, quantity);
                        end
                        val = app.formatSpecValue(raw);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function val = safePressureRatio(app, u)
            try
                if isprop(u,'PR') && isfinite(u.PR)
                    val = app.formatSpecValue(u.PR);
                    return;
                end
                if isprop(u,'inlet') && isprop(u,'outlet')
                    p1 = u.inlet.P;
                    p2 = u.outlet.P;
                    if isfinite(p1) && p1 ~= 0 && isfinite(p2)
                        val = app.formatSpecValue(p2/p1);
                        return;
                    end
                end
            catch
            end
            val = '-';
        end

        function txt = safeDescribe(~, u)
            try
                if ismethod(u,'describe')
                    txt = char(string(u.describe()));
                else
                    txt = class(u);
                end
            catch
                txt = class(u);
            end
        end

        function T = buildUnitTable(app)
            n = numel(app.unitDefs);
            cols = {'Unit_Index','Type','Connected_Streams', ...
                    'Spec1_Label','Spec1_Value','Spec2_Label','Spec2_Value','Spec3_Label','Spec3_Value'};
            if n == 0
                T = cell2table(cell(0, numel(cols)), 'VariableNames', cols);
                return;
            end
            data = cell(n, numel(cols));
            for i = 1:n
                data(i,:) = app.serializeUnitDefRow(i, app.unitDefs{i});
            end
            T = cell2table(data, 'VariableNames', cols);
        end

        function row = serializeUnitDefRow(app, idx, def)
            row = {idx, '-', '-', '-', '-', '-', '-', '-', '-'};
            if ~isstruct(def) || ~isfield(def,'type')
                return;
            end
            typ = char(string(def.type));
            row{2} = typ;
            row{3} = app.unitConnectedStreams(def);

            specs = app.unitSpecPairs(def);
            for k = 1:min(3,size(specs,1))
                row{3 + (k-1)*2 + 1} = specs{k,1};
                row{3 + (k-1)*2 + 2} = specs{k,2};
            end
        end

        function streamText = unitConnectedStreams(app, def)
            parts = {};
            fSingle = {'inlet','outlet','source','tear','stream','recycle','purge','outletA','outletB', ...
                'processInlet','bypassStream','processReturn','hotInlet','hotOutlet','coldInlet','coldOutlet', ...
                'lhsStream','aStream','bStream'};
            for i = 1:numel(fSingle)
                f = fSingle{i};
                if isfield(def,f)
                    parts{end+1} = sprintf('%s=%s', f, app.formatSpecValue(def.(f))); %#ok<AGROW>
                end
            end
            if isfield(def,'inlets')
                parts{end+1} = sprintf('inlets=%s', app.formatSpecValue(def.inlets)); %#ok<AGROW>
            end
            if isfield(def,'outlets')
                parts{end+1} = sprintf('outlets=%s', app.formatSpecValue(def.outlets)); %#ok<AGROW>
            end
            if isempty(parts)
                streamText = '-';
            else
                streamText = strjoin(parts, ' | ');
            end
        end

        function specs = unitSpecPairs(app, def)
            specs = {};
            typ = char(string(def.type));
            switch typ
                case 'Mixer'
                    specs = {'No. inlets', app.formatSpecValue(numel(def.inlets)); 'Outlet', app.formatSpecValue(def.outlet)};
                case 'Heater'
                    specs = {app.unitLabel('temperature','Tout'), app.getDefField(def,'Tout','temperature'); app.unitLabel('duty','Qdot'), app.getDefField(def,'duty','duty'); 'dP/Pout/PR', app.getDefField(def,'dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = app.getDefField(def,'Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                            specs{3,2} = app.getDefField(def,'PR');
                        end
                    end
                case 'Cooler'
                    specs = {app.unitLabel('temperature','Tout'), app.getDefField(def,'Tout','temperature'); app.unitLabel('duty','Qdot'), app.getDefField(def,'duty','duty'); 'dP/Pout/PR', app.getDefField(def,'dP','pressure')};
                    if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                        specs{3,2} = app.getDefField(def,'Pout','pressure');
                        if ischar(specs{3,2}) && strcmp(specs{3,2},'-')
                            specs{3,2} = app.getDefField(def,'PR');
                        end
                    end
                case 'Compressor'
                    specs = {'Pressure ratio', app.getDefField(def,'PR'); 'Efficiency', app.getDefField(def,'eta')};
                case 'Turbine'
                    specs = {'Pressure ratio', app.getDefField(def,'PR'); 'Efficiency', app.getDefField(def,'eta')};
                case 'Reactor'
                    specs = {'Conversion', app.getDefField(def,'conversion'); 'Reactions', app.getDefField(def,'reactions')};
                case 'ConversionReactor'
                    specs = {'Key species', app.getDefField(def,'keySpecies'); 'Conversion', app.getDefField(def,'conversion'); 'Mode', app.getDefField(def,'conversionMode')};
                case 'StoichiometricReactor'
                    specs = {'Extent', app.getDefField(def,'extent'); 'Mode', app.getDefField(def,'extentMode'); 'Ref species', app.getDefField(def,'referenceSpecies')};
                case 'YieldReactor'
                    specs = {'Basis species', app.getDefField(def,'basisSpecies'); 'Conversion', app.getDefField(def,'conversion'); 'Products', app.getDefField(def,'productSpecies')};
                case 'EquilibriumReactor'
                    specs = {'Keq', app.getDefField(def,'Keq'); 'Ref species', app.getDefField(def,'referenceSpecies'); 'Stoich nu', app.getDefField(def,'nu')};
                case 'Separator'
                    specs = {'Split phi', app.getDefField(def,'phi')};
                case 'Purge'
                    specs = {'Purge beta', app.getDefField(def,'beta')};
                case 'Splitter'
                    if isfield(def,'splitFractions')
                        specs = {'Mode', 'fractions'; 'Values', app.getDefField(def,'splitFractions')};
                    else
                        specs = {'Mode', 'flows'; 'Values', app.getDefField(def,'specifiedOutletFlows')};
                    end
                case 'Bypass'
                    specs = {'Bypass fraction', app.getDefField(def,'bypassFraction')};
                case 'Manifold'
                    specs = {'Route', app.getDefField(def,'route')};
                case 'Source'
                    specs = {app.unitLabel('flow','Total flow'), app.getDefField(def,'totalFlow','flow'); 'Composition', app.getDefField(def,'composition'); app.unitLabel('flow','Comp flows'), app.getDefField(def,'componentFlows','flow')};
                case 'DesignSpec'
                    specs = {'Metric', app.getDefField(def,'metric'); 'Target', app.getDefField(def,'target'); 'Species idx', app.getDefField(def,'speciesIndex')};
                case 'Adjust'
                    specs = {'Field', app.getDefField(def,'field'); 'Index', app.getDefField(def,'index'); 'Bounds', sprintf('[%s, %s]', app.getDefField(def,'minValue'), app.getDefField(def,'maxValue'))};
                case 'Calculator'
                    specs = {'LHS field', app.getDefField(def,'lhsField'); 'Operator', app.getDefField(def,'operator'); 'RHS fields', sprintf('%s %s %s', app.getDefField(def,'aField'), app.getDefField(def,'operator'), app.getDefField(def,'bField'))};
                case 'Constraint'
                    specs = {'Field', app.getDefField(def,'field'); 'Value', app.getDefField(def,'value'); 'Index', app.getDefField(def,'index')};
                otherwise
                    specs = {'Spec struct fields', app.formatSpecValue(fieldnames(def)')};
            end
        end

        function val = getDefField(app, def, fld, quantity)
            if nargin < 4
                quantity = '';
            end
            if isfield(def, fld)
                raw = def.(fld);
                if ~isempty(quantity)
                    raw = app.fromSI(raw, quantity);
                end
                val = app.formatSpecValue(raw);
            else
                val = '-';
            end
        end

        function txt = formatSpecValue(~, val)
            if ischar(val)
                txt = val;
            elseif isstring(val)
                txt = char(val);
            elseif isnumeric(val) || islogical(val)
                if isscalar(val)
                    txt = num2str(val);
                else
                    txt = mat2str(val);
                end
            elseif iscell(val)
                c = cell(size(val));
                for i = 1:numel(val)
                    c{i} = char(string(val{i}));
                end
                txt = ['{' strjoin(c, ', ') '}'];
            else
                txt = char(string(val));
            end
        end

        function valOut = toSI(app, valIn, quantity)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(app.unitPrefs.flow,'mol/s')
                        valOut = valIn / 1000;
                    end
                case 'temperature'
                    if strcmp(app.unitPrefs.temperature,'C')
                        valOut = valIn + 273.15;
                    end
                case 'pressure'
                    switch app.unitPrefs.pressure
                        case 'kPa', valOut = valIn * 1e3;
                        case 'bar', valOut = valIn * 1e5;
                    end
                case {'duty','power'}
                    unitName = app.unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn * 1e3;
                        case 'MW', valOut = valIn * 1e6;
                    end
            end
        end

        function valOut = fromSI(app, valIn, quantity)
            valOut = valIn;
            if isempty(valIn) || ~isnumeric(valIn)
                return;
            end
            switch quantity
                case 'flow'
                    if strcmp(app.unitPrefs.flow,'mol/s')
                        valOut = valIn * 1000;
                    end
                case 'temperature'
                    if strcmp(app.unitPrefs.temperature,'C')
                        valOut = valIn - 273.15;
                    end
                case 'pressure'
                    switch app.unitPrefs.pressure
                        case 'kPa', valOut = valIn / 1e3;
                        case 'bar', valOut = valIn / 1e5;
                    end
                case {'duty','power'}
                    unitName = app.unitPrefs.(quantity);
                    switch unitName
                        case 'kW', valOut = valIn / 1e3;
                        case 'MW', valOut = valIn / 1e6;
                    end
            end
        end

        function txt = unitLabel(app, quantity, base)
            switch quantity
                case 'flow', u = app.unitPrefs.flow;
                case 'temperature', u = app.unitPrefs.temperature;
                case 'pressure', u = app.unitPrefs.pressure;
                case 'duty', u = app.unitPrefs.duty;
                case 'power', u = app.unitPrefs.power;
                otherwise, u = '';
            end
            if isempty(u)
                txt = base;
            else
                txt = sprintf('%s (%s)', base, u);
            end
        end

        function T = convertDisplayStreamTable(app, T)
            if isempty(T)
                return;
            end
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                v = vars{i};
                if strcmp(v,'n_dot')
                    T.(v) = app.fromSI(T.(v), 'flow');
                elseif strcmp(v,'T')
                    T.(v) = app.fromSI(T.(v), 'temperature');
                elseif strcmp(v,'P')
                    T.(v) = app.fromSI(T.(v), 'pressure');
                end
            end
        end

        function names = displayColumnNames(app, names)
            for i = 1:numel(names)
                if strcmp(names{i},'n_dot')
                    names{i} = app.unitLabel('flow','n_dot');
                elseif strcmp(names{i},'T')
                    names{i} = app.unitLabel('temperature','T');
                elseif strcmp(names{i},'P')
                    names{i} = app.unitLabel('pressure','P');
                end
            end
        end

        function onUnitPrefsChanged(app, key, value)
            app.unitPrefs.(key) = char(string(value));
            app.refreshStreamTables();
            app.refreshResultsTable();
            app.refreshUnitTablePopup();
        end

        function prefs = mergeUnitPrefs(~, inPrefs)
            prefs = struct('flow','kmol/s','temperature','K','pressure','Pa','duty','kW','power','kW');
            fns = fieldnames(prefs);
            for i = 1:numel(fns)
                f = fns{i};
                if isfield(inPrefs,f) && ~(isempty(inPrefs.(f)))
                    prefs.(f) = char(string(inPrefs.(f)));
                end
            end
        end

        function applyUnitPrefsToControls(app)
            if ~isempty(app.FlowUnitDropDown), app.FlowUnitDropDown.Value = app.unitPrefs.flow; end
            if ~isempty(app.TempUnitDropDown), app.TempUnitDropDown.Value = app.unitPrefs.temperature; end
            if ~isempty(app.PressureUnitDropDown), app.PressureUnitDropDown.Value = app.unitPrefs.pressure; end
            if ~isempty(app.DutyUnitDropDown), app.DutyUnitDropDown.Value = app.unitPrefs.duty; end
            if ~isempty(app.PowerUnitDropDown), app.PowerUnitDropDown.Value = app.unitPrefs.power; end
        end

        function fmt = normalizeUnitTableExportFormat(~, fmt)
            if ~(ischar(fmt) || (isstring(fmt) && isscalar(fmt)))
                error('MathLab:UnitTable:InvalidFormat', ...
                    'Unit table export format must be a non-empty text scalar (''csv'' or ''mat'').');
            end
            fmt = lower(strtrim(char(string(fmt))));
            if isempty(fmt)
                error('MathLab:UnitTable:InvalidFormat', ...
                    'Unit table export format must be a non-empty text scalar (''csv'' or ''mat'').');
            end
            if ~ismember(fmt, {'csv','mat'})
                error('MathLab:UnitTable:UnsupportedFormat', ...
                    'Unsupported unit table export format "%s". Supported formats: csv, mat.', fmt);
            end
        end

        % Single export entry point for unit table exports (avoid duplicate methods during refactors).
        function exportUnitTableToOutput(app, fmt)
            fmt = app.normalizeUnitTableExportFormat(fmt);

            outDir = app.ensureOutputDir('results');
            outDirMsg = char(string(outDir));
            if isempty(strtrim(outDirMsg)) || ~isfolder(outDirMsg)
                reason = sprintf('Output directory is not valid: %s', outDirMsg);
                app.setStatus(sprintf('Unit table export failed: %s', reason));
                if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                    app.UnitTableStatusLabel.Text = sprintf('Unit table export failed: %s', reason);
                end
                uialert(app.Fig, sprintf(['Failed to export unit table.\nResolved output directory: %s\nReason: %s'], outDirMsg, reason), ...
                    'Unit Table Export Failed', 'Icon', 'error');
                return;
            end

            try
                T = app.buildUnitResultsTable();
                switch fmt
                    case 'csv'
                        filepath = fullfile(outDirMsg, app.autoFileName('unit_table', 'csv'));
                        writetable(T, filepath);
                    case 'mat'
                        filepath = fullfile(outDirMsg, app.autoFileName('unit_table', 'mat'));
                        unitTable = T; %#ok<NASGU>
                        save(filepath, 'unitTable');
                    otherwise
                        error('MathLab:UnitTable:UnsupportedFormat', ...
                            'Unsupported unit table export format "%s". Supported formats: csv, mat.', fmt);
                end
            catch ME
                reason = strtrim(ME.message);
                failMsg = sprintf('Unit table export failed: %s (output dir: %s)', reason, outDirMsg);
                app.setStatus(failMsg);
                if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                    app.UnitTableStatusLabel.Text = failMsg;
                end
                uialert(app.Fig, sprintf(['Failed to export unit table as %s.\nResolved output directory: %s\nReason: %s'], ...
                    upper(fmt), outDirMsg, reason), 'Unit Table Export Failed', 'Icon', 'error');
                return;
            end

            app.setStatus(sprintf('Unit table exported to %s (output dir: %s)', filepath, outDirMsg));
            if ~isempty(app.UnitTableStatusLabel) && isvalid(app.UnitTableStatusLabel)
                app.UnitTableStatusLabel.Text = sprintf('Exported %s (%d rows): %s [dir: %s]', upper(fmt), height(T), filepath, outDirMsg);
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


        function dialogSource(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            ns = numel(app.speciesNames);
            [d, ctrls] = app.makeDialog('Configure Source', 520, 240, ...
                {{'Outlet:','dropdown',sNames}, ...
                 {'Total flow n_dot (NaN=none):','numeric',10}, ...
                 {sprintf('Composition y (%d vals, NaN skip):',ns),'text',num2str(nan(1,ns))}, ...
                 {sprintf('Component flows n_i (%d vals, NaN skip):',ns),'text',num2str(nan(1,ns))}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.outlet.name));
                ctrls{2}.Value=u.totalFlow;
                ctrls{3}.Value=num2str(u.composition);
                ctrls{4}.Value=num2str(u.componentFlows);
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def=struct(); def.type='Source'; def.outlet=ctrls{1}.Value;
                def.totalFlow=ctrls{2}.Value;
                def.composition=str2num(ctrls{3}.Value); %#ok
                def.componentFlows=str2num(ctrls{4}.Value); %#ok
                opts = struct('totalFlow',def.totalFlow,'composition',def.composition,'componentFlows',def.componentFlows);
                u=proc.units.Source(app.findStream(def.outlet), opts);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogSink(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Sink', 360, 120, ...
                {{'Inlet:','dropdown',sNames}});
            if ~isempty(editIdx)
                u=app.units{editIdx}; ctrls{1}.Value=char(string(u.inlet.name));
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def=struct('type','Sink','inlet',ctrls{1}.Value);
                u=proc.units.Sink(app.findStream(def.inlet));
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogDesignSpec(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure DesignSpec', 460, 180, ...
                {{'Stream:','dropdown',sNames}, ...
                 {'Metric:','dropdown',{'total_flow','comp_flow','mole_fraction'}}, ...
                 {'Component index:','numeric',1}, ...
                 {'Target:','numeric',0.5}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.stream.name)); ctrls{2}.Value=u.metric;
                ctrls{3}.Value=u.componentIndex; ctrls{4}.Value=u.target;
            end
            app.addDialogButtons(d, @okCb);
            function okCb()
                def=struct('type','DesignSpec','stream',ctrls{1}.Value,'metric',ctrls{2}.Value,...
                    'componentIndex',ctrls{3}.Value,'target',ctrls{4}.Value);
                u=proc.units.DesignSpec(app.findStream(def.stream), def.metric, def.target, def.componentIndex);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogAdjust(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Adjust', 520, 210, ...
                {{'DesignSpec unit index:','numeric',1}, ...
                 {'Manipulated unit index:','numeric',1}, ...
                 {'Field name:','text','beta'}, ...
                 {'Field index (NaN=scalar):','numeric',NaN}, ...
                 {'Min value:','numeric',0}, ...
                 {'Max value:','numeric',1}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{3}.Value=u.variableField; ctrls{4}.Value=u.variableIndex;
                ctrls{5}.Value=u.minValue; ctrls{6}.Value=u.maxValue;
            end
            app.addDialogButtons(d,@okCb);
            function okCb()
                dsIdx=round(ctrls{1}.Value); muIdx=round(ctrls{2}.Value);
                if dsIdx<1||dsIdx>numel(app.units) || ~isa(app.units{dsIdx},'proc.units.DesignSpec')
                    uialert(d,'DesignSpec index must refer to an existing DesignSpec unit.','Error'); return;
                end
                if muIdx<1||muIdx>numel(app.units)
                    uialert(d,'Manipulated unit index invalid.','Error'); return;
                end
                def=struct('type','Adjust','designSpecIndex',dsIdx,'ownerIndex',muIdx,'field',ctrls{3}.Value,...
                    'index',ctrls{4}.Value,'minValue',ctrls{5}.Value,'maxValue',ctrls{6}.Value);
                u=proc.units.Adjust(app.units{dsIdx}, app.units{muIdx}, def.field, def.index, def.minValue, def.maxValue);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogCalculator(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Calculator', 620, 260, ...
                {{'LHS stream:','dropdown',sNames},{'LHS field:','dropdown',{'n_dot','T','P'}}, ...
                 {'A stream:','dropdown',sNames},{'A field:','dropdown',{'n_dot','T','P'}}, ...
                 {'Operator:','dropdown',{'+' '-' '*' '/'}}, ...
                 {'B stream:','dropdown',sNames},{'B field:','dropdown',{'n_dot','T','P'}}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.lhsOwner.name)); ctrls{2}.Value=u.lhsField;
                ctrls{3}.Value=char(string(u.aOwner.name)); ctrls{4}.Value=u.aField;
                ctrls{5}.Value=u.operator;
                ctrls{6}.Value=char(string(u.bOwner.name)); ctrls{7}.Value=u.bField;
            end
            app.addDialogButtons(d,@okCb);
            function okCb()
                def=struct('type','Calculator','lhsStream',ctrls{1}.Value,'lhsField',ctrls{2}.Value,...
                    'aStream',ctrls{3}.Value,'aField',ctrls{4}.Value,'operator',ctrls{5}.Value,...
                    'bStream',ctrls{6}.Value,'bField',ctrls{7}.Value);
                u=proc.units.Calculator(app.findStream(def.lhsStream),def.lhsField,...
                    app.findStream(def.aStream),def.aField,def.operator,...
                    app.findStream(def.bStream),def.bField);
                app.commitUnit(u,def,editIdx); delete(d);
            end
        end

        function dialogConstraint(app, sNames, editIdx)
            if nargin<3, editIdx=[]; end
            [d, ctrls] = app.makeDialog('Configure Constraint', 460, 170, ...
                {{'Stream:','dropdown',sNames},{'Field:','dropdown',{'n_dot','T','P'}}, ...
                 {'Value:','numeric',1},{'Index (NaN=scalar):','numeric',NaN}});
            if ~isempty(editIdx)
                u=app.units{editIdx};
                ctrls{1}.Value=char(string(u.owner.name)); ctrls{2}.Value=u.field;
                ctrls{3}.Value=u.value; ctrls{4}.Value=u.index;
            end
            app.addDialogButtons(d,@okCb);
            function okCb()
                def=struct('type','Constraint','stream',ctrls{1}.Value,'field',ctrls{2}.Value,...
                    'value',ctrls{3}.Value,'index',ctrls{4}.Value);
                u=proc.units.Constraint(app.findStream(def.stream),def.field,def.value,def.index);
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
            try
                app.syncStreamsFromTable();
                app.saveConfig(filepath);
                app.setStatus(sprintf('Config save succeeded: %s', filepath));
            catch ME
                app.setStatus(sprintf('Config save failed: %s', filepath));
                uialert(app.Fig, sprintf('Failed to save config to:\n%s\n\n%s', filepath, ME.message), ...
                    'Save Config Failed', 'Icon', 'error');
            end
        end

        function saveConfigToOutput(app)
            filepath = '';
            try
                app.syncStreamsFromTable();
                outDir = app.ensureOutputDir('saves');
                fname = app.autoFileName('config', 'mat');
                filepath = fullfile(outDir, fname);
                app.saveConfig(filepath);
                app.setStatus(sprintf('Config save succeeded: %s', filepath));
            catch ME
                if isempty(filepath)
                    filepath = fullfile(pwd, 'output', 'saves');
                end
                app.setStatus(sprintf('Config save failed: %s', filepath));
                uialert(app.Fig, sprintf('Failed to save config to:\n%s\n\n%s', filepath, ME.message), ...
                    'Save Config Failed', 'Icon', 'error');
            end
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
                streamTable = app.lastFlowsheet.streamTable('showAliasColumn', true); %#ok
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
            if ~(ischar(filepath) || isstring(filepath)) || strlength(string(filepath)) == 0
                error('MathLab:SaveConfig:InvalidPath', 'Config path must be a non-empty string.');
            end
            filepath = char(string(filepath));
            saveDir = fileparts(filepath);
            if isempty(saveDir)
                saveDir = pwd;
            end
            app.ensureWritableDir(saveDir);

            cfg = app.buildValidatedConfigPayload();
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

            if isfield(cfg,'unitPrefs') && isstruct(cfg.unitPrefs)
                app.unitPrefs = app.mergeUnitPrefs(cfg.unitPrefs);
            end
            app.applyUnitPrefsToControls();

            app.refreshStreamTables();
            app.refreshUnitsListBox();
            app.refreshFlowsheetDiagram();
            app.updateDOF();
            app.refreshUnitTablePopup();
            app.updateSensDropdowns();
            app.refreshSpeciesPropsTable();

            % Auto-suggest next stream name
            if ~isempty(app.streams)
                lastName = char(string(app.streams{end}.name));
                tok = regexp(lastName,'^([A-Za-z_]*)(\d+)$','tokens');
                if ~isempty(tok)
                    app.StreamNameField.Value = sprintf('%s%d',tok{1}{1},str2double(tok{1}{2})+1);
                end
            end
        end

        function u = buildUnitFromDef(app, def, varargin)
            u = [];
            p = inputParser;
            p.addParameter('includeIdentityLink', true, @(x)islogical(x)&&isscalar(x));
            p.parse(varargin{:});
            includeIdentityLink = p.Results.includeIdentityLink;
            switch def.type
                case 'Link'
                    if app.isIdentityLinkDef(def) && ~includeIdentityLink
                        return;
                    end
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
                case 'Source'
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sOut)
                        opts = struct();
                        if isfield(def,'totalFlow'), opts.totalFlow = def.totalFlow; end
                        if isfield(def,'composition'), opts.composition = def.composition; end
                        if isfield(def,'componentFlows'), opts.componentFlows = def.componentFlows; end
                        u = proc.units.Source(sOut, opts);
                    end
                case 'Sink'
                    sIn = app.findStream(def.inlet);
                    if ~isempty(sIn), u = proc.units.Sink(sIn); end
                case 'DesignSpec'
                    s = app.findStream(def.stream);
                    if ~isempty(s)
                        u = proc.units.DesignSpec(s, def.metric, def.target, def.componentIndex);
                    end
                case 'Adjust'
                    if isfield(def,'designSpecIndex') && isfield(def,'ownerIndex') && ...
                            def.designSpecIndex <= numel(app.units) && def.ownerIndex <= numel(app.units)
                        ds = app.units{def.designSpecIndex};
                        owner = app.units{def.ownerIndex};
                        u = proc.units.Adjust(ds, owner, def.field, def.index, def.minValue, def.maxValue);
                    end
                case 'Calculator'
                    lhs = app.findStream(def.lhsStream);
                    a = app.findStream(def.aStream);
                    b = app.findStream(def.bStream);
                    if ~isempty(lhs) && ~isempty(a) && ~isempty(b)
                        u = proc.units.Calculator(lhs, def.lhsField, a, def.aField, def.operator, b, def.bField);
                    end
                case 'Constraint'
                    s = app.findStream(def.stream);
                    if ~isempty(s)
                        u = proc.units.Constraint(s, def.field, def.value, def.index);
                    end
                case 'Heater'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Heater(sIn, sOut, mix, args{:});
                    end
                case 'Cooler'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Tout'), args=[args,{'Tout',def.Tout}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        if isfield(def,'dP'), args=[args,{'dP',def.dP}]; end
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        u = proc.units.Cooler(sIn, sOut, mix, args{:});
                    end
                case 'HeatExchanger'
                    hIn = app.findStream(def.hotInlet);
                    hOut = app.findStream(def.hotOutlet);
                    cIn = app.findStream(def.coldInlet);
                    cOut = app.findStream(def.coldOutlet);
                    if ~isempty(hIn) && ~isempty(hOut) && ~isempty(cIn) && ~isempty(cOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Th_out'), args=[args,{'Th_out',def.Th_out}]; end
                        if isfield(def,'Tc_out'), args=[args,{'Tc_out',def.Tc_out}]; end
                        if isfield(def,'duty'), args=[args,{'duty',def.duty}]; end
                        u = proc.units.HeatExchanger(hIn, hOut, cIn, cOut, mix, args{:});
                    end
                case 'Compressor'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Compressor(sIn, sOut, mix, args{:});
                    end
                case 'Turbine'
                    sIn = app.findStream(def.inlet);
                    sOut = app.findStream(def.outlet);
                    if ~isempty(sIn) && ~isempty(sOut)
                        mix = app.buildThermoMixForGUI();
                        args = {};
                        if isfield(def,'Pout'), args=[args,{'Pout',def.Pout}]; end
                        if isfield(def,'PR'), args=[args,{'PR',def.PR}]; end
                        if isfield(def,'eta'), args=[args,{'eta',def.eta}]; end
                        u = proc.units.Turbine(sIn, sOut, mix, args{:});
                    end
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
                            isIdentityLink = ~(isfield(def, 'mode') && ~strcmp(def.mode, 'identity'));
                            if isfield(def, 'isIdentity')
                                isIdentityLink = logical(def.isIdentity);
                            end
                            if ~isIdentityLink
                                fprintf(fid, 'fs.addUnit(proc.units.Link(%s, %s));\n', def.inlet, def.outlet);
                            end
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
                        case 'Source'
                            fprintf(fid, 'srcOpts = struct(''totalFlow'', %.6g, ''composition'', %s, ''componentFlows'', %s);\n', ...
                                def.totalFlow, mat2str(def.composition,6), mat2str(def.componentFlows,6));
                            fprintf(fid, 'fs.addUnit(proc.units.Source(%s, srcOpts));\n', def.outlet);
                        case 'Sink'
                            fprintf(fid, 'fs.addUnit(proc.units.Sink(%s));\n', def.inlet);
                        case 'DesignSpec'
                            fprintf(fid, 'fs.addUnit(proc.units.DesignSpec(%s, ''%s'', %.6g, %d));\n', ...
                                def.stream, def.metric, def.target, def.componentIndex);
                        case 'Calculator'
                            fprintf(fid, 'fs.addUnit(proc.units.Calculator(%s, ''%s'', %s, ''%s'', ''%s'', %s, ''%s''));\n', ...
                                def.lhsStream, def.lhsField, def.aStream, def.aField, def.operator, def.bStream, def.bField);
                        case 'Constraint'
                            fprintf(fid, 'fs.addUnit(proc.units.Constraint(%s, ''%s'', %.6g, %.6g));\n', ...
                                def.stream, def.field, def.value, def.index);
                        case 'Heater'
                            fprintf(fid, 'thermoLib = thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Tout'), args = [args, sprintf(', ''Tout'', %.6g', def.Tout)]; end
                            if isfield(def,'duty'), args = [args, sprintf(', ''duty'', %.6g', def.duty)]; end
                            if isfield(def,'dP'), args = [args, sprintf(', ''dP'', %.6g', def.dP)]; end
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Heater(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'Cooler'
                            fprintf(fid, 'thermoLib = thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Tout'), args = [args, sprintf(', ''Tout'', %.6g', def.Tout)]; end
                            if isfield(def,'duty'), args = [args, sprintf(', ''duty'', %.6g', def.duty)]; end
                            if isfield(def,'dP'), args = [args, sprintf(', ''dP'', %.6g', def.dP)]; end
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Cooler(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'HeatExchanger'
                            fprintf(fid, 'thermoLib = thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Th_out'), args = sprintf(', ''Th_out'', %.6g', def.Th_out); end
                            if isfield(def,'Tc_out'), args = sprintf(', ''Tc_out'', %.6g', def.Tc_out); end
                            if isfield(def,'duty'), args = sprintf(', ''duty'', %.6g', def.duty); end
                            fprintf(fid, 'fs.addUnit(proc.units.HeatExchanger(%s, %s, %s, %s, mix%s));\n', ...
                                def.hotInlet, def.hotOutlet, def.coldInlet, def.coldOutlet, args);
                        case 'Compressor'
                            fprintf(fid, 'thermoLib = thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            if isfield(def,'eta'), args = [args, sprintf(', ''eta'', %.6g', def.eta)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Compressor(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
                        case 'Turbine'
                            fprintf(fid, 'thermoLib = thermo.ThermoLibrary();\n');
                            fprintf(fid, 'mix = thermo.IdealGasMixture(species, thermoLib);\n');
                            args = '';
                            if isfield(def,'Pout'), args = [args, sprintf(', ''Pout'', %.6g', def.Pout)]; end
                            if isfield(def,'PR'), args = [args, sprintf(', ''PR'', %.6g', def.PR)]; end
                            if isfield(def,'eta'), args = [args, sprintf(', ''eta'', %.6g', def.eta)]; end
                            fprintf(fid, 'fs.addUnit(proc.units.Turbine(%s, %s, mix%s));\n', def.inlet, def.outlet, args);
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
        function [resolvedDefs, aliasByOutlet] = resolveIdentityLinks(app, unitDefs)
            aliasByOutlet = containers.Map('KeyType','char','ValueType','char');
            resolvedDefs = cell(size(unitDefs));
            for i = 1:numel(unitDefs)
                def = unitDefs{i};
                if ~isstruct(def)
                    resolvedDefs{i} = def;
                    continue;
                end
                def = app.rewriteDefStreams(def, aliasByOutlet);
                if strcmp(def.type, 'Link') && app.isIdentityLinkDef(def)
                    inletRoot = app.resolveAliasName(def.inlet, aliasByOutlet);
                    aliasByOutlet(char(def.outlet)) = inletRoot;
                    continue;
                end
                resolvedDefs{i} = def;
            end
            resolvedDefs = resolvedDefs(~cellfun(@isempty, resolvedDefs));
        end

        function def = rewriteDefStreams(app, def, aliasByOutlet)
            fnSingles = {'inlet','source','stream','tear','processInlet','bypassStream','processReturn', ...
                'lhsStream','aStream','bStream','recycle','purge','outlet','outletA','outletB', ...
                'hotInlet','hotOutlet','coldInlet','coldOutlet'};
            for i = 1:numel(fnSingles)
                f = fnSingles{i};
                if ~isfield(def, f)
                    continue;
                end
                if strcmp(f, 'outlet') && strcmp(def.type, 'Link') && app.isIdentityLinkDef(def)
                    continue;
                end
                def.(f) = app.resolveAliasName(def.(f), aliasByOutlet);
            end
            if isfield(def, 'inlets')
                for k = 1:numel(def.inlets)
                    def.inlets{k} = app.resolveAliasName(def.inlets{k}, aliasByOutlet);
                end
            end
            if isfield(def, 'outlets')
                for k = 1:numel(def.outlets)
                    def.outlets{k} = app.resolveAliasName(def.outlets{k}, aliasByOutlet);
                end
            end
        end

        function addStreamAliasesToFlowsheet(app, fs, aliasByOutlet)
            if isempty(aliasByOutlet)
                return;
            end
            keys = aliasByOutlet.keys;
            for i = 1:numel(keys)
                aliasName = keys{i};
                targetName = aliasByOutlet(aliasName);
                s = app.findStream(targetName);
                if ~isempty(s)
                    fs.addAlias(aliasName, s);
                end
            end
        end

        function tf = isIdentityLinkDef(~, def)
            tf = strcmp(def.type, 'Link') && ~(isfield(def, 'mode') && ~strcmp(def.mode, 'identity'));
            if isfield(def, 'isIdentity')
                tf = logical(def.isIdentity);
            end
        end

        function outName = resolveAliasName(~, name, aliasByOutlet)
            outName = char(string(name));
            visited = containers.Map('KeyType','char','ValueType','logical');
            while isKey(aliasByOutlet, outName)
                if isKey(visited, outName)
                    break;
                end
                visited(outName) = true;
                outName = aliasByOutlet(outName);
            end
        end

        function mix = buildThermoMixForGUI(app)
            % Build an IdealGasMixture from the current species list.
            % Returns [] if any species is missing from the thermo library.
            try
                lib = thermo.ThermoLibrary();
                mix = thermo.IdealGasMixture(app.speciesNames, lib);
            catch
                mix = [];
            end
        end

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

        function cfg = buildValidatedConfigPayload(app)
            cfg = struct();
            cfg.speciesNames = app.speciesNames;
            cfg.speciesMW    = app.speciesMW;

            % Serialize streams
            N = numel(app.streams);
            if N == 0
                streamData = struct('name', {}, 'n_dot', {}, 'T', {}, 'P', {}, 'y', {}, ...
                    'known_n_dot', {}, 'known_T', {}, 'known_P', {}, 'known_y', {});
            else
                streamData = repmat(struct('name', '', 'n_dot', NaN, 'T', NaN, 'P', NaN, 'y', [], ...
                    'known_n_dot', false, 'known_T', false, 'known_P', false, 'known_y', false), 1, N);
            end
            for i = 1:N
                s = app.streams{i};
                sd = struct();
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
            cfg.unitPrefs = app.unitPrefs;

            app.validateConfigPayload(cfg);
        end

        function validateConfigPayload(~, cfg)
            requiredTop = {'speciesNames','speciesMW','streams','unitDefs','maxIter','tolAbs','projectTitle','unitPrefs'};
            for i = 1:numel(requiredTop)
                key = requiredTop{i};
                if ~isfield(cfg, key)
                    error('MathLab:SaveConfig:MissingField', 'Config payload missing required field "%s".', key);
                end
            end

            if ~iscell(cfg.speciesNames) || isempty(cfg.speciesNames)
                error('MathLab:SaveConfig:InvalidSpecies', 'speciesNames must be a non-empty cell array.');
            end
            if ~isnumeric(cfg.speciesMW) || numel(cfg.speciesMW) ~= numel(cfg.speciesNames)
                error('MathLab:SaveConfig:InvalidSpecies', 'speciesMW must be numeric and match speciesNames length.');
            end

            if ~isstruct(cfg.streams)
                error('MathLab:SaveConfig:InvalidStreams', 'streams must be a struct array.');
            end
            streamRequired = {'name','n_dot','T','P','y','known_n_dot','known_T','known_P','known_y'};
            for i = 1:numel(cfg.streams)
                for k = 1:numel(streamRequired)
                    f = streamRequired{k};
                    if ~isfield(cfg.streams(i), f)
                        error('MathLab:SaveConfig:InvalidStreams', ...
                            'Stream %d missing required field "%s".', i, f);
                    end
                end
            end

            if ~iscell(cfg.unitDefs)
                error('MathLab:SaveConfig:InvalidUnits', 'unitDefs must be a cell array.');
            end
            if any(~cellfun(@isstruct, cfg.unitDefs))
                error('MathLab:SaveConfig:InvalidUnits', 'unitDefs entries must be structs.');
            end

            if ~isscalar(cfg.maxIter) || ~isfinite(cfg.maxIter) || cfg.maxIter <= 0
                error('MathLab:SaveConfig:InvalidSolver', 'maxIter must be a finite positive scalar.');
            end
            if ~isscalar(cfg.tolAbs) || ~isfinite(cfg.tolAbs) || cfg.tolAbs <= 0
                error('MathLab:SaveConfig:InvalidSolver', 'tolAbs must be a finite positive scalar.');
            end

            if ~isstruct(cfg.unitPrefs)
                error('MathLab:SaveConfig:InvalidUnits', 'unitPrefs must be a struct.');
            end
        end

        function ensureWritableDir(~, dirPath)
            if ~(ischar(dirPath) || isstring(dirPath)) || strlength(string(dirPath)) == 0
                error('MathLab:SaveConfig:InvalidPath', 'Output directory path must be a non-empty string.');
            end
            dirPath = char(string(dirPath));
            if ~exist(dirPath, 'dir')
                [ok,msg] = mkdir(dirPath);
                if ~ok
                    error('MathLab:SaveConfig:CreateDirFailed', ...
                        'Could not create output directory "%s": %s', dirPath, msg);
                end
            end
            if ~isfolder(dirPath)
                error('MathLab:SaveConfig:InvalidPath', 'Output directory path is not a folder: %s', dirPath);
            end
            [fid,msg] = fopen(fullfile(dirPath, '.mathlab_write_test.tmp'), 'w');
            if fid < 0
                error('MathLab:SaveConfig:WritePermission', ...
                    'Directory is not writable "%s": %s', dirPath, msg);
            end
            fclose(fid);
            delete(fullfile(dirPath, '.mathlab_write_test.tmp'));
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
            if ~exist(baseDir, 'dir')
                [ok,msg] = mkdir(baseDir);
                if ~ok
                    error('MathLab:OutputDir:CreateFailed', ...
                        'Failed to create output directory "%s": %s', baseDir, msg);
                end
            end
            dirPath = fullfile(baseDir, subfolder);
            if ~exist(dirPath, 'dir')
                [ok,msg] = mkdir(dirPath);
                if ~ok
                    error('MathLab:OutputDir:CreateFailed', ...
                        'Failed to create output subdirectory "%s": %s', dirPath, msg);
                end
            end
            if ~isfolder(dirPath)
                error('MathLab:OutputDir:InvalidPath', 'Output path is not a directory: %s', dirPath);
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

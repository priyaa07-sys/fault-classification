%% generate_line910_data.m
% FIXED: Generate fault data for Line 9-10 using CORRECT variable names
% Uses: Fault_VI_data1 (Line 9-10 measurement) and Fault_VI_data (Line 1-2)

clc; clear; close all;
disp('Generating Fault Data for Line 9-10...');

%% --- 1. MODEL CONFIGURATION ---
model_name = 'Fourteen_bus1_ff';
load_system(model_name);

fixed_step_size = 5.0E-5;
set_param(model_name, 'SolverType', 'Fixed-step', 'FixedStep', num2str(fixed_step_size));
set_param(model_name, 'StopTime', '0.12');
samples_per_cycle = 400;

%% --- 2. LINE 9-10 CONFIGURATION ---
% CORRECTED: Using actual block names from your model
fault_blk = [model_name '/Three-Phase Fault3'];  % Line 9-10 fault block
block1 = [model_name '/Branch9'];   % RLC branch on Bus 9 side
block2 = [model_name '/Branch10'];  % RLC branch on Bus 10 side

% Line 9-10 impedance parameters (from IEEE 14-bus data)
% UPDATE these if needed based on your actual line data
R_total = 0.03181;   % ohms
L_total = 0.0845 / (2*pi*50);  % H (from X value)

%% --- 3. DISABLE ALL OTHER FAULT BLOCKS ---
disp('Disabling all other fault blocks...');
all_fault_blocks = {
    [model_name '/Three-Phase Fault'],   % Line 1-2
    [model_name '/Three-Phase Fault1'],  % Some other line
    [model_name '/Three-Phase Fault2'],  % Some other line
};
for i = 1:length(all_fault_blocks)
    try
        set_param(all_fault_blocks{i}, 'FaultA', 'off', 'FaultB', 'off', ...
                  'FaultC', 'off', 'GroundFault', 'off', 'SwitchTimes', '[1000 1001]');
    catch
    end
end

%% --- 4. FAULT CONFIGURATION ---
all_types = {'AG','BG','CG','AB','BC','AC','ABG','BCG','ACG','ABC','ABCG'};

% Adjust these for dataset size
fault_locations = 0.1:0.1:0.9;  % 9 locations
fault_resistances = [0.1, 1, 5, 10, 25, 50, 100];  % 7 resistances
total_normal = 50;  % Normal samples

total_samples = length(all_types) * length(fault_locations) * length(fault_resistances) + total_normal;
num_features = samples_per_cycle * 12;  % 12 channels

dataset_X = zeros(total_samples, num_features);
dataset_Y = zeros(total_samples, 3);
row_counter = 1;

disp(['Total samples to generate: ' num2str(total_samples)]);

%% --- 5. GENERATE FAULT DATA ---
for t = 1:length(all_types)
    current_type = all_types{t};
    
    % Assign Class ID
    if ismember(current_type, {'AG','BG','CG'}), class_id = 1;      % SLG
    elseif ismember(current_type, {'AB','BC','AC'}), class_id = 2;  % LL
    elseif ismember(current_type, {'ABG','BCG','ACG'}), class_id = 3; % DLG
    elseif ismember(current_type, {'ABC','ABCG'}), class_id = 4;    % 3P
    else, class_id = 0; end
    
    % Configure fault type
    vA='off'; vB='off'; vC='off'; vG='off';
    if contains(current_type, 'A'), vA='on'; end
    if contains(current_type, 'B'), vB='on'; end
    if contains(current_type, 'C'), vC='on'; end
    if contains(current_type, 'G'), vG='on'; end
    
    set_param(fault_blk, 'FaultA', vA, 'FaultB', vB, 'FaultC', vC, 'GroundFault', vG);
    
    for loc = fault_locations
        % Set fault location by splitting line impedance
        set_param(block1, 'Resistance', num2str(R_total * loc), 'Inductance', num2str(L_total * loc));
        set_param(block2, 'Resistance', num2str(R_total * (1-loc)), 'Inductance', num2str(L_total * (1-loc)));
        
        for res = fault_resistances
            try
                set_param(fault_blk, 'FaultResistance', num2str(res));
                set_param(fault_blk, 'SwitchTimes', '[0.05 0.1]');
                
                sim(model_name);
                
                % CORRECTED: Use the ACTUAL variable names from your model!
                % Fault_VI_data = Line 1-2 measurement (Bus 1 side reference)
                % Fault_VI_data1 = Line 9-10 measurement (where fault is!)
                d1 = Fault_VI_data;    % Line 1-2 (reference)
                d2 = Fault_VI_data1;   % Line 9-10 (fault location)
                
                % Handle data format
                if size(d2, 2) == 7  % Has time column
                    idx_start = find(d2(:,1) >= 0.05, 1) + 1;
                else
                    idx_start = round(0.05 / fixed_step_size) + 1;
                end
                range = idx_start : idx_start + samples_per_cycle - 1;
                if max(range) > size(d2,1), range = 1:samples_per_cycle; end
                
                if size(d2, 2) == 7
                    v1 = d1(range, 2:4); i1 = d1(range, 5:7);
                    v2 = d2(range, 2:4); i2 = d2(range, 5:7);
                else
                    v1 = d1(range, 1:3); i1 = d1(range, 4:6);
                    v2 = d2(range, 1:3); i2 = d2(range, 4:6);
                end
                
                % Flatten to single row [V1 I1 V2 I2] = 12 channels x 400 samples
                dataset_X(row_counter, :) = [reshape(v1,1,[]) reshape(i1,1,[]) reshape(v2,1,[]) reshape(i2,1,[])];
                dataset_Y(row_counter, :) = [class_id, loc, res];
                row_counter = row_counter + 1;
                
            catch ME
                fprintf('    Error: %s\n', ME.message);
            end
            
            % Reset fault and clear memory
            set_param(fault_blk, 'SwitchTimes', '[1000 1001]');
            Simulink.sdi.clear;
            evalin('base', 'clear Fault_VI_data Fault_VI_data1');
        end
    end
    fprintf('  %s done: %d samples\n', current_type, row_counter-1);
end

%% --- 6. GENERATE NORMAL DATA ---
disp('Generating Normal samples...');
set_param(fault_blk, 'FaultA', 'off', 'FaultB', 'off', 'FaultC', 'off', 'GroundFault', 'off');
set_param(fault_blk, 'SwitchTimes', '[1000 1001]');

for n = 1:total_normal
    try
        sim(model_name);
        
        d1 = Fault_VI_data;
        d2 = Fault_VI_data1;
        
        if size(d2, 2) == 7
            idx_start = find(d2(:,1) >= 0.05, 1) + 1;
            range = idx_start : idx_start + samples_per_cycle - 1;
            v1 = d1(range, 2:4); i1 = d1(range, 5:7);
            v2 = d2(range, 2:4); i2 = d2(range, 5:7);
        else
            idx_start = round(0.05 / fixed_step_size) + 1;
            range = idx_start : idx_start + samples_per_cycle - 1;
            if max(range) > size(d2,1), range = 1:samples_per_cycle; end
            v1 = d1(range, 1:3); i1 = d1(range, 4:6);
            v2 = d2(range, 1:3); i2 = d2(range, 4:6);
        end
        
        dataset_X(row_counter, :) = [reshape(v1,1,[]) reshape(i1,1,[]) reshape(v2,1,[]) reshape(i2,1,[])];
        dataset_Y(row_counter, :) = [0, 0, 0];  % Class 0 = Normal
        row_counter = row_counter + 1;
        
        Simulink.sdi.clear;
        evalin('base', 'clear Fault_VI_data Fault_VI_data1');
    catch ME
        fprintf('  Error: %s\n', ME.message);
    end
end

%% --- 7. SAVE AND VERIFY ---
dataset_X = dataset_X(1:row_counter-1, :);
dataset_Y = dataset_Y(1:row_counter-1, :);

writematrix(dataset_X, 'Line910_Fault_Data_X.csv');
writematrix(dataset_Y, 'Line910_Fault_Labels_Y.csv');

fprintf('\n========================================\n');
fprintf('SUCCESS! Generated %d samples from Line 9-10.\n', row_counter-1);
fprintf('========================================\n');
fprintf('Class distribution:\n');
for c = 0:4
    count = sum(dataset_Y(:,1) == c);
    fprintf('  Class %d: %d samples\n', c, count);
end

% Data quality check
fprintf('\nData Quality Check:\n');
fprintf('  Max voltage (V1): %.2f V\n', max(abs(dataset_X(:, 1:1200)), [], 'all'));
fprintf('  Max current (I1): %.4f A\n', max(abs(dataset_X(:, 1201:2400)), [], 'all'));
fprintf('  Max voltage (V2): %.2f V\n', max(abs(dataset_X(:, 2401:3600)), [], 'all'));
fprintf('  Max current (I2): %.2f A\n', max(abs(dataset_X(:, 3601:4800)), [], 'all'));

% Check if fault current is captured
i2_max = max(abs(dataset_X(:, 3601:4800)), [], 'all');
if i2_max > 100
    disp('✅ Line 9-10 fault current captured successfully!');
else
    disp('⚠️  Current seems low - verify measurement placement');
end

fprintf('\nFiles saved:\n');
fprintf('  - Line910_Fault_Data_X.csv\n');
fprintf('  - Line910_Fault_Labels_Y.csv\n');

function [ tau1_map , tau2_map , r2_map , mask ] = NormalFitProcess( image , roi , scantimes , last_pfp )
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here

%% Start Timer
fprintf('\nBeginning F19 Processing.'); timeStart = tic;

%% Define Derived Variables
nrows     = size(image, 1);         % number of rows in image
ncols     = size(image, 2);         % number of cols in image
nslices   = size(image, 3);         % number of slices in image
nscans    = size(image, 4);         % number of scans in time
nel       = nrows*ncols*nslices;    % number of elements in image

%% Find mean pixel values in ROI
[ means , mask ] = ComputePixelAverageIn3DROI( image, roi );

%% Fitting of ROI volume
[ f4 ] = ROIVentilationFit( last_pfp , means , scantimes , nscans );
%PlotF19Fit(f4 , scantimes, means) % plot the fit resutls

%% Get vector of each voxel signal intensity over time within whole lung ROI
[ masked_all ] = maskcellimages( mask, image, nrows, ncols, nslices, nscans );

%% Find peak wash-in and time to peak wash-in for each voxel
[ vvec2 ] = voxel_vector( masked_all , nrows , ncols , nslices , nel , nscans );

%% Computing Max Wash in Times
[ max_map , time2max_map , time2max_mapTimes ] = max_washin_time( vvec2, nrows, ncols, nslices, nel, image, scantimes, 1, nscans, last_pfp, last_pfp, mask );

 %% choose one method, and apply to each voxel
[ d0_map , df_map , tau1_map , tau2_map , t0_map , t1_map, r2_map ] = ffitmaps( nrows, ncols, nslices, nscans, nel, time2max_map, time2max_mapTimes, vvec2, scantimes, f4 );

%% Stop Timer
fprintf('\nFinished F19 Processing.\nTotal Time %0.1f Minutes.',toc(timeStart)/60)

end

function [ Means , Mask ] = ComputePixelAverageIn3DROI( Image, ROI )
%ComputePixelAverageInROI finds the mean signal intensity value in an image
%within an inputted ROI

% Image is a 4D image (rows x columns x slices x time)
% ROI is a 3D segmentation mask (rows x columns x slices)
% Means is a 1D array (length = number of slices) with mean pixel value of Image in ROI for each slice

%% Start timer
fprintf('\nFinding mean pixel value for ROI at each time point...'); tStart = tic;

%% Get dimensions of image volume in 3D (rows x cols x slices)
nrows     = size(Image, 1); % number of rows in image
ncols     = size(Image, 2); % number of cols in image
nscans    = size(Image, 4); % number of scans in time

%% Resize ROI to match image
Mask = imresize(ROI,[nrows,ncols]);

%% Compute mean of ROI at each time point
Means = zeros(nscans,1);

for i = 1:nscans
    Segmented = Image(:,:,:,i).*Mask; % select only image values within mask
    Values    = Segmented(:); % put image into 1d array
    Means(i)  = sum(Values)./sum(Values~=0); % find mean of all nonzero values
end

%% End timer
fprintf('done (%0.1f Seconds)',toc(tStart))

end

function [ f4 ] = ROIVentilationFit(  last_pfp, means, ScanTimes, nscans )
%WHOLE_LUNG_FIT ouputs the fit of the mean intesity value of whole lung
%ROI vs. time

%   The fit is calculated using the method
%   outlined in "Simon BA, Marcucci C, Fung M, Lele SR (1998) Parameter 
%   estimation and confidence intervals for Xe-CT ventilation studies: 
%   a Monte Carlo approach. J Appl Physiol 84:709�716".

%% Start Timer
fprintf('\nComputing fit for averaged ROI...'); tStart = tic;

%% Compute Fit
avt = ScanTimes(last_pfp); % switch point

fullfit = fittype('(x>=t0 & x<=t1)*[d0 + (df-d0)*[1-exp(-(x-t0)/tau1)]] + (x>=t1)*[d0 + (df-d0)*[1-exp(-(t1-t0)/tau2)]*[exp(-(x-t1)/tau2)]] ', ... 
    'dependent', {'y'}, 'independent', {'x'}, ...
    'coefficients', {'d0', 'df', 'tau1', 'tau2', 't0', 't1'});

f4 = fit(ScanTimes(2:nscans), means(2:nscans), fullfit,'Robust', 'off','Algorithm', 'Levenberg-Marquardt',...
    'Startpoint', [10, 50, 100, 100, 0, avt]);
%     'Lower', [0,             max(means) - 30,  1,   1,   et_vector(2, 1) - 45, avt - 45],... %NEED TO DEFINE REASONABLE LIMITS FOR ALL COEEFFICIENTS EXCEPT TAU
%     'Upper', [min(means)+30, max(means) + 30,  500, 500, et_vector(2, 1) + 45, avt + 45],...

%% Stop Timer
fprintf('done (%0.1f Seconds)',toc(tStart))

end

function [ masked_all ] = maskcellimages( mask, image, nrow, ncol, nslice, nscans )
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here

%% Start Timer
fprintf('\nGetting voxel vectors over time...'); tStart = tic;

%% Function Code
j = 1;

masked_all = cell(nrow, ncol, nslice, nscans);
for i = 1 : nscans
    um = image(:,:,:,i);
    masked = um .* mask;
    masked_all{j}(:, :, :) = masked;
    j = j + 1;
end

%% End Timer
fprintf('done (%0.1f Seconds)',toc(tStart))

end

function [ vvec ] = voxel_vector( all_scan, nrows , ncols , nslices , nel , nscans )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

%% Start Timer
fprintf('\nComputing peak wash-in fit for each voxel...'); tStart = tic;

%% Function Code

i = 1;%row
j = 1;%col
% k = 1;%slice
n = 1;
% p = 1;

vvec = ones(nel, nscans);

while n  <= nel%voxel
    for k = 1:nslices
%         k = p;
        while i <= nrows
            while j <= ncols
                for m = 1:nscans%scan
                    vvec(n,m) = all_scan{m}(i,j,k); % can be changed from all to all_roi
%                     k = p+(m*nslice);
                end
%                 k = p;%slice
                j = j+1;
                n = n+1;
            end
            j = 1;%col
            i = i+1;
        end
        i = 1;%row 
    end
end

%% Stop Timer
fprintf('done (%0.1f Seconds)',toc(tStart))

end

function [ max_map, time2max_map, time2max_map_time ] = max_washin_time( vvec, nrow, ncol, nslice, nel, all, time, x, y, z, last_pfp, mask )
%UNTITLED3 Summary of this function goes here
%   Detailed explanation goes here

%% Start Timer
fprintf('\nComputing max wash in fit for each voxel...'); tStart = tic;

%% Function Code
% time = tot_elap_time;
[M,I] = max(vvec, [], 2);
for i = 1: nel
    I2(i,1) = time(I(i));
end

%% Send max and time of max to Map
max_map1 = ones(nrow,ncol,nslice); %Map of Maximum Value
tm_map = ones(nrow,ncol,nslice); %Map of Scan Number of Maximum Value
tm_map_time = ones(nrow,ncol,nslice); %Map of Scan Number of Maximum Value

count = 1;
while count <= nel
    for a = 1:nslice
        for b = 1:nrow
            for c = 1:ncol
                max_map1(b, c, a) = M(count);
                tm_map (b, c, a) = I(count);
                tm_map_time (b, c, a) = I2(count);
                count = count+1;
            end
        end
    end
end

%% Sum of all PFP acquisitions for masking purposes
i = last_pfp;
% sumtest = zeros(nrow,ncol,nslice);
% while i > 0
%     sumtest = sumtest + all{i};
%     i = i - 1;
% end
% mask = sumtest>thresh;


% mask = all{last_pfp}(:, :, :)>thresh; %former mask of single PFP
% acquisition

%% Masking time-to-maximum wash-in map
masked_tm_map = mask.*tm_map; 
time2max_map = masked_tm_map;

masked_tm_map_time = mask.*tm_map_time; 
time2max_map_time = masked_tm_map_time;

%% Masking maximum intensity per voxel map
max_map = mask.*max_map1;

%% Find mode of time-to-maximum wash-in map
find_mode = masked_tm_map(masked_tm_map>0);
avg_time2max = mode(find_mode);

find_mode2 = masked_tm_map_time(masked_tm_map_time>0);
avg_time2max_time = mode(find_mode2);

%% End Timer
fprintf('done (%0.1f Seconds)',toc(tStart))

end

function [ d0_map, df_map, tau1_map, tau2_map, t0_map, t1_map, r2_map ] = ffitmaps( nrow, ncol, nslice, nscans, nel, time2max_map, time2max_mapt, vvec2, et_vector, f4 )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

%% Start Timer
fprintf('\nComputing fit maps for images:'); tfitStart = tic;

%% Code for Function
fullfit = fittype('(x>=t0 & x<=t1)*[d0 + (df-d0)*[1-exp(-(x-t0)/tau1)]] + (x>=t1)*[d0 + (df-d0)*[1-exp(-(t1-t0)/tau2)]*[exp(-(x-t1)/tau2)]] ', ...
    'dependent', {'y'}, 'independent', {'x'}, ...
    'coefficients', {'d0', 'df', 'tau1', 'tau2', 't0', 't1'});

d0_map = ones(nrow,ncol,nslice);   %Map of d0
df_map = ones(nrow,ncol,nslice);   %Map of df
tau1_map = ones(nrow,ncol,nslice); %Map of tau1
tau2_map = ones(nrow,ncol,nslice); %Map of tau2
t0_map = ones(nrow,ncol,nslice);   %Map of t0
t1_map = ones(nrow,ncol,nslice);   %Map of t1
r2_map = ones(nrow,ncol,nslice);   %Map of r-squared

probe = zeros(nel,3);

count = 1;

while count <= nel
    
    for a = 1:nslice
        fprintf('\n   Computing Slice %i of %i...',a,nslice); tStart = tic; % starts timer
        for b = 1:nrow
            for c = 1:ncol
                probe(count, 1) = a;
                probe(count, 2) = b;
                probe(count, 3) = c;
                if max(vvec2(count, :))>0
                    
                    %mt1 = (.5*f4.tau1);
                    %mt2 = (.5*f4.tau2);
                    %lower_limits = [vvec2(count, 1) - 50, vvec2(count, time2max_map(b, c, a)) - 50, f4.tau1 - mt1, f4.tau2 - mt2, et_vector(2, 1) - 60, time2max_mapt(b, c, a) - 60];
                    %upper_limits = [vvec2(count, 1) + 50, vvec2(count, time2max_map(b, c, a)) + 50, f4.tau1 + mt1, f4.tau2 + mt2, et_vector(2, 1) + 60, time2max_mapt(b, c, a) + 60];
                    %lower_limits = [vvec2(count, 1) - 15, vvec2(count, time2max_map(b, c, a)) - 50, f4.tau1 - mt1, f4.tau2 - mt2, f4.t0 - 60, f4.t1 - 60];
                    %upper_limits = [vvec2(count, 1) + 15, vvec2(count, time2max_map(b, c, a)) + 50, f4.tau1 + mt1, f4.tau2 + mt2, f4.t0 + 60, f4.t1 + 60];
                    %start = [f4.d0, f4.df, f4.tau1, f4.tau2, f4.t0, f4.t1];
                    
                    % Experimental F19 Fit
                    mt1 = (.75*f4.tau1);
                    mt2 = (.75*f4.tau2);
                    lower_limits = [                   0,                                    10.01, f4.tau1 - mt1, f4.tau2 - mt2,           0, f4.t1 - 60];
                    upper_limits = [                  10, vvec2(count, time2max_map(b, c, a)) + 10, f4.tau1 + mt1, f4.tau2 + mt2, f4.t0 + 400, f4.t1 + 400];
                    start = [f4.d0, f4.df, f4.tau1, f4.tau2, f4.t0, f4.t1]; 
                    
                    [f_vvec , gof] = fit(et_vector(2: nscans), vvec2(count, 2:nscans).', fullfit,'Lower', lower_limits,... %LEFT OFF HERE!!!!
                        'Upper', upper_limits, 'Startpoint', start);              
                    
                    
                    %                     legend('off')
                    %                     plot(f_vvec, 'b-', et_vector, vvec2(count))
                    %                     hold on
                    %                     legend('off')
                    
                    
                    d0_map(b, c, a)    = f_vvec.d0;
                    df_map (b, c, a)   = f_vvec.df;
                    tau1_map(b, c, a)  = f_vvec.tau1;
                    tau2_map(b, c, a)  = f_vvec.tau2;
                    t0_map(b, c, a)    = f_vvec.t0; 
                    t1_map(b, c, a)    = f_vvec.t1;
                    r2_map(b, c, a)    = gof.rsquare;
                    
                else
                    d0_map(b, c, a)    = 0;
                    df_map (b, c, a)   = 0;
                    tau1_map(b, c, a)  = 0;
                    tau2_map(b, c, a)  = 0;
                    t0_map(b, c, a)    = 0;
                    t1_map(b, c, a)    = 0;
                    r2_map(b, c, a)    = 1;
                    
                end
                count = count + 1;
                
            end 
        end
        fprintf('done (%0.1f Seconds)',toc(tStart)) % print timing
    end
    
    
end

%% Stop Timer
fprintf('\nFit Maps Completed (total time: %0.1f Minutes)',toc(tfitStart)/60)

end


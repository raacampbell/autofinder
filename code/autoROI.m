function varargout=autoROI(pStack, varargin)
    % autoROI
    %
    % function varargout=autoROI(pStack, 'param',val, ... )
    % 
    % Purpose
    % Automatically detect regions in the current section where there is
    % sample and find a tile-based bounding box that surrounds it. This function
    % can also be fed a bounding box list in order to use these ROIs as a guide
    % for finding the next set of boxes in the next xection. This mimics the 
    % behavior under the microscope. 
    % See: autoROI.text.runOnStackStruct
    %
    % Return results in a structure.
    %
    % 
    % Inputs (Required)
    % pStack - The pStack structure. From this we extract key information such as pixel size.
    %
    % Inputs (Optional param/val pairs)
    % tThresh - Threshold for tissue/no tissue. By default this is auto-calculated
    % tThreshSD - Used to do the auto-calculation of tThresh.
    % doPlot - if true, display image and overlay boxes. false by default
    % doTiledRoi - if true (default) return the ROI we would have if tile scanning. 
    % lastSectionStats - By default the whole image is used. If this argument is 
    %               present it should be the output of autoROI from a
    %               previous section;
    % skipMergeNROIThresh - If more than this number of ROIs is found, do not attempt
    %                         to merge. Just return them. Used to speed up auto-finding.
    %                         By default this is infinity, so we always try to merge.
    % showBinaryImages - shows results from the binarization step
    % doBinaryExpansion - default from setings file. If true, run the expansion of 
    %                     binarized image routine. 
    % settings - the settings structure. If empty or missing, we read from the file itself
    %
    %
    % Outputs
    % stats - borders and so forth
    % binaryImageStats - detailed stats on the binary image step (see binarizeImage)
    % H - plot handles
    %
    %
    % Rob Campbell - SWC, 2019


    if ~isstruct(pStack)
        fprintf('%s - First input argument must be a structure.\n',mfilename)
        return
    end

    %TODO -- temp code until we overhaul all the pStacks
    if ~isfield(pStack,'sectionNumber')
        fprintf('%s - Creating sectionNumber field and setting to 1.\n',mfilename)
        pStack.sectionNumber=1;
    end

    % Extract the image we will work with
    im = pStack.imStack(:,:,pStack.sectionNumber);


    % Get size settings from pStack structure
    pixelSize = pStack.voxelSizeInMicrons;
    tileSize = pStack.tileSizeInMicrons;



    params = inputParser;
    params.CaseSensitive = false;

    params.addParameter('doPlot', true, @(x) islogical(x) || x==1 || x==0)
    params.addParameter('doTiledRoi', true, @(x) islogical(x) || x==1 || x==0)
    params.addParameter('tThresh',[], @(x) isnumeric(x) && isscalar(x))
    params.addParameter('tThreshSD',[], @(x) isnumeric(x) && isscalar(x) || isempty(x))
    params.addParameter('lastSectionStats',[], @(x) isstruct(x) || isempty(x))
    params.addParameter('skipMergeNROIThresh',inf, @(x) isnumeric(x) )
    params.addParameter('showBinaryImages', false, @(x) islogical(x) || x==1 || x==0)
    params.addParameter('doBinaryExpansion', [], @(x) islogical(x) || x==1 || x==0 || isempty(x))
    params.addParameter('settings',autoROI.readSettings, @(x) isstruct(x) )


    params.parse(varargin{:})
    doPlot = params.Results.doPlot;
    doTiledRoi=params.Results.doTiledRoi;
    tThresh = params.Results.tThresh;
    tThreshSD = params.Results.tThreshSD;
    lastSectionStats = params.Results.lastSectionStats;
    skipMergeNROIThresh = params.Results.skipMergeNROIThresh;
    showBinaryImages = params.Results.showBinaryImages;
    doBinaryExpansion = params.Results.doBinaryExpansion;
    settings = params.Results.settings;



    % Get defaults from settings file if needed
    if isempty(tThreshSD)
        fprintf('%s is using a default threshold of %0.2f\n',mfilename,tThreshSD)
        tThreshSD = settings.main.defaultThreshSD;
    end

    if isempty(doBinaryExpansion)
        doBinaryExpansion = settings.mainBin.doExpansion;
    end

    % Extract settings from setting structure
    borderPixSize = settings.main.borderPixSize;

    rescaleTo = settings.stackStr.rescaleTo;



    % These are the arguments we feed into the binarization function
    binArgs = {'doBinaryExpansion', doBinaryExpansion, ...
                'showImages',showBinaryImages, ...
                'settings',settings};

    if size(im,3)>1
        fprintf('%s requires a single image not a stack\n',mfilename)
        return
    end


    if rescaleTo>1
        fprintf('%s is rescaling image to %d mic/pix from %0.2f mic/pix\n', ...
            mfilename, rescaleTo, pixelSize);
        sizeIm=size(im);
        sizeIm = round( sizeIm / (rescaleTo/pixelSize) );
        im = imresize(im, sizeIm);
        origPixelSize = pixelSize;
        pixelSize = rescaleTo;
    else
        origPixelSize = pixelSize;
    end



    % Median filter the image first. This is necessary, otherwise downstream steps may not work.
    im = medfilt2(im,[settings.main.medFiltRawImage,settings.main.medFiltRawImage]);
    im = single(im);

    % If no threshold for segregating sample from background was supplied then calculate one
    % based on the pixels around the image border.
    if isempty(tThresh)
        %Find pixels within b pixels of the border
        b = borderPixSize;
        borderPix = [im(1:b,:), im(:,1:b)', im(end-b+1:end,:), im(:,end-b+1:end)'];
        borderPix = borderPix(:);
        tThresh = median(borderPix) + std(borderPix)*tThreshSD;
        fprintf('\n\nNo threshold provided to %s - USING IMAGE BORDER PIXELS to extract a threshold of %0.1f based on threshSD of %0.2f\n', ...
         mfilename, tThresh, tThreshSD)

    else
        fprintf('Running %s with provided threshold of %0.2f\n', mfilename, tThresh)
    end



    % Binarize, clean, add a border around the sample
    if nargout>1
       [BW,binStats] = autoROI.binarizeImage(im,pixelSize,tThresh,binArgs{:});
    else
        BW = autoROI.binarizeImage(im,pixelSize,tThresh,binArgs{:});
    end

    % We run on the whole image
    if showBinaryImages
        disp('Press return')
        pause
    end

    if isempty(lastSectionStats)
        stats = autoROI.getBoundingBoxes(BW,im,pixelSize);  % Find bounding boxes
        %stats = autoROI.growBoundingBoxIfSampleClipped(im,stats,pixelSize,tileSize);
        if length(stats) < skipMergeNROIThresh
            stats = autoROI.mergeOverlapping(stats,size(im)); % Merge partially overlapping ROIs
        end

    else
        % We have provided bounding box history from previous sections
        
        lastROI = lastSectionStats.roiStats(end);
        if rescaleTo>1
            lastROI.BoundingBoxes = ...
                cellfun(@(x) round(x/(rescaleTo/origPixelSize)), lastROI.BoundingBoxes,'UniformOutput',false);
        end

        % Run within each ROI then afterwards consolidate results
        nT=1;

        for ii = 1:length(lastROI.BoundingBoxes)
            % Scale down the bounding boxes

            fprintf('* Analysing ROI %d/%d for sub-ROIs\n', ii, length(lastROI.BoundingBoxes))
            % TODO -- we run binarization each time. Otherwise boundingboxes tha merge don't unmerge for some reason.
            %         see Issue 58. 
            tIm = autoROI.getSubImageUsingBoundingBox(im,lastROI.BoundingBoxes{ii},true); % Pull out just this sub-region
            %tBW = autoROI.getSubImageUsingBoundingBox(BW,lastSectionStats.roiStats.BoundingBoxes{ii},true); % Pull out just this sub-region
            tBW = autoROI.binarizeImage(tIm,pixelSize,tThresh,binArgs{:});
            tStats{ii} = autoROI.getBoundingBoxes(tBW,tIm,pixelSize);
            %tStats{ii}}= autoROI.growBoundingBoxIfSampleClipped(im,tStats{ii},pixelSize,tileSize);

            if ~isempty(tStats{ii})
                tStats{nT} = autoROI.mergeOverlapping(tStats{ii},size(tIm));
                nT=nT+1;
            end

        end

        if ~isempty(tStats{1})

            % Collate bounding boxes across sub-regions into one "stats" structure. 
            n=1;
            for ii = 1:length(tStats)
                for jj = 1:length(tStats{ii})
                    stats(n).BoundingBox = tStats{ii}(jj).BoundingBox; %collate into one structure
                    n=n+1;
                end
            end


            % Final merge. This is in case some sample ROIs are now so close together that
            % they ought to be merged. This would not have been possible to do until this point. 
            % TODO -- possibly we can do only the final merge?

            if length(stats) < skipMergeNROIThresh
                fprintf('* Doing final merge\n')
                stats = autoROI.mergeOverlapping(stats,size(im));
            end
        else
            % No bounding boxes found
            fprintf('autoROI found no bounding boxes\n')
            stats=[];
        end

    end

    % Deal with scenario where nothing was found
    if isempty(stats)
        fprintf(' ** Stats array is empty. %s is bailing out. **\n',mfilename)
        if nargout>0
            varargout{1}=[];
        end
        if nargout>1
            varargout{2}=[];
        end
        if nargout>2
            varargout{3}=im;
        end
        return

    end


    % We now expand the tight bounding boxes to larger ones that correspond to a tiled acquisition
    if doTiledRoi

        fprintf('\n -> Creating tiled bounding boxes\n');
        %Convert to a tiled ROI size 
        for ii=1:length(stats)
            stats(ii).BoundingBox = ...
            autoROI.boundingBoxToTiledBox(stats(ii).BoundingBox, ...
                pixelSize, tileSize);
        end

        if settings.main.doTiledMerge && length(stats) < skipMergeNROIThresh
            fprintf('* Doing merge of tiled bounding boxes\n')
            [stats,delta_n_ROI] = ...
                autoROI.mergeOverlapping(stats, size(im), ...
                    settings.main.tiledMergeThresh);
        else
            delta_n_ROI=0;
        end

    end % if doTiledRoi


    if doPlot
        clf
        H=autoROI.plotting.overlayBoundingBoxes(im,stats);
        title('Final boxes')
    else
        H=[];
    end



    % Get the forground and background pixels within each ROI. We will later
    % use this to calculate stats on all of those pixels. 
    BoundingBoxes = {stats.BoundingBox};
    for ii=1:length(BoundingBoxes)
        tIm = autoROI.getSubImageUsingBoundingBox(im,BoundingBoxes{ii});
        tBW = autoROI.getSubImageUsingBoundingBox(BW,BoundingBoxes{ii});
        imStats(ii) = autoROI.getForegroundBackgroundPixels(tIm,pixelSize,borderPixSize,tThresh,tBW);
    end

    % Calculate the number of pixels in the bounding boxes
    nBoundingBoxPixels = zeros(1,length(BoundingBoxes));
    for ii=1:length(BoundingBoxes)
        nBoundingBoxPixels(ii) = prod(BoundingBoxes{ii}(3:4));
    end


    % Make a fresh output structure if no last section stats were 
    % provided as an input argument
    n=pStack.sectionNumber;
    if isempty(lastSectionStats)
        out.origPixelSize = origPixelSize;
        out.rescaledPixelSize = rescaleTo;
        out.nSamples = pStack.nSamples;
        out.settings = settings;
    else
        out = lastSectionStats;
    end

    % Data from all processed sections goes here
    out.roiStats(n).BoundingBoxes = {stats.BoundingBox};
    out.roiStats(n).tThresh = tThresh;
    out.roiStats(n).tThreshSD = tThreshSD;

    % Get the foreground and background pixel stats from the ROIs (not the whole image)
    out.roiStats(n).medianBackground = median([imStats.backgroundPix]);
    out.roiStats(n).stdBackground = std([imStats.backgroundPix]);

    out.roiStats(n).medianForeground = median([imStats.foregroundPix]);
    out.roiStats(n).stdForeground = std([imStats.foregroundPix]);


    % Calculate area of background and foreground in sq mm from the above ROIs
    out.roiStats(n).backgroundSqMM = length([imStats.backgroundPix]) * (pixelSize*1E-3)^2;
    out.roiStats(n).foregroundSqMM = length([imStats.foregroundPix]) * (pixelSize*1E-3)^2;


    % Convert bounding box sizes to meaningful units and return those.
    out.roiStats(n).BoundingBoxSqMM = nBoundingBoxPixels * (pixelSize*1E-3)^2;
    out.roiStats(n).meanBoundingBoxSqMM = mean(out.roiStats(n).BoundingBoxSqMM);
    out.roiStats(n).totalBoundingBoxSqMM = sum(out.roiStats(n).BoundingBoxSqMM);

    % What proportion of the whole FOV is covered by the bounding boxes?
    % This number is only available in test datasets. In real acquisitions with the 
    % auto-finder we won't have this number. 
    out.roiStats(n).propImagedAreaCoveredByBoundingBox = sum(nBoundingBoxPixels) / prod(sizeIm);


    % Finally: return bounding boxes to original size
    % If we re-scaled then we need to put the bounding box coords back into the original size
    if rescaleTo>1
        out.roiStats(n).BoundingBoxes = ...
             cellfun(@(x) round(x*(rescaleTo/origPixelSize)), out.roiStats(n).BoundingBoxes,'UniformOutput',false);
    end



    % Optionally return coords of each box
    if nargout>0
        varargout{1}=out;
    end

    if nargout>1
        varargout{2}=binStats;
    end

    if nargout>2
        varargout{3}=H;
    end
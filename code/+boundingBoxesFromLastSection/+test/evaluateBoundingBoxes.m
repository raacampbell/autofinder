function out=evaluateBoundingBoxes(stats,pStack)
% Evaluate how well the bounding boxes capture the brain
%
%   function out=evaluateBoundingBoxes(stats)
%
% Purpose
% Report accuracy of brain finding. Shows images of failed sections
% if no outputs were requested. NOTE: evaluates based on the border
% defined in pStack.borders and not on the binarised image.
%
% Inputs
% The pStackLog file in test directory. The pStack is loaded automatically.
%
% Inputs (optional)
% pStack - if supplied optionally as a second input argument, the pStack
%          is not loaded from disk.
%
%
% Example
% testLog  = boundingBoxesFromLastSection.test.runOnStackStruct(testLog)
% boundingBoxesFromLastSection.test.evaluateBoundingBoxes(testLog)
%
% Outputs
% out - A string describing how well this sample registered. This
%       is so we can write text files for multiple sumples to summarize
%       the performance of the algorithm. 


% Look for pStack file to load
if nargin==1
    pStackFname = stats(1).stackFname;
    if ~exist(pStackFname,'file')
        out = sprintf('No pStack file found at %s\n', pStackFname);
        fprintf(out)
        return
    else
        fprintf('Loading stack file %s\n',pStackFname)
        load(pStackFname)
    end
end


nPlanesWithMissingBrain=0;

out = '';

BW = zeros(size(pStack.binarized,[1,2])); 
for ii=1:length(stats)

    %Empty image. We will fill with ones all regions where brain was found.
    tB = pStack.borders{1}{ii};
    for jj = 1:length(tB)
        f= sub2ind(size(BW),tB{jj}(:,1),tB{jj}(:,2));
        BW(f)=1;
    end
    BW = imfill(BW);

    for jj=1:length(stats(ii).BoundingBoxes)
        % All pixels that are within the bounding box should be zero
        bb=stats(ii).BoundingBoxes{jj};

        bb(bb<=0)=1; %In case boxes have origins outside of the image
        BW(bb(2):bb(2)+bb(4), bb(1):bb(1)+bb(3))=0;
    end

    % Any non-zero pixels indicate non-imaged sample areas
    nonImagedPixels = sum(BW,[1,2]);

    if nonImagedPixels>0
        nPlanesWithMissingBrain = nPlanesWithMissingBrain + 1;

        if nargout==0
            imagesc(pStack.imStack(:,:,ii));

            % Overlay the brain border
            hold on
            for jj=1:length(pStack.borders{1}{ii})
                tBorder = pStack.borders{1}{ii}{jj};
                plot(tBorder(:,2),tBorder(:,1), '--c')
                plot(tBorder(:,2),tBorder(:,1), ':g','LineWidth',1)
            end
            hold off

            % Overlay bounding boxes
            for jj=1:length(stats(ii).BoundingBoxes)
                bb=stats(ii).BoundingBoxes{jj};
                boundingBoxesFromLastSection.plotting.overlayBoundingBox(bb);
            end


            set(gcf,'Name',sprintf('%d/%d',ii,size(pStack.binarized,3)))
            caxis([0,300])
            drawnow
            pause
        end
        % How many pixels fell outside of the area?
        pixelsInATile = round(pStack.tileSizeInMicrons/pStack.voxelSizeInMicrons)^2;
        nonImagedTiles = nonImagedPixels/pixelsInATile;
        if nonImagedTiles>1
            warnStr = ' * ';
        elseif nonImagedTiles>2
            warnStr = ' ** ';
        elseif nonImagedTiles>3
            warnStr = ' *** ';
        else
            warnStr = '';
        end

        msg = sprintf('%sSection %03d/%03d, %d ROIs, %d non-imaged pixels; %0.3f tiles; %0.3f sq mm \n', ...
            warnStr, ...
            ii, ...
            size(pStack.binarized,3), ...
            length(stats(ii).BoundingBoxes), ...
            nonImagedPixels, ...
            nonImagedTiles, ...
            sqrt(nonImagedPixels) * pStack.voxelSizeInMicrons * 1E-3);

        fprintf(msg)
        out = [out,msg];

    end
    BW(:)=0; %Wipe the binary image
end

if nPlanesWithMissingBrain==0
    msg=sprintf('GOOD -- None of the %d evaluated sections have sample which is unimaged.\n', ...
        length(stats));
    fprintf(msg)
    out = [out,msg];
end

if length(stats)~=size(pStack.binarized,3)
    msg=sprintf('WARNING -- There are %d sections in the image stack but only %d were processed.\n', ...
        size(pStack.binarized,3), length(stats));
    fprintf(msg)
    out = [out,msg];
end


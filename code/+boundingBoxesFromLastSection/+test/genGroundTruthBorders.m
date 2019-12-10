function pStack = genGroundTruthBorders(pStack,threshSTD)
% Determines the ground truth pixels which contain brain for each slice 
%
% Purpose
% This function produces ground truth data indicating where the brain is. 
% This can then be used to assess how well the auto brain finder is going.
% The auto brain finder will use a different algorithm, as it can't see into
% the future, which is what this function does. 
% NOTE: the user must validate output of this manually. You may need to 
% do things like copy the border from one section to an adjacent one.
% By hook or by crook you should generate borders that look sensible and then
% save the results. 
%
%
% Inputs
% pStack is the output of stackToGroundTruth
% threshSTD can be left empty. Optional.
%
% Outputs
% pStack - Same as input structure but now with added results.



if nargin<2
    threshSTD=4;
end

fprintf('Generating ground truth\n')

pStack.binarized = zeros(size(pStack.imStack),'logical'); %pre-allocate

for ii=1:size(pStack.imStack,3)
    if mod(ii,5)==0
        fprintf('.')
    end
    im = medfilt2(pStack.imStack(:,:,ii),[5,5]);
    im = single(im);
    [pStack.binarized(:,:,ii), pStack.borders{1}{ii}] = findBrainInSection(im, pStack.voxelSizeInMicrons, pStack.nSamples,threshSTD);

end
fprintf('\n')



function [BW,L] = findBrainInSection(im, pixelSize, nSamples, threshSTD)

    % Find pixels within b pixels of a border
    b=7;
    borderPix = [im(1:b,:), im(:,1:b)', im(end-b+1:end,:), im(:,end-b+1:end)'];
    borderPix = borderPix(:);
    tThresh = mean(borderPix) + std(borderPix)*threshSTD;

    % Binarize
    BW = im>tThresh;
    BW = medfilt2(BW,[3,3]);

    % Remove crap using spatial filtering
    SE = strel('disk',round(50/pixelSize));
    BW = imerode(BW,SE);
    BW = imdilate(BW,SE);


    % Add a border around the brain
    %SE = strel('square',round(50/pixelSize));
    %BW = imdilate(BW,SE);

    %Look for objects at that occupy least a certain proportion of the image area
    minSize=0.0015;
    sizeThresh = prod(size(BW)) * (minSize / nSamples);

    [L,indexedBW]=bwboundaries(BW,'noholes');

    for ii=length(L):-1:1
        thisN = length(find(indexedBW == ii));
        if thisN < sizeThresh
            L(ii)=[]; % Delete small stuff
        end
    end

    BW = indexedBW>0;
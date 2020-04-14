# autofinder
Test of algorithm to image only a sample and not surrounding tissue using serial-section 2-photon imaging. 
We have over 150 acquisitions, many have multiple samples so in total there are over 300 samples. 
Almost all samples are rat or mouse brains.
Testing proceeds in phases:

* **Phase One** is brains that have few or no obvious problems for the auto-ROI and are 100% expected to work without unusual user intervention.

* **Phase Two** Are samples which are particularly awkward but we would like to get working before moving on to implementing this in BakingTray. Once Phase Two is complete, we move to the BakingTray implementation. Phase Two includes cases where the  laser intensity changed during acquisition, spinal cord acquisitions, low SNR acquisitions. 

* **Phase Three** samples are those where user intervention of some sort is necessary. This includes acquisitions where one or more samples is not visible at all initially. It also includes acquisitions where the sample legitimately vanishes (e.g. PMT switched off due to user error, sample block unglued, etc). 

* **Deferred Samples** are those that we will worry about once everything above worked. e.g. this includes BS data with large numbers of duplicate tiles. Hopefully this can be fixed by Vidrio. 


# Generating pStack files
The command `boundingBoxesFromLastSection.test.runOnStackStruct(pStack)` calculates bounding boxes for 
a whole image stack. 
The input argument `pStack` is a structure which needs to be generated by the user. 
It's a good idea to generate these and store to disk in some reasonable way. 
e.g. Inside sub-directories divided up however makes sense, such as one directory containing all acquisitions of single samples, one with two samples, etc. 
To generate the pStack files do the following


We will work with imaging stacks (`imStack`, below) obtained from the BakingTray preview stacks. 

```
>> nSamples=2;
>> pStack = boundingBoxesFromLastSection.groundTruth.stackToGroundTruth(imStack,'/pathTo/recipeFile',nSamples)

pStack = 

  struct with fields:

               imStack: [1138x2826x192 int16]
                recipe: [1x1 struct]
    voxelSizeInMicrons: 8.1855
     tileSizeInMicrons: 1.0281e+03
              nSamples: 2
             binarized: []
               borders: {}

```

There are two empty fields (`binarized` and `borders`) in the `pStack` structure. 
These need to be populated with what we will treat as a proxy for ground truth: which regions actually contain brain.
This is necessary for subsequent evaluation steps but is not necessary to run the automatic tissue-finding code. 
This is done with:

```
pStack=boundingBoxesFromLastSection.groundTruth.genGroundTruthBorders(pStack,7)
```

And the results visualised with:
```
>> volView(pStack.imStack,[1,200],pStack.borders)  
```

Correct any issues you see by any means necessary. 

# Generating bounding boxes from a stack structure
```
>> OUT=boundingBoxesFromLastSection.test.runOnStackStruct(pStack)
```

Visualise it:
```
>> b={{OUT.BoundingBoxes},{},{}}
>> volView(pStack.imStack,[1,200],b)
```

# Evaluating results
First ensure you have run analyses on all samples. 
Run the test script on one directory:

```
>> boundingBoxesFromLastSection.test.runOnAllInDir('stacks/singleBrains')
```

You can optionally generate a text file that sumarises the results:
```
>> boundingBoxesFromLastSection.test.evaluateDir('tests/191211_1545')
```

To visualise the outcome of one sample:
```
>> load LIC_003_previewStack.mat 
>> load tests/191211_1545/log_LIC_003_previewStack.mat
>> b={{testLog.BoundingBoxes},{},{}};
>> volView(pStack.imStack,[1,200],b);
```

To run on all directories containing sample data within the stacks sub-directory do:
```
>> boundingBoxesFromLastSection.test.runOnAllInDir
```


## How it works
The general idea is that bounding boxes around sample(s) are found in the current section (`n`), expanded by about 200 microns, then applied to section `n+1`. 
When section `n+1` is imaged, the bounding boxes are re-calculated as before.
This approach takes into account the fact that the imaged area of most samples changes during the acquisition. 
Because the acquisition is tiled and we round up to the nearest tile, we usually end up with a border of more than 200 microns. 
In practice, this avoids clipping the sample in cases where it gets larger quickly as we section through it. 
There is likely no need to search for cases where sample edges are clipped in order to add tiles. 
We image rectangular bounding boxes rather than oddly shaped tile patterns because in most cases our tile size is large. 


### Implementation
`imStack` is a downsampled stack that originates from the preview images of a BakingTray serial section 2p acquisition. 
To calculate the bounding boxes for section 11 we would run:
```
boundingBoxesFromLastSection(imStack(:,:,10))
```

The function will return an image of section 10 with the bounding boxes drawn around it. 
It uses default values for a bunch of important parameters, such as pixel size.
Of course in reality these bounding boxes will need to be evaluated with respect to section 11. 
To perform this exploration we can run the algorithm on the whole stack.
To achieve this we load a "pStack" structure, as produced by `boundingBoxesFromLastSection.test.runOnStackStruct`, above. 
Then, as described above, we can run:
```
 boundingBoxesFromLastSection.test.runOnStackStruct(pStack)
```

How does `boundingBoxesFromLastSection` actually give us back the bounding boxes when run the first time (i.e. not in a loop over a stack)? 
It does the following:
* Median filter the stack with a 2D filter
* On the first section, derives a threshold between brain and no-brain by using the median plus a few SDs of the border pixels. 
We can do this because the border pixels will definitely contain no brain the first time around. 
* On the first section we now binarize the image using the above threshold and do some morphological filtering to tidy it up and to expand the border by 200 microns. This is done by the internal function `binarizeImage`. 
* This binarized image is now fed to the internal function `getBoundingBoxes`, which calls `regionProps` to return a bounding box. 
It also: removes very small boxes, provides a hackish fix for the missing corner tile, then sorts the bounding boxes in order of ascending size. 
* Next we use the external function `boundingBoxesFromLastSection.mergeOverlapping` to merge bounding boxes in cases where the is is appropriate. This function is currently problematic as it exhibits some odd behaviours that can cause very large overlaps between bounding boxes. 
* Finally, bounding boxes are expanded to the nearest whole tile and the merging is re-done. 


## Making summaries
`boundingBoxesFromLastSection.test.evaluateBoundingBoxes` works on a stats structure saved by 
`boundingBoxesFromLastSection.test.runOnAllInDir`. We can do the whole test directory with
`boundingBoxesFromLastSection.test.evaluateDir`. 

## Changelog

* v2 Does well with single brains and multiple brains where the individual brains have bounding boxes that are not going to overlap. 
Once bounding boxes overlap we begin to get odd and major failures. 
For instance, whole brains sudenly are excluded. 
An example of this is `threeBrains/AF_C2_2FPPVs_previewStack.mat` with `tThreshSD=4` -- irrespective of threshold we lose the bottom brain from section 17 to section 18. 
The problem lies with `mergeOverlapping`. 
The bounding boxes are correctly found but the merge step produces a bad result when applied to the tile-corrected output.
I believe it is losing a ROI when doing the merge comparisons because it's failing to correctly do comparisons with more than 2 ROIs.

* v3 Fixed issues relating to multiple sample ROIs. 
The main problems were that `mergeOverlapping` was deleteing ROIs and that the final bounding-box generation step had a tendency to merge ROIs that should not have been merged. 

* v4 Corrects the [issue with merge leading to imaging the same brain twice](https://github.com/raacampbell/autofinder/issues/14). 
I then ran the algorithm on all samples and looked at the results. We have the following failure modes that need addressing:
  - Ten acquisitions show mild to moderate failure to image the very posterior part of cortex when it appears. This is very severe in an additional three more: ~~HMV_NN01~~, ~~AL_029~~ and ~~AL023~~.
  - ~~One acquisition shows persistent issues finding all the brain: HMV_OIs04_OIs05. This is potentially serious since we don't know this happens.~~ Fixed 
  - One acquisition (AF_PCA_19_20_22_25) has a brain where we start imaging very caudal indeed. The spinal cord appears before cerebellum and it takes a few sections until cerebellum is imaged. Minor data loss.
  - ~~Two acquisitions show a thresholding issue where the brain is found in section 1 but subsequent ones are empty:~~ ~~AF_4C2s~~ and ~~AF_C2_2FPPVs~~. This would not lead to data loss, only annoyance. Fixed
  - ~~Two acquisitions suddenly fail to find the tissue mid way through acqisition~~: ~~C2vGvLG1~~ and ~~CC_125_1__125_2~~. This would not lead to data loss, only annoyance. Fixed
  - ~~Two acquisitions of 4 brains each lose one brain because it wasn't visible at the start of the acquisition. Not serious because we can solve this via user intervention before acquisition starts.~~ Phase 2 
  - ~~Two acquisitions fail due to sudden loss of the tissue for whatever reason: sample_972991_972992, FERRET~~. Not a problem with the algorithm. The microscope would just stop and send a Slack message. No data loss due to algorithm. Phase 2 
  - Other thresholding failures include: ~~LUNG_MACRO (bright tissue at edge?)~~ Basically fixed., ~~OI06_OI07 (very little brain found and it just gives up -- faint?)~~ Fixed.

* v5
  - Increasing the border from 100 to 300 microns helps a lot with the posterior cortex failure. Detailed examination pending, but it's positive.
  - The sudden unexpected failures were due to a bug that is now fixed.
  - One of the acquisitions which initially had no brain is now fine after the pixel change: a tiny bit of tissue was present and now crosses threshold. 
  
* v6
Generally pretty good performance. Increased the pool of acquisitions from 65 to about 114. Removed one sample where laser power was changed. The main thing to sort out now is [whether the evaluation is using the correct borders](https://github.com/raacampbell/autofinder/issues/35). 

* v7
Increase to 127 samples in main pool plus another 25 in the phase 2 pool, which we'll worry about later. That includes 7 where there was just one or more samples not visible at the start, 2 where the sample vanishes part way due to an acquisition problem, the eye, and 7 which simply have too many duplicate tiles due to BS with large number of averages.  
What we need to do right now is address the problem with [low SNR acquisitions](https://github.com/raacampbell/autofinder/issues/40).

* v8 and v8.5
Deal with lowSNR acquisitions and also enables the rolling threshold, which sorts out a few other problems. The main sticking point now is what to do with brains such as `SW_BY319_2_3_4`, which do badly beuse [the laser power was changed mid-way](https://github.com/raacampbell/autofinder/issues/33) through the acquisition. The rolling threshold does not cover this adquately as implemented. Working on the [occluded brain issue](https://github.com/raacampbell/autofinder/issues/33) might help the low laser power. In some ways they are related. 

* v9
The major change here is an algorithm to locate tiling in the binarised image and use this to indicate that the threshold is too low. This has fixed two cases of rat brains where the whole agar block is being imaged: the autothresh now correctly finds the brain in the block and doesn't draw a border around the agar. In the process of doing this, the four samples where we changed laser power a lot just magically work. So that's good. However, it turns out that one of the spinal cord samples balloons due to a large laser power increase. This is described in [Issue #50](https://github.com/raacampbell/autofinder/issues/50). To fix that, I think we need to first address [Issue #38](https://github.com/raacampbell/autofinder/issues/38), which is that for initially setting the `tThreshSD` based upon ROI edge pixels not FOV edge pixels. 

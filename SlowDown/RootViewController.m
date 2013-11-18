//
//  RootViewController.m
//  SlowDown
//

@import AssetsLibrary;
@import AVFoundation;

#import "RootViewController.h"
#import "FooterView.h"
#import "ViewController.h"

@interface RootViewController ()

@property (strong, nonatomic) IBOutlet UIView *backgroundView;
@property (strong, nonatomic) IBOutlet UILabel *centerLabel;
@property (weak, nonatomic) FooterView *footerView;

@property (strong, nonatomic) ALAssetsLibrary *assetsLibrary;
@property (strong, nonatomic) ALAssetsGroup *assetsGroup;
@property (strong, nonatomic) NSMutableArray *assets;
@property (strong, nonatomic) NSMutableArray *infoForAssets;

@end

@implementation RootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.collectionView.backgroundView = self.backgroundView;
    
    ALAuthorizationStatus status = [ALAssetsLibrary authorizationStatus];
    switch (status) {
        case ALAuthorizationStatusRestricted:
            _centerLabel.text = NSLocalizedString(@"This application is not authorized to access camera roll.", @"ALAuthorizationStatusRestricted");
            return;
        case ALAuthorizationStatusDenied:
            _centerLabel.text = NSLocalizedString(@"This application needs enable access to your camera roll.", @"ALAuthorizationStatusDenied");
            return;
        case ALAuthorizationStatusNotDetermined:
        case ALAuthorizationStatusAuthorized:
            _centerLabel.text = NSLocalizedString(@"No Videos", @"No Videos");
        default:
            break;
    }
    
    _assetsLibrary = [[ALAssetsLibrary alloc]init];
    
    _assets = [NSMutableArray array];
    _infoForAssets = [NSMutableArray array];

    ALAssetsLibraryGroupsEnumerationResultsBlock enumerationBlock = ^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            _assetsGroup = group;
            self.title = [_assetsGroup valueForProperty:ALAssetsGroupPropertyName];
            [_assetsGroup setAssetsFilter:[ALAssetsFilter allVideos]];
            [self loadAssets];
            *stop = YES;
        }
    };
    ALAssetsLibraryAccessFailureBlock failureBlock = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            if (error.code == ALAssetsLibraryAccessUserDeniedError) {
                _centerLabel.text = NSLocalizedString(@"Need enable access to your camera roll.", @"ALAuthorizationStatusDenied");
            } else {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[error description]
                                                                message:nil
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
            }
        });
    };
    [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:enumerationBlock failureBlock:failureBlock];

    [[NSNotificationCenter defaultCenter]addObserver:self
                                            selector:@selector(assetsLibraryDidChanged:)
                                                name:ALAssetsLibraryChangedNotification
                                              object:nil];
}

- (NSDictionary*)infoForAsset:(ALAsset*)asset;
{
    static id sharedKeySet = nil;
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *keys = @[@"duration", @"nominalFrameRate"];
        sharedKeySet = [NSDictionary sharedKeySetForKeys:keys];
        cache = [[NSCache alloc]init];
    });
    
    // assetのインスタンスは同じurlに対しても毎回変わるので、urlをキーにキャッシュする。
    NSMutableDictionary *info = [cache objectForKey:asset.defaultRepresentation.url];
    if (!info) {
        info = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
        
        AVAsset *avAsset = [AVURLAsset assetWithURL:asset.defaultRepresentation.url];
        Float64 seconds = roundf(CMTimeGetSeconds(avAsset.duration));
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
        static NSDateFormatter *formatter = nil;
        if (!formatter) {
            formatter = [[NSDateFormatter alloc]init];
            [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
        }
        if (seconds > 60*60) {
            [formatter setDateFormat:@"H:mm:ss"];
        } else {
            [formatter setDateFormat:@"m:ss"];
        }
        info[@"duration"] = [formatter stringFromDate:date];
        
        AVAssetTrack *track = [avAsset tracksWithMediaType:AVMediaTypeVideo][0];
        info[@"nominalFrameRate"] = @(track.nominalFrameRate);
        
        [cache setObject:info forKey:asset.defaultRepresentation.url];
    }
    return info;
}

- (void)loadAssets
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Manipulating views requires main thread.
        [_assets removeAllObjects];
        [_infoForAssets removeAllObjects];
        if ([_assetsGroup numberOfAssets]) {
            ALAssetsGroupEnumerationResultsBlock enumerationBlock = ^(ALAsset *asset, NSUInteger index, BOOL *stop) {
                if (asset) {
                    [_assets addObject:asset];
                    [_infoForAssets addObject:[self infoForAsset:asset]];
                }
            };
            [_assetsGroup enumerateAssetsWithOptions:0 usingBlock:enumerationBlock];
        }
        [self.collectionView reloadData];
        _footerView.countOfVideos = _assets.count;
        _backgroundView.hidden = (_assets.count != 0);
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"pushViewController"]) {
        NSArray *indexes = [self.collectionView indexPathsForSelectedItems];
        if (indexes.count > 0) {
            NSIndexPath *indexPath = indexes[0];
            ALAsset *asset = _assets[indexPath.row];
            ViewController* viewController = segue.destinationViewController;
            viewController.assetsLibrary = _assetsLibrary;
            viewController.alAsset = asset;
        }
    }
}

#pragma mark - ALAssetsLibraryChangedNotification

- (void)assetsLibraryDidChanged:(NSNotification*)note
{
    // If assetsGroup has been updated, reload it.
    NSArray *updatedAssetGroups = note.userInfo[ALAssetLibraryUpdatedAssetGroupsKey];
    if ([updatedAssetGroups containsObject:[_assetsGroup valueForProperty:ALAssetsGroupPropertyURL]]){
        [self loadAssets];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _assets.count;
}

#define kImageViewTag 1 // the image view inside the collection view cell prototype is tagged with "1"
#define kDurationTag 2
#define kIndicatorTag 3

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:CellIdentifier forIndexPath:indexPath];
    
    // load the asset for this cell
    ALAsset *asset = _assets[indexPath.row];
    CGImageRef thumbnailImageRef = [asset thumbnail];
    UIImage *thumbnail = [UIImage imageWithCGImage:thumbnailImageRef];
    
    // apply the image to the cell
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:kImageViewTag];
    imageView.image = thumbnail;
    
    NSDictionary *info = _infoForAssets[indexPath.row];
    // apply the duration
    UILabel *duration = (UILabel*)[cell viewWithTag:kDurationTag];
    duration.text = info[@"duration"];
    
    // apply indicator
    UIImageView *indicator = (UIImageView *)[cell viewWithTag:kIndicatorTag];
    if ([info[@"nominalFrameRate"]floatValue] > 108) {
        indicator.image = [UIImage imageNamed:@"indicatorHighSpeed"];
    } else {
        indicator.image = [UIImage imageNamed:@"indicatorNormal"];
    }
    return cell;
}

#define kFooterLabelTag 1   // the label inside the footer view prototype is tagged with "1"

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath;
{
    _footerView = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                     withReuseIdentifier:@"FooterView"
                                                            forIndexPath:indexPath];
    _footerView.countOfVideos = _assets.count;
    return _footerView;
}

@end

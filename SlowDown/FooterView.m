//
//  FooterView.m
//  SlowDown
//

#import "FooterView.h"

@interface FooterView ()

@property (strong, nonatomic) IBOutlet UILabel *label;

@end

@implementation FooterView

- (void)setCountOfVideos:(NSUInteger)countOfPhotos
{
    _countOfVideos = countOfPhotos;
    NSString *format = NSLocalizedString(@"%d Videos", @"Collection View footer shows number of videos.");
    dispatch_async(dispatch_get_main_queue(), ^{
        _label.text = [NSString stringWithFormat:format, _countOfVideos];
    });
}

#pragma mark - UICollectionReusableView

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes;
{
    [super applyLayoutAttributes:layoutAttributes];
    
    // If footer view is out of bounds, footer view will not be hidden.
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hidden = CGRectContainsPoint([[UIScreen mainScreen]bounds], layoutAttributes.center);
    });
}

@end

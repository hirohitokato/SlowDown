//
//  ViewController.h
//  SlowDown
//
//  Created by Hirohito Kato on 2013/10/17.
//  Copyright (c) 2013年 UntilTomorrow. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, CurrentStatus) {
    StatusNormal = 0,
    StatusPlaying,
    StatusExporting,
};

@interface ViewController : UIViewController

@property (nonatomic) ALAssetsLibrary *assetsLibrary;
@property (nonatomic) ALAsset *alAsset;

@end

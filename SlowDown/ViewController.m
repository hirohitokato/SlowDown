//
//  ViewController.m
//  SlowDown
//
//  Created by Hirohito Kato on 2013/10/17.
//  Copyright (c) 2013年 UntilTomorrow. All rights reserved.
//

@import MobileCoreServices;
@import AVFoundation;
@import AssetsLibrary;

#import "ViewController.h"
#import "PlayerView.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet PlayerView *playbackView;
@property (weak, nonatomic) IBOutlet UIProgressView *progressBar;

@property (weak, nonatomic) IBOutlet UIButton *chooseButton;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *exportButton;
@property (weak, nonatomic) IBOutlet UISlider *rateSlider;
@property (weak, nonatomic) IBOutlet UILabel *rateLabel;

@property (nonatomic) AVURLAsset *asset;
@property (nonatomic) AVAssetExportSession *exportSession;
@property (nonatomic) NSString *audioTimePitchAlgorithm;
@property (nonatomic) CurrentStatus status;
@property (nonatomic) id periodicObserver;
@end

@implementation ViewController

typedef NS_ENUM(NSInteger, ExportResult) {
    ExportResultSuccess = 0,
    ExportResultFailure,
    ExportResultCancelled,
};

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmVarispeed;

    __weak ViewController *weakSelf = self;

    // 再生が終わったら初期位置に戻す
    [[NSNotificationCenter defaultCenter]
     addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
     object:nil
     queue:[NSOperationQueue mainQueue]
     usingBlock:^(NSNotification *note) {
         [weakSelf.playbackView.player seekToTime:kCMTimeZero];
         weakSelf.progressBar.progress = 0.0f;
         weakSelf.status = StatusNormal;
     }];

    self.status = StatusNormal;
    
    if (self.alAsset) {
        [self buildSessionForMediaURL:self.alAsset.defaultRepresentation.url];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter]
     removeObserver:self];
    [self removeObserverForPlayer:self.playbackView.player];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - actions
- (IBAction)rateChanged:(UISlider*)sender {
    [self.playbackView.player pause];

    // 0.05おきにステップする
    float value = roundf(sender.value * 20) / 20.0f;
    [sender setValue:value animated:YES];
    NSString *text = [NSString stringWithFormat:@"x%.2f", sender.value];
    self.rateLabel.text = text;
}

- (IBAction)pickLatest:(id)sender {
    if (!_assetsLibrary) {
        _assetsLibrary = [[ALAssetsLibrary alloc]init];
    }
    [_assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        [group setAssetsFilter:[ALAssetsFilter allVideos]];
        NSInteger numberOfAssets = [group numberOfAssets];
        if (numberOfAssets > 0) {
            [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                if (result) {
                    NSURL *url = result.defaultRepresentation.url;
                    AVURLAsset *asset = [AVURLAsset assetWithURL:url];
                    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo][0];
                    if (!result.originalAsset && track.nominalFrameRate > 30) {
                        self.alAsset = result;
                        [self buildSessionForMediaURL:url];
                        *stop = YES;
                    }
                }
            }];
            *stop = YES;
        }
    } failureBlock:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[error description]
                                                            message:nil
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
            [alert show];
        });
    }];
}

- (IBAction)playOrPause:(id)sender {
    if (self.status == StatusNormal) {
        [self.playbackView.player setRate:self.rateSlider.value];
    } else if (self.status == StatusPlaying) {
        [self.playbackView.player pause];
    }
}

- (IBAction)export:(id)sender {
    // アセットからトラックを取得
    AVAssetTrack *videoAssetTrack = [self.asset tracksWithMediaType:AVMediaTypeVideo][0];
    AVAssetTrack *audioAssetTrack = [self.asset tracksWithMediaType:AVMediaTypeAudio][0];

    // 現在の再生レートを適用したコンポジションを作成
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *videoTrack =
    [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                             preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *audioTrack =
    [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                             preferredTrackID:kCMPersistentTrackID_Invalid];

    // アセットのトラックをコンポジション上に挿入し、再生レートを指定
    [videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, self.asset.duration)
                        ofTrack:videoAssetTrack
                         atTime:kCMTimeZero
                          error:nil];
    [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, self.asset.duration)
                        ofTrack:audioAssetTrack
                         atTime:kCMTimeZero
                          error:nil];
    CMTime newDuration = CMTimeMultiplyByFloat64(self.asset.duration,
                                                 1.0/self.rateSlider.value);
    [videoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, self.asset.duration)
                    toDuration:newDuration];
    [audioTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, self.asset.duration)
                    toDuration:newDuration];

    AVMutableVideoComposition *videoComposition = nil;
    // 最大120fpsとする
    CMTime outputFrameDuration = CMTimeMultiplyByFloat64(videoAssetTrack.minFrameDuration, 1.0/self.rateSlider.value);
    if (CMTimeCompare(outputFrameDuration, CMTimeMake(1, 120)) < 0) {
        outputFrameDuration = CMTimeMake(1, 120);
        // フレームレートを120fps上限とするためのインストラクション・ビデオコンポジション作成。
        // （不透明にしてオリエンテーションをオリジナルに合わせる）
        AVMutableVideoCompositionLayerInstruction *instruction =
        [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        [instruction setOpacity:1.0 atTime:kCMTimeZero];
        [instruction setTransform:videoAssetTrack.preferredTransform atTime:kCMTimeZero];
        AVMutableVideoCompositionInstruction *videoCompositionInstruction =
        [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        videoCompositionInstruction.layerInstructions = @[instruction];
        videoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, newDuration);
        
        videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.frameDuration = outputFrameDuration;
        
        // オリエンテーションを反映したレンダリングサイズを指定
        CGSize renderSize =CGSizeApplyAffineTransform([videoAssetTrack naturalSize],
                                                      videoAssetTrack.preferredTransform);
        renderSize.height = fabsf(renderSize.height); // @FIXME:なぜかマイナスに
        renderSize.width = fabsf(renderSize.width);   // @FIXME:なぜかマイナスに
        videoComposition.renderSize = renderSize;
        videoComposition.instructions = @[videoCompositionInstruction];
        
    } else {
        // オリエンテーションを設定
        // CGAffineTransformをコピー
        videoTrack.preferredTransform = videoAssetTrack.preferredTransform;
    }
    

    // エクスポートセッションを作成
    self.exportSession =
    [AVAssetExportSession exportSessionWithAsset:composition
                                      presetName:AVAssetExportPresetHighestQuality];
//                                      presetName:AVAssetExportPresetPassthrough]; // パススルーは音が使えない。
    self.exportSession.audioTimePitchAlgorithm = self.audioTimePitchAlgorithm;
    /* AVAudioTimePitchAlgorithmVarispeed  / ピッチ変わる
     * AVAudioTimePitchAlgorithmSpectral   / ピッチ維持、ノイズも増幅される
     * AVAudioTimePitchAlgorithmTimeDomain / ピッチ維持、ノイズも増幅される
     */

    NSString *filePath = NSTemporaryDirectory();
    filePath = [filePath stringByAppendingPathComponent:@"out.MOV"];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    self.exportSession.outputURL = [NSURL fileURLWithPath:filePath];
    self.exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    self.exportSession.metadata = self.asset.commonMetadata; // メタデータを継承

    self.exportSession.videoComposition = videoComposition;

    // エクスポート開始
    self.status = StatusExporting;
    __weak AVAssetExportSession *weakSession = self.exportSession;
    ALAsset *originalAsset = self.alAsset;
	[self.exportSession exportAsynchronouslyWithCompletionHandler:^{
        NSLog(@"エクスポート処理から戻りました。url:%@", weakSession.outputURL);

        if (weakSession.status == AVAssetExportSessionStatusCompleted) {
            // カメラロールへの書き込み。
            [originalAsset writeModifiedVideoAtPathToSavedPhotosAlbum:weakSession.outputURL
                                                      completionBlock:^(NSURL *assetURL,
                                                                        NSError *error) {
                                                          if (error) {
                                                              [self showAlertForResult:ExportResultFailure];
                                                          } else {
                                                              [self showAlertForResult:ExportResultSuccess];
                                                          }
                                                      }];
        } else if (weakSession.status == AVAssetExportSessionStatusCancelled) {
            [self showAlertForResult:ExportResultCancelled];
        } else {
            [self showAlertForResult:ExportResultFailure];
        }
        self.status = StatusNormal;
    }];

    // プログレスバーを非同期に更新
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        while (weakSession.status == AVAssetExportSessionStatusWaiting
               || weakSession.status == AVAssetExportSessionStatusExporting) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                self.progressBar.progress = weakSession.progress;
            });
        }
    });
}

#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"rate"]) {
        AVPlayer *player = (AVPlayer *)object;
        if (player.rate == 0.0) {
            // 停止中
            [self.playButton setTitle:@"Play" forState:UIControlStateNormal];
            self.status = StatusNormal;
        } else {
            // 再生中
            [self.playButton setTitle:@"Pause" forState:UIControlStateNormal];
            self.status = StatusPlaying;
        }
    }
}

- (void)addObserverForPlayer:(AVPlayer*)player;
{
    // ビデオの進み具合をプログレスバーに表示するよう登録
    __weak ViewController *weakSelf = self;
    self.periodicObserver = [player
                             addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.1,NSEC_PER_SEC)
                             queue:dispatch_get_main_queue()
                             usingBlock:^(CMTime time) {
                                 CMTime current = [weakSelf.playbackView.player currentTime];
                                 CMTime duration = [weakSelf.playbackView.player.currentItem duration];
                                 Float64 currentSec = CMTimeGetSeconds(current);
                                 Float64 total = CMTimeGetSeconds(duration);
                                 weakSelf.progressBar.progress = currentSec/total;
                             }];
    
    // 再生レート監視を登録
    [player addObserver:self
             forKeyPath:@"rate"
                options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld)
                context:NULL];
}

- (void)removeObserverForPlayer:(AVPlayer*)player;
{
    if (self.periodicObserver) {
        [player removeTimeObserver:self.periodicObserver];
        self.periodicObserver = nil;
    }
    [player removeObserver:self forKeyPath:@"rate"];
}

#pragma mark Editing a movie
- (void)buildSessionForMediaURL:(NSURL *)url
{
    self.asset = [AVURLAsset assetWithURL:url];
    if (!self.asset) return;

    // 再生用のセッティング
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:self.asset];
    item.audioTimePitchAlgorithm = self.audioTimePitchAlgorithm;

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    
    [self removeObserverForPlayer:self.playbackView.player];
    self.playbackView.player = player;
    [self addObserverForPlayer:self.playbackView.player];

    // スライダーをリセット
    AVAssetTrack *track = [self.asset tracksWithMediaType:AVMediaTypeVideo][0];
    float newValue = 30/track.nominalFrameRate;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.rateSlider.value = newValue;
        [self rateChanged:self.rateSlider];
    });
    self.status = StatusNormal;
}

#pragma mark - misc methods
- (void)setStatus:(CurrentStatus)status
{
    _status = status;
    [self updateUI];
}

- (void)updateUI
{
    self.playbackView.hidden = YES;
    self.progressBar.hidden = YES;
    self.chooseButton.enabled = NO;
    self.playButton.enabled = NO;
    self.exportButton.enabled = NO;
    self.rateLabel.enabled = NO;
    self.rateSlider.enabled = NO;

    switch (self.status) {
        case StatusNormal:
            self.chooseButton.enabled = YES;
            if (self.asset) {
                self.playbackView.hidden = NO;
                self.progressBar.hidden = NO;
                self.playButton.enabled = self.asset.isPlayable;
                self.exportButton.enabled = self.asset.isComposable;
                self.rateLabel.enabled = self.asset.isPlayable;
                self.rateSlider.enabled = self.asset.isPlayable;
            }
            break;
        case StatusPlaying:
            self.chooseButton.enabled = YES;
            if (self.asset) {
                self.playbackView.hidden = NO;
                self.progressBar.hidden = NO;
                self.playButton.enabled = self.asset.isPlayable;
                self.exportButton.enabled = NO;
                self.rateLabel.enabled = self.asset.isPlayable;
                self.rateSlider.enabled = self.asset.isPlayable;
            }
            break;
        case StatusExporting:
            self.playbackView.hidden = NO;
            self.progressBar.hidden = NO;
            break;
        default:
            break;
    }
}

- (void)showAlertForResult:(ExportResult)result
{
    NSString *title = @"";
    switch (result) {
        case ExportResultSuccess:
            title = NSLocalizedString(@"エクスポートに成功しました。", @"");
            break;
        case ExportResultFailure:
            title = NSLocalizedString(@"エクスポートに失敗しました。", @"");
            break;
        case ExportResultCancelled:
            title = NSLocalizedString(@"エクスポートがキャンセルされました。", @"");
            break;
        default:
            break;
    }

    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                                       message:nil
                                                                      delegate:nil
                                                             cancelButtonTitle:@"OK"
                                                             otherButtonTitles:nil];
                       [alert show];
                       self.progressBar.progress = 0;
                   });
}
@end

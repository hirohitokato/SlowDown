#import <Foundation/Foundation.h>

@interface CompositionUtility : NSObject
// ビデオトラックをフェードイン＆アウトするレイヤーインストラクションの作成。
+ (AVVideoCompositionLayerInstruction *)fadeVideoTrack:(AVAssetTrack *)track
                                             startTime:(CMTime)startTime
                                               endTime:(CMTime)endTime
                                          fadeDuration:(CMTime)fadeDuration;

// オーディオトラックをフェードイン＆アウトするオーディオ入力パラメータの作成。
+ (AVAudioMixInputParameters *)fadeAudioTrack:(AVAssetTrack *)track
                                    startTime:(CMTime)startTime
                                      endTime:(CMTime)endTime
                                 fadeDuration:(CMTime)fadeDuration;
@end

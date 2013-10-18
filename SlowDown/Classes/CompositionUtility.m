@import AVFoundation;
#import "CompositionUtility.h"

@implementation CompositionUtility
// ビデオトラックをフェードイン＆アウトするレイヤーインストラクションの作成。
+ (AVVideoCompositionLayerInstruction *)fadeVideoTrack:(AVAssetTrack *)track
                                             startTime:(CMTime)startTime
                                               endTime:(CMTime)endTime
                                          fadeDuration:(CMTime)fadeDuration {
    // 指定されたビデオトラックに対応するレイヤーインストラクションの作成。
    AVMutableVideoCompositionLayerInstruction *layerInst =
    [AVMutableVideoCompositionLayerInstruction
        videoCompositionLayerInstructionWithAssetTrack:track];

    // フェードインの設定。
    CMTimeRange timeRangeIn = CMTimeRangeMake(startTime, fadeDuration);
    [layerInst setOpacityRampFromStartOpacity:0
                                 toEndOpacity:1
                                    timeRange:timeRangeIn];

    // フェードアウトの設定。
    CMTime fadeoutStartTime = CMTimeSubtract(endTime, fadeDuration);
    CMTimeRange timeRangeOut = CMTimeRangeMake(fadeoutStartTime, fadeDuration);
    [layerInst setOpacityRampFromStartOpacity:1
                                 toEndOpacity:0
                                    timeRange:timeRangeOut];

    return layerInst;
}

// オーディオトラックをフェードイン＆アウトするオーディオ入力パラメータの作成。
+ (AVAudioMixInputParameters *)fadeAudioTrack:(AVAssetTrack *)track
                                    startTime:(CMTime)startTime
                                      endTime:(CMTime)endTime
                                 fadeDuration:(CMTime)fadeDuration {
    // 指定されたオーディオトラックに対応するオーディオ入力パラメータの作成。
    AVMutableAudioMixInputParameters *params =
    [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];

    // フェードインの設定。
    CMTimeRange timeRangeIn = CMTimeRangeMake(startTime, fadeDuration);
    [params setVolumeRampFromStartVolume:0
                             toEndVolume:1
                               timeRange:timeRangeIn];

    // フェードアウトの設定。
    CMTime fadeoutStartTime = CMTimeSubtract(endTime, fadeDuration);
    CMTimeRange timeRangeOut = CMTimeRangeMake(fadeoutStartTime, fadeDuration);
    [params setVolumeRampFromStartVolume:1
                             toEndVolume:0
                               timeRange:timeRangeOut];

    return params;
}

@end

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the Objective-C exception it raised, or nil.
///
/// AVFoundation reports misuse of AVAudioEngine with Objective-C exceptions. Swift can't catch
/// them, and one unwinding through Swift async frames corrupts the concurrency runtime, so
/// every call that can raise goes through here.
NSException *_Nullable VMCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END

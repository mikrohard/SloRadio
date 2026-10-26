//
//  SRToastView.h
//  SloRadio
//
//  Created by Jernej Fijačko on 26. 10. 26.
//  Copyright © 2026 Jernej Fijačko. All rights reserved.
//

#import <UIKit/UIKit.h>

// Short message on a floating platter at the top of the window. It hides by itself after a few seconds
// (or when tapped or swiped away) and never blocks the rest of the interface.
@interface SRToastView : UIView

// Shows the message in the view's window (replacing a toast that is already visible).
+ (void)showMessage:(NSString *)message inView:(UIView *)view;

// Hides the visible toast (e.g. when its message no longer applies).
+ (void)hideCurrentToast;

@end

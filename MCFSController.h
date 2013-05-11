
#import <Cocoa/Cocoa.h>

@class GMUserFileSystem;

@interface MCFSController : NSObject <NSApplicationDelegate> {
  GMUserFileSystem* fs_;
}

@end

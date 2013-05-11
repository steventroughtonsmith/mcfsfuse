
#import "MCFSController.h"
#import "MCFSFuseFileSystem.h"
#import <OSXFUSE/OSXFUSE.h>

@implementation MCFSController

- (void)didMount:(NSNotification *)notification {
	NSDictionary* userInfo = [notification userInfo];
	NSString* mountPath = [userInfo objectForKey:kGMUserFileSystemMountPathKey];
	NSString* parentPath = [mountPath stringByDeletingLastPathComponent];
	[[NSWorkspace sharedWorkspace] selectFile:mountPath
					 inFileViewerRootedAtPath:parentPath];
}

- (void)didUnmount:(NSNotification*)notification {
	[[NSApplication sharedApplication] terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(didMount:)
				   name:kGMUserFileSystemDidMount object:nil];
	[center addObserver:self selector:@selector(didUnmount:)
				   name:kGMUserFileSystemDidUnmount object:nil];
	
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
	NSString* mountPath = @"/Volumes/MCFS_DISK";
	MCFSFuseFileSystem* mcfs = [[MCFSFuseFileSystem alloc] init];
	fs_ = [[GMUserFileSystem alloc] initWithDelegate:mcfs isThreadSafe:YES];
	NSMutableArray* options = [NSMutableArray array];
	[options addObject:@"rdonly"];
	[options addObject:@"volname=MCFS_DISK"];
	[options addObject:[NSString stringWithFormat:@"volicon=%@",
						[[NSBundle mainBundle] pathForResource:@"Fuse" ofType:@"icns"]]];
	
	BOOL didLoad = [mcfs loadImage:filename];
	
	if (didLoad)
		[fs_ mountAtPath:mountPath withOptions:options];
	
	return didLoad;
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[fs_ unmount];  // Just in case we need to unmount;
	[[fs_ delegate] release];  // Clean up HelloFS
	[fs_ release];
	return NSTerminateNow;
}

@end

#import <Cocoa/Cocoa.h>

/* A Screen object representent one display on a machine */
@interface Screen : NSObject
{
@public
	NSRect					_frame;
	CGDirectDisplayID		_displayID;
	NSUInteger				_identifier;
}

- (NSRect) frame;
- (CGDirectDisplayID) displayID;
@end

/* A Screens object regroups all screenList present in the network */
@interface Screens : NSObject
{
@private
	NSMutableDictionary*	_screens;
	NSRect					_renderFrame;	// Render frame is smallest rect containing all screen rects
	NSUInteger				_hCount, _vCount;
	Screens*				_savedScreens;
	BOOL					_consolidated;
}

- (id) init;

/* Managing screens */
- (void) setSavedScreens:(Screens*)screens;
- (NSArray*) screensForKey:(NSString*)name;

- (void) setNSScreens:(NSArray*)nsScreens forKey:(NSString*)name;
- (void) setScreens:(NSArray*)screens forKey:(NSString*)name;

- (void) removeScreensForKey:(NSString*)name;
- (void) removeAllScreens;
- (NSArray*) flatten;
- (NSRect) renderFrame;

/* Moving screens around. Called by UI. */
- (void) moveLeftForKey:(NSString*)key;
- (void) moveRightForKey:(NSString*)key;
- (void) moveUpForKey:(NSString*)key;
- (void) moveDownForKey:(NSString*)key;
@end
